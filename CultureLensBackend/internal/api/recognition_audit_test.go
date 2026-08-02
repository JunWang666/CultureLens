package api

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/goudaijun/culturelens-backend/internal/recognition"
	"github.com/goudaijun/culturelens-backend/internal/recognitionaudit"
)

type fakeAuditWriter struct {
	records []recognitionaudit.Record
	err     error
}

func (w *fakeAuditWriter) SaveRecognitionRequest(
	_ context.Context,
	record recognitionaudit.Record,
) error {
	w.records = append(w.records, record)
	return w.err
}

type fakeAuditReader struct {
	items []recognitionaudit.Summary
	image recognitionaudit.Image
	err   error
}

func (r fakeAuditReader) RecentRecognitionRequests(
	_ context.Context,
	limit int,
) ([]recognitionaudit.Summary, error) {
	if r.err != nil {
		return nil, r.err
	}
	if limit < len(r.items) {
		return r.items[:limit], nil
	}
	return r.items, nil
}

func (r fakeAuditReader) RecognitionRequestImage(
	_ context.Context,
	_ int64,
	kind string,
) (recognitionaudit.Image, error) {
	if r.err != nil {
		return recognitionaudit.Image{}, r.err
	}
	if kind != "context" || len(r.image.Data) == 0 {
		return recognitionaudit.Image{}, recognitionaudit.ErrImageNotFound
	}
	return r.image, nil
}

func serverWithAudit(
	t *testing.T,
	writer recognitionaudit.Writer,
	reader recognitionaudit.Reader,
) http.Handler {
	t.Helper()
	return NewWithAdminAndAudit(
		recognition.NewPipeline(
			recognition.MockProvider{},
			testContentData(),
			"culturelens-mock-v1",
			"recognition-v5",
			"provider-recognition-v5",
		),
		testContentRepository{},
		&fakeAdminRepository{},
		writer,
		reader,
		slog.New(slog.NewTextHandler(io.Discard, nil)),
	)
}

func TestRecognitionAuditRecordsSuccessfulFullRequest(t *testing.T) {
	writer := &fakeAuditWriter{}
	body := `{"request_id":"request-1","image_base64":"` + jpegBase64(t) + `","mime_type":"image/jpeg","locale":"zh_CN","context_note":"檐下"}`
	request := httptest.NewRequest(http.MethodPost, "/v1/recognitions", strings.NewReader(body))
	response := httptest.NewRecorder()
	serverWithAudit(t, writer, fakeAuditReader{}).ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
	if len(writer.records) != 1 {
		t.Fatalf("audit records=%d", len(writer.records))
	}
	record := writer.records[0]
	image, _ := base64.StdEncoding.DecodeString(jpegBase64(t))
	if record.RequestID != "request-1" ||
		record.HTTPStatus != http.StatusOK ||
		record.ContextMIMEType != "image/jpeg" ||
		len(record.ContextImage) != len(image) ||
		record.ModelIdentifier != "culturelens-mock-v5" ||
		record.PromptVersion != "recognition-v5" ||
		record.CanonicalName == "" ||
		len(record.ResponsePayload) == 0 {
		t.Fatalf("unexpected audit record: %+v", record)
	}
	if strings.Contains(string(record.RequestPayload), "image_base64") ||
		!strings.Contains(string(record.RequestPayload), "context_note") {
		t.Fatalf("unexpected redacted request payload: %s", record.RequestPayload)
	}
}

func TestRecognitionAuditRecordsInvalidJSONWithoutRawBody(t *testing.T) {
	writer := &fakeAuditWriter{}
	request := httptest.NewRequest(http.MethodPost, "/v1/recognitions", strings.NewReader(`{"secret":`))
	response := httptest.NewRecorder()
	serverWithAudit(t, writer, fakeAuditReader{}).ServeHTTP(response, request)
	if response.Code != http.StatusBadRequest || len(writer.records) != 1 {
		t.Fatalf("status=%d records=%d body=%s", response.Code, len(writer.records), response.Body.String())
	}
	record := writer.records[0]
	if record.ErrorCode != "invalid_request" ||
		len(record.RequestPayload) != 0 ||
		len(record.ContextImage) != 0 ||
		record.RequestBodyBytes == 0 {
		t.Fatalf("unexpected invalid audit record: %+v", record)
	}
}

func TestRecognitionAuditFailureDoesNotChangeRecognitionResponse(t *testing.T) {
	writer := &fakeAuditWriter{err: errors.New("database unavailable")}
	body := `{"image_base64":"` + jpegBase64(t) + `","mime_type":"image/jpeg"}`
	request := httptest.NewRequest(http.MethodPost, "/v1/recognitions", strings.NewReader(body))
	response := httptest.NewRecorder()
	serverWithAudit(t, writer, fakeAuditReader{}).ServeHTTP(response, request)
	if response.Code != http.StatusOK || len(writer.records) != 1 {
		t.Fatalf("status=%d records=%d body=%s", response.Code, len(writer.records), response.Body.String())
	}
}

func TestRecognitionAuditAdminPageListAndImages(t *testing.T) {
	now := time.Now().UTC()
	reader := fakeAuditReader{
		items: []recognitionaudit.Summary{{
			ID:                   9,
			RequestID:            "request-9",
			ReceivedAt:           now,
			CompletedAt:          now,
			DurationMilliseconds: 12,
			HTTPStatus:           http.StatusOK,
			RequestPayload:       json.RawMessage(`{"locale":"zh_CN"}`),
			ResponsePayload:      json.RawMessage(`{"resolutionStatus":"resolved"}`),
			ContextMIMEType:      "image/jpeg",
			ContextImageBytes:    3,
			CanonicalName:        "斗拱",
		}},
		image: recognitionaudit.Image{MIMEType: "image/jpeg", Data: []byte{1, 2, 3}},
	}
	server := serverWithAudit(t, &fakeAuditWriter{}, reader)

	pageRequest := httptest.NewRequest(http.MethodGet, "/admin/recognitions", nil)
	pageResponse := httptest.NewRecorder()
	server.ServeHTTP(pageResponse, pageRequest)
	if pageResponse.Code != http.StatusOK ||
		pageResponse.Header().Get("Cache-Control") != "no-store" ||
		!strings.Contains(pageResponse.Body.String(), "最近识别请求") ||
		!strings.Contains(pageResponse.Body.String(), "/v1/admin/recognition-requests") {
		t.Fatalf("unexpected audit page: %d %s", pageResponse.Code, pageResponse.Body.String())
	}

	listRequest := httptest.NewRequest(http.MethodGet, "/v1/admin/recognition-requests?limit=100", nil)
	listResponse := httptest.NewRecorder()
	server.ServeHTTP(listResponse, listRequest)
	if listResponse.Code != http.StatusOK ||
		!strings.Contains(listResponse.Body.String(), "request-9") ||
		strings.Contains(listResponse.Body.String(), "AQID") {
		t.Fatalf("unexpected audit list: %d %s", listResponse.Code, listResponse.Body.String())
	}

	imageRequest := httptest.NewRequest(http.MethodGet, "/v1/admin/recognition-requests/9/images/context", nil)
	imageResponse := httptest.NewRecorder()
	server.ServeHTTP(imageResponse, imageRequest)
	if imageResponse.Code != http.StatusOK ||
		imageResponse.Header().Get("Content-Type") != "image/jpeg" ||
		imageResponse.Header().Get("Cache-Control") != "no-store" ||
		imageResponse.Body.String() != string([]byte{1, 2, 3}) {
		t.Fatalf("unexpected image response: %d %v", imageResponse.Code, imageResponse.Header())
	}
}

func TestRecognitionAuditAdminDisabledAndValidation(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/v1/admin/recognition-requests", nil)
	response := httptest.NewRecorder()
	testServer().ServeHTTP(response, request)
	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("disabled status=%d body=%s", response.Code, response.Body.String())
	}

	request = httptest.NewRequest(http.MethodGet, "/v1/admin/recognition-requests?limit=101", nil)
	response = httptest.NewRecorder()
	serverWithAudit(t, &fakeAuditWriter{}, fakeAuditReader{}).ServeHTTP(response, request)
	if response.Code != http.StatusBadRequest {
		t.Fatalf("invalid limit status=%d body=%s", response.Code, response.Body.String())
	}

	request = httptest.NewRequest(http.MethodGet, "/v1/admin/recognition-requests/9/images/focus", nil)
	response = httptest.NewRecorder()
	serverWithAudit(t, &fakeAuditWriter{}, fakeAuditReader{}).ServeHTTP(response, request)
	if response.Code != http.StatusNotFound {
		t.Fatalf("missing image status=%d body=%s", response.Code, response.Body.String())
	}
}
