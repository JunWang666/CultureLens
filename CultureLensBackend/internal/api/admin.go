package api

import (
	_ "embed"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/goudaijun/culturelens-backend/internal/contentadmin"
)

const maximumAdminBodyBytes = 2 << 20

//go:embed admin.html
var adminPageHTML []byte

func (s Server) adminPage(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set(
		"Content-Security-Policy",
		"default-src 'self'; style-src 'unsafe-inline'; "+
			"script-src 'unsafe-inline'; connect-src 'self'; "+
			"img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'",
	)
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(adminPageHTML)
}

func (s Server) adminSnapshot(w http.ResponseWriter, r *http.Request) {
	if !s.authorizeAdmin(w, r) {
		return
	}
	snapshot, err := s.admin.Snapshot(r.Context())
	if err != nil {
		s.adminFailure(w, r, "list content", "", err)
		return
	}
	writeJSON(w, http.StatusOK, snapshot)
}

func (s Server) adminUpsertElement(w http.ResponseWriter, r *http.Request) {
	if !s.authorizeAdmin(w, r) {
		return
	}
	var element contentadmin.CulturalElement
	if err := decodeAdminJSON(w, r, &element); err != nil ||
		element.Key != strings.TrimSpace(r.PathValue("elementKey")) ||
		contentadmin.ValidateElement(element) != nil {
		s.writeError(w, r, http.StatusBadRequest, "invalid_request", "请求参数无效。", false)
		return
	}
	saved, err := s.admin.UpsertElement(r.Context(), element)
	if err != nil {
		s.adminFailure(w, r, "upsert cultural element", element.Key, err)
		return
	}
	s.adminSuccess(r, "upsert cultural element", element.Key)
	writeJSON(w, http.StatusOK, saved)
}

func (s Server) adminUpsertAttraction(w http.ResponseWriter, r *http.Request) {
	if !s.authorizeAdmin(w, r) {
		return
	}
	var attraction contentadmin.Attraction
	if err := decodeAdminJSON(w, r, &attraction); err != nil ||
		attraction.Key != strings.TrimSpace(r.PathValue("attractionKey")) ||
		contentadmin.ValidateAttraction(attraction) != nil {
		s.writeError(w, r, http.StatusBadRequest, "invalid_request", "请求参数无效。", false)
		return
	}
	saved, err := s.admin.UpsertAttraction(r.Context(), attraction)
	if err != nil {
		s.adminFailure(w, r, "upsert attraction", attraction.Key, err)
		return
	}
	s.adminSuccess(r, "upsert attraction", attraction.Key)
	writeJSON(w, http.StatusOK, saved)
}

func (s Server) adminUpsertIntroduction(w http.ResponseWriter, r *http.Request) {
	if !s.authorizeAdmin(w, r) {
		return
	}
	var introduction contentadmin.AttractionIntroduction
	if err := decodeAdminJSON(w, r, &introduction); err != nil ||
		introduction.Key != strings.TrimSpace(r.PathValue("introductionKey")) ||
		contentadmin.ValidateIntroduction(introduction) != nil {
		s.writeError(w, r, http.StatusBadRequest, "invalid_request", "请求参数无效。", false)
		return
	}
	saved, err := s.admin.UpsertIntroduction(r.Context(), introduction)
	if err != nil {
		s.adminFailure(w, r, "upsert attraction introduction", introduction.Key, err)
		return
	}
	s.adminSuccess(r, "upsert attraction introduction", introduction.Key)
	writeJSON(w, http.StatusOK, saved)
}

func (s Server) adminUpsertRelation(w http.ResponseWriter, r *http.Request) {
	if !s.authorizeAdmin(w, r) {
		return
	}
	relation := contentadmin.Relation{
		ElementKey:        strings.TrimSpace(r.PathValue("elementKey")),
		RelatedElementKey: strings.TrimSpace(r.PathValue("relatedElementKey")),
	}
	if contentadmin.ValidateRelation(relation) != nil {
		s.writeError(w, r, http.StatusBadRequest, "invalid_request", "请求参数无效。", false)
		return
	}
	if err := s.admin.UpsertRelation(r.Context(), relation); err != nil {
		s.adminFailure(w, r, "upsert cultural element relation", relation.ElementKey, err)
		return
	}
	s.adminSuccess(r, "upsert cultural element relation", relation.ElementKey)
	writeJSON(w, http.StatusOK, relation)
}

func (s Server) adminImport(w http.ResponseWriter, r *http.Request) {
	if !s.authorizeAdmin(w, r) {
		return
	}
	var bundle contentadmin.Bundle
	if err := decodeAdminJSON(w, r, &bundle); err != nil ||
		contentadmin.ValidateBundle(bundle) != nil {
		s.writeError(w, r, http.StatusBadRequest, "invalid_request", "导入内容无效。", false)
		return
	}
	result, err := s.admin.Import(r.Context(), bundle)
	if err != nil {
		s.adminFailure(w, r, "import content bundle", bundle.Version, err)
		return
	}
	s.adminSuccess(r, "import content bundle", bundle.Version)
	writeJSON(w, http.StatusOK, result)
}

func (s Server) authorizeAdmin(w http.ResponseWriter, r *http.Request) bool {
	w.Header().Set("Cache-Control", "no-store")
	if !s.adminOn {
		s.writeError(
			w,
			r,
			http.StatusServiceUnavailable,
			"admin_unavailable",
			"内容管理服务未启用。",
			true,
		)
		return false
	}
	return true
}

func decodeAdminJSON(w http.ResponseWriter, r *http.Request, target any) error {
	defer r.Body.Close()
	r.Body = http.MaxBytesReader(w, r.Body, maximumAdminBodyBytes)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return errors.New("request must contain one JSON document")
	}
	return nil
}

func (s Server) adminFailure(
	w http.ResponseWriter,
	r *http.Request,
	operation string,
	key string,
	err error,
) {
	s.logger.Error(
		"content admin operation failed",
		"request_id",
		requestID(r.Context()),
		"operation",
		operation,
		"resource_key",
		key,
		"error",
		err,
	)
	s.writeError(
		w,
		r,
		http.StatusServiceUnavailable,
		"admin_write_failed",
		"内容保存失败，请稍后重试。",
		true,
	)
}

func (s Server) adminSuccess(r *http.Request, operation string, key string) {
	s.logger.Info(
		"content admin operation completed",
		"request_id",
		requestID(r.Context()),
		"operation",
		operation,
		"resource_key",
		key,
	)
}
