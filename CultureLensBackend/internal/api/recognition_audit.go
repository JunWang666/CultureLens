package api

import (
	"context"
	_ "embed"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/goudaijun/culturelens-backend/internal/recognition"
	"github.com/goudaijun/culturelens-backend/internal/recognitionaudit"
)

//go:embed recognition_audit.html
var recognitionAuditPageHTML []byte

type recognitionAuditRequest struct {
	RequestID     string                `json:"request_id"`
	MIMEType      string                `json:"mime_type"`
	FocusMIMEType string                `json:"focus_mime_type,omitempty"`
	Location      *recognition.Location `json:"location,omitempty"`
	ContextNote   string                `json:"context_note,omitempty"`
	Locale        string                `json:"locale,omitempty"`
}

func (s Server) recognitionAuditPage(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set(
		"Content-Security-Policy",
		"default-src 'self'; style-src 'unsafe-inline'; "+
			"script-src 'unsafe-inline'; connect-src 'self'; "+
			"img-src 'self'; base-uri 'none'; frame-ancestors 'none'",
	)
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(recognitionAuditPageHTML)
}

func (s Server) saveRecognitionAudit(
	r *http.Request,
	receivedAt time.Time,
	req *recognition.Request,
	requestBodyBytes int64,
	status int,
	errorCode string,
	responsePayload any,
) {
	if s.auditWriter == nil {
		return
	}
	completedAt := time.Now().UTC()
	record := recognitionaudit.Record{
		RequestID:            requestID(r.Context()),
		ReceivedAt:           receivedAt,
		CompletedAt:          completedAt,
		DurationMilliseconds: max(completedAt.Sub(receivedAt).Milliseconds(), 0),
		HTTPStatus:           status,
		ErrorCode:            errorCode,
		RequestBodyBytes:     requestBodyBytes,
		ResponsePayload:      marshalAuditJSON(responsePayload),
	}
	if req != nil {
		record.RequestID = req.RequestID
		record.RequestPayload = marshalAuditJSON(recognitionAuditRequest{
			RequestID:     req.RequestID,
			MIMEType:      req.MIMEType,
			FocusMIMEType: req.FocusMIMEType,
			Location:      req.Location,
			ContextNote:   req.ContextNote,
			Locale:        req.Locale,
		})
		record.ContextImage = decodeAuditImage(req.ImageBase64)
		if len(record.ContextImage) > 0 {
			record.ContextMIMEType = auditImageMIMEType(req.MIMEType)
		}
		record.FocusImage = decodeAuditImage(req.FocusImageBase64)
		if len(record.FocusImage) > 0 {
			record.FocusMIMEType = auditImageMIMEType(req.FocusMIMEType)
		}
	}
	if response, ok := responsePayload.(recognition.Response); ok {
		record.ModelIdentifier = response.ModelIdentifier
		record.PromptVersion = response.PromptVersion
		record.SchemaVersion = response.SchemaVersion
		record.ResolutionStatus = response.ResolutionStatus
		record.CulturalElementKey = response.Object.CulturalElementKey
		record.CanonicalName = response.Object.CanonicalName
	}
	auditContext, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), 3*time.Second)
	defer cancel()
	if err := s.auditWriter.SaveRecognitionRequest(auditContext, record); err != nil {
		s.logger.Error(
			"save recognition request audit",
			"request_id",
			record.RequestID,
			"http_status",
			status,
			"error",
			err,
		)
	}
}

func decodeAuditImage(encoded string) []byte {
	if strings.TrimSpace(encoded) == "" {
		return nil
	}
	decoded, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return nil
	}
	return decoded
}

func auditImageMIMEType(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "image/jpeg":
		return "image/jpeg"
	case "image/png":
		return "image/png"
	default:
		return "application/octet-stream"
	}
}

func marshalAuditJSON(value any) json.RawMessage {
	data, err := json.Marshal(value)
	if err != nil {
		return json.RawMessage(`{"audit_encoding_error":true}`)
	}
	return data
}

func (s Server) adminRecognitionRequests(w http.ResponseWriter, r *http.Request) {
	if !s.authorizeRecognitionAudit(w, r) {
		return
	}
	limit := 100
	if raw := strings.TrimSpace(r.URL.Query().Get("limit")); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 1 || parsed > 100 {
			s.writeError(w, r, http.StatusBadRequest, "invalid_request", "limit 必须在 1 到 100 之间。", false)
			return
		}
		limit = parsed
	}
	items, err := s.auditReader.RecentRecognitionRequests(r.Context(), limit)
	if err != nil {
		s.logger.Error("list recognition request audits", "request_id", requestID(r.Context()), "error", err)
		s.writeError(w, r, http.StatusServiceUnavailable, "audit_unavailable", "识别请求记录暂时不可用。", true)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"requests": items})
}

func (s Server) adminRecognitionRequestImage(w http.ResponseWriter, r *http.Request) {
	if !s.authorizeRecognitionAudit(w, r) {
		return
	}
	id, err := strconv.ParseInt(strings.TrimSpace(r.PathValue("auditID")), 10, 64)
	if err != nil || id < 1 {
		s.writeError(w, r, http.StatusBadRequest, "invalid_request", "请求记录 ID 无效。", false)
		return
	}
	image, err := s.auditReader.RecognitionRequestImage(r.Context(), id, r.PathValue("kind"))
	if err != nil {
		if errors.Is(err, recognitionaudit.ErrImageNotFound) {
			s.writeError(w, r, http.StatusNotFound, "image_not_found", "这条请求没有对应图片。", false)
			return
		}
		s.logger.Error("read recognition request image", "request_id", requestID(r.Context()), "audit_id", id, "error", err)
		s.writeError(w, r, http.StatusServiceUnavailable, "audit_unavailable", "识别请求图片暂时不可用。", true)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Type", image.MIMEType)
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(image.Data)
}

func (s Server) authorizeRecognitionAudit(w http.ResponseWriter, r *http.Request) bool {
	w.Header().Set("Cache-Control", "no-store")
	if !s.adminOn || s.auditReader == nil {
		s.writeError(w, r, http.StatusServiceUnavailable, "audit_unavailable", "识别请求记录服务未启用。", true)
		return false
	}
	return true
}
