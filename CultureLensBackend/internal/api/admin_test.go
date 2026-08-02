package api

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/goudaijun/culturelens-backend/internal/contentadmin"
	"github.com/goudaijun/culturelens-backend/internal/recognition"
)

type fakeAdminRepository struct {
	snapshot contentadmin.Snapshot
	lastKey  string
}

func (r *fakeAdminRepository) Snapshot(context.Context) (contentadmin.Snapshot, error) {
	return r.snapshot, nil
}

func (r *fakeAdminRepository) UpsertElement(
	_ context.Context,
	element contentadmin.CulturalElement,
) (contentadmin.CulturalElement, error) {
	r.lastKey = element.Key
	return element, nil
}

func (r *fakeAdminRepository) UpsertAttraction(
	_ context.Context,
	attraction contentadmin.Attraction,
) (contentadmin.Attraction, error) {
	r.lastKey = attraction.Key
	return attraction, nil
}

func (r *fakeAdminRepository) UpsertIntroduction(
	_ context.Context,
	introduction contentadmin.AttractionIntroduction,
) (contentadmin.AttractionIntroduction, error) {
	r.lastKey = introduction.Key
	return introduction, nil
}

func (r *fakeAdminRepository) UpsertRelation(
	_ context.Context,
	relation contentadmin.Relation,
) error {
	r.lastKey = relation.ElementKey + ":" + relation.RelatedElementKey
	return nil
}

func (r *fakeAdminRepository) Import(
	_ context.Context,
	bundle contentadmin.Bundle,
) (contentadmin.ImportResult, error) {
	r.lastKey = bundle.Version
	return contentadmin.ImportResult{
		Version:       bundle.Version,
		Elements:      len(bundle.Elements),
		Attractions:   len(bundle.Attractions),
		Relations:     len(bundle.Relations),
		Introductions: len(bundle.Introductions),
	}, nil
}

func serverWithAdmin(t *testing.T, repository contentadmin.Repository) http.Handler {
	t.Helper()
	return NewWithAdmin(
		recognition.NewPipeline(
			recognition.MockProvider{},
			testContentData(),
			"culturelens-mock-v1",
			"recognition-v5",
			"provider-recognition-v5",
		),
		testContentRepository{},
		repository,
		slog.New(slog.NewTextHandler(io.Discard, nil)),
	)
}

func TestAdminPageSecurityContract(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/admin", nil)
	response := httptest.NewRecorder()
	testServer().ServeHTTP(response, request)
	if response.Code != http.StatusOK ||
		response.Header().Get("Cache-Control") != "no-store" ||
		response.Header().Get("Content-Security-Policy") == "" {
		t.Fatalf("unexpected admin page response: %d %v", response.Code, response.Header())
	}
	body := response.Body.String()
	for _, expected := range []string{
		"CultureLens 内容管理",
		"Cloudflare Zero Trust",
		"/v1/admin/attraction-introductions/",
		"Latitude",
		"Longitude",
	} {
		if !strings.Contains(body, expected) {
			t.Fatalf("admin page is missing %q", expected)
		}
	}
	for _, forbidden := range []string{"sessionStorage", "Authorization", "CULTURELENS_ADMIN_TOKEN", "管理令牌"} {
		if strings.Contains(body, forbidden) {
			t.Fatalf("admin page must not contain %q", forbidden)
		}
	}
}

func TestAdminRoutesAreExcludedFromPublicOpenAPI(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/openapi.json", nil)
	response := httptest.NewRecorder()
	testServer().ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
	if strings.Contains(response.Body.String(), "/v1/admin/") {
		t.Fatal("public OpenAPI must not advertise admin routes")
	}
}

func TestAdminAPIRequiresOnlyAdminRepositoryConfiguration(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/v1/admin/content", nil)
	response := httptest.NewRecorder()
	testServer().ServeHTTP(response, request)
	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("disabled status=%d body=%s", response.Code, response.Body.String())
	}

	request = httptest.NewRequest(http.MethodGet, "/v1/admin/content", nil)
	response = httptest.NewRecorder()
	serverWithAdmin(t, &fakeAdminRepository{}).ServeHTTP(response, request)
	if response.Code != http.StatusOK || response.Header().Get("WWW-Authenticate") != "" {
		t.Fatalf("enabled status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestAdminSnapshotAndIntroductionUpsert(t *testing.T) {
	repository := &fakeAdminRepository{snapshot: contentadmin.Snapshot{
		Elements:      []contentadmin.CulturalElement{},
		Attractions:   []contentadmin.Attraction{},
		Relations:     []contentadmin.Relation{},
		Introductions: []contentadmin.AttractionIntroduction{},
	}}
	request := httptest.NewRequest(http.MethodGet, "/v1/admin/content", nil)
	response := httptest.NewRecorder()
	serverWithAdmin(t, repository).ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
	var snapshot contentadmin.Snapshot
	if err := json.NewDecoder(response.Body).Decode(&snapshot); err != nil {
		t.Fatal(err)
	}
	if snapshot.Elements == nil || snapshot.Introductions == nil {
		t.Fatalf("admin lists must be non-null: %+v", snapshot)
	}

	input := contentadmin.AttractionIntroduction{
		Key:                 "leifeng-pagoda.lake-landscape",
		Name:                "雷峰塔的湖山位置",
		Introduction:        json.RawMessage(`{"schemaVersion":1,"blocks":[{"type":"paragraph","text":"正文"}]}`),
		CulturalElementKey:  "west-lake-pagoda-landscape",
		AttractionKey:       "leifeng-pagoda",
		Latitude:            30.233889,
		Longitude:           120.145,
		CoordinateSourceURL: "https://www.wikidata.org/",
	}
	body, _ := json.Marshal(input)
	request = httptest.NewRequest(
		http.MethodPut,
		"/v1/admin/attraction-introductions/"+input.Key,
		bytes.NewReader(body),
	)
	response = httptest.NewRecorder()
	serverWithAdmin(t, repository).ServeHTTP(response, request)
	if response.Code != http.StatusOK || repository.lastKey != input.Key {
		t.Fatalf("status=%d key=%q body=%s", response.Code, repository.lastKey, response.Body.String())
	}
}

func TestAdminRejectsInvalidCoordinateAndPathMismatch(t *testing.T) {
	repository := &fakeAdminRepository{}
	for _, test := range []struct {
		path string
		body string
	}{
		{
			path: "/v1/admin/attraction-introductions/bad-coordinate",
			body: `{"key":"bad-coordinate","name":"无效","introduction":{"schemaVersion":1,"blocks":[{"type":"paragraph","text":"正文"}]},"culturalElementKey":"element","attractionKey":"attraction","latitude":91,"longitude":120}`,
		},
		{
			path: "/v1/admin/attractions/path-key",
			body: `{"key":"body-key","name":"不一致"}`,
		},
	} {
		request := httptest.NewRequest(http.MethodPut, test.path, strings.NewReader(test.body))
		response := httptest.NewRecorder()
		serverWithAdmin(t, repository).ServeHTTP(response, request)
		if response.Code != http.StatusBadRequest {
			t.Fatalf("path=%s status=%d body=%s", test.path, response.Code, response.Body.String())
		}
	}
}
