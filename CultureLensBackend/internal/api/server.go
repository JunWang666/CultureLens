package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/goudaijun/culturelens-backend/internal/contentadmin"
	"github.com/goudaijun/culturelens-backend/internal/knowledge"
	"github.com/goudaijun/culturelens-backend/internal/recognition"
	"github.com/goudaijun/culturelens-backend/internal/recognitionaudit"
)

type Server struct {
	pipeline    recognition.Pipeline
	content     knowledge.ContentRepository
	admin       contentadmin.Repository
	adminOn     bool
	auditWriter recognitionaudit.Writer
	auditReader recognitionaudit.Reader
	logger      *slog.Logger
}

func New(
	p recognition.Pipeline,
	contentRepository knowledge.ContentRepository,
	logger *slog.Logger,
) http.Handler {
	return NewWithAdmin(
		p,
		contentRepository,
		nil,
		logger,
	)
}

func NewWithAdmin(
	p recognition.Pipeline,
	contentRepository knowledge.ContentRepository,
	adminRepository contentadmin.Repository,
	logger *slog.Logger,
) http.Handler {
	return NewWithAdminAndAudit(
		p,
		contentRepository,
		adminRepository,
		nil,
		nil,
		logger,
	)
}

func NewWithAdminAndAudit(
	p recognition.Pipeline,
	contentRepository knowledge.ContentRepository,
	adminRepository contentadmin.Repository,
	auditWriter recognitionaudit.Writer,
	auditReader recognitionaudit.Reader,
	logger *slog.Logger,
) http.Handler {
	return Server{
		pipeline:    p,
		content:     contentRepository,
		admin:       adminRepository,
		adminOn:     adminRepository != nil,
		auditWriter: auditWriter,
		auditReader: auditReader,
		logger:      logger,
	}.routes()
}
func (s Server) routes() http.Handler {
	businessMux := http.NewServeMux()
	businessMux.HandleFunc("GET /admin", s.adminPage)
	businessMux.HandleFunc("GET /admin/recognitions", s.recognitionAuditPage)
	businessMux.HandleFunc("GET /debug", s.debug)
	businessMux.HandleFunc("GET /health", s.health)
	businessMux.HandleFunc("POST /v1/recognitions", s.recognize)
	businessMux.HandleFunc(
		"GET /v1/attraction-introductions/recommendations",
		s.recommendAttractionIntroductions,
	)
	businessMux.HandleFunc(
		"GET /v1/cultural-elements/{elementKey}/related",
		s.relatedCulturalElements,
	)
	businessMux.HandleFunc("GET /v1/admin/content", s.adminSnapshot)
	businessMux.HandleFunc(
		"GET /v1/admin/recognition-requests",
		s.adminRecognitionRequests,
	)
	businessMux.HandleFunc(
		"GET /v1/admin/recognition-requests/{auditID}/images/{kind}",
		s.adminRecognitionRequestImage,
	)
	businessMux.HandleFunc("PUT /v1/admin/content/import", s.adminImport)
	businessMux.HandleFunc(
		"PUT /v1/admin/cultural-elements/{elementKey}",
		s.adminUpsertElement,
	)
	businessMux.HandleFunc(
		"PUT /v1/admin/attractions/{attractionKey}",
		s.adminUpsertAttraction,
	)
	businessMux.HandleFunc(
		"PUT /v1/admin/attraction-introductions/{introductionKey}",
		s.adminUpsertIntroduction,
	)
	businessMux.HandleFunc(
		"PUT /v1/admin/cultural-element-relations/{elementKey}/{relatedElementKey}",
		s.adminUpsertRelation,
	)
	documentation := newDocumentationHandler()
	return s.withRequestID(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if isDocumentationPath(r.URL.Path) {
			documentation.ServeHTTP(w, r)
			return
		}
		businessMux.ServeHTTP(w, r)
	}))
}
func (s Server) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
func (s Server) recognize(w http.ResponseWriter, r *http.Request) {
	receivedAt := time.Now().UTC()
	defer r.Body.Close()
	r.Body = http.MaxBytesReader(w, r.Body, 18<<20)
	body, err := io.ReadAll(r.Body)
	if err != nil {
		payload := errorEnvelope(r, "invalid_request", "请求格式无效。", false)
		s.saveRecognitionAudit(r, receivedAt, nil, int64(len(body)), http.StatusBadRequest, "invalid_request", payload)
		writeJSON(w, http.StatusBadRequest, payload)
		return
	}
	var req recognition.Request
	if err := json.Unmarshal(body, &req); err != nil {
		payload := errorEnvelope(r, "invalid_request", "请求格式无效。", false)
		s.saveRecognitionAudit(r, receivedAt, nil, int64(len(body)), http.StatusBadRequest, "invalid_request", payload)
		writeJSON(w, http.StatusBadRequest, payload)
		return
	}
	if req.RequestID == "" {
		req.RequestID = requestID(r.Context())
	}
	response, err := s.pipeline.Recognize(r.Context(), req)
	if err != nil {
		status, code, message, retry := mapError(err)
		payload := errorEnvelope(r, code, message, retry)
		s.saveRecognitionAudit(r, receivedAt, &req, int64(len(body)), status, code, payload)
		writeJSON(w, status, payload)
		return
	}
	s.logger.Info(
		"recognition completed",
		"request_id",
		req.RequestID,
		"used_place_context",
		req.Location != nil,
		"used_focus_image",
		req.FocusImageBase64 != "",
		"knowledge_version",
		response.CatalogVersion,
		"knowledge_candidates",
		response.CatalogCandidateCount,
		"resolution_status",
		response.ResolutionStatus,
	)
	s.saveRecognitionAudit(r, receivedAt, &req, int64(len(body)), http.StatusOK, "", response)
	writeJSON(w, http.StatusOK, response)
}
func (s Server) writeError(w http.ResponseWriter, r *http.Request, status int, code, message string, retry bool) {
	writeJSON(w, status, errorEnvelope(r, code, message, retry))
}

func errorEnvelope(r *http.Request, code, message string, retry bool) map[string]any {
	return map[string]any{"request_id": requestID(r.Context()), "error": map[string]any{"code": code, "message": message, "retryable": retry}}
}
func mapError(err error) (int, string, string, bool) {
	switch {
	case errors.Is(err, recognition.ErrInvalidRequest):
		return 400, "invalid_request", "请求参数无效。", false
	case errors.Is(err, recognition.ErrImageTooLarge):
		return 413, "image_too_large", "图片过大，请选择较小的图片。", false
	case errors.Is(err, recognition.ErrUnsupportedImage):
		return 415, "unsupported_image", "暂不支持此图片格式。", false
	case errors.Is(err, context.DeadlineExceeded) || strings.Contains(err.Error(), "timeout"):
		return 504, "recognition_upstream_timeout", "识别服务暂时不可用，请稍后重试。", true
	case strings.Contains(err.Error(), "invalid provider output"):
		return 502, "recognition_invalid_output", "识别结果暂时无法验证，请稍后重试。", true
	default:
		return 503, "recognition_unavailable", "识别服务暂时不可用，请稍后重试。", true
	}
}
func (s Server) withRequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := strings.TrimSpace(r.Header.Get("X-Request-ID"))
		if id == "" {
			id = uuid.NewString()
		}
		w.Header().Set("X-Request-ID", id)
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), requestIDKey{}, id)))
	})
}

type requestIDKey struct{}

func requestID(ctx context.Context) string {
	if id, ok := ctx.Value(requestIDKey{}).(string); ok {
		return id
	}
	return uuid.NewString()
}
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
