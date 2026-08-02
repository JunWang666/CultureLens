package googleai

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/goudaijun/culturelens-backend/internal/recognition"
)

func TestProviderSendsGeminiVisionRequest(t *testing.T) {
	client := &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		if r.URL.Path != "/v1beta/models/gemini-3.6-flash:generateContent" {
			t.Fatalf("path=%s", r.URL.Path)
		}
		if r.Header.Get("x-goog-api-key") != "token" {
			t.Fatal("missing Gemini key")
		}
		var request generateContentRequest
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Fatal(err)
		}
		if request.GenerationConfig.ResponseMIMEType != "application/json" ||
			request.GenerationConfig.ResponseJSONSchema["type"] != "object" ||
			request.Contents[0].Parts[1].InlineData == nil ||
			request.Contents[0].Parts[1].MediaResolution.Level != mediaResolutionHigh {
			t.Fatalf("unexpected Gemini request: %+v", request)
		}
		if !strings.Contains(request.Contents[0].Parts[0].Text, `"name":"斗拱"`) ||
			!strings.Contains(request.Contents[0].Parts[0].Text, `"key":"timber-bracket"`) ||
			!strings.Contains(request.Contents[0].Parts[0].Text, `"attraction_name":"灵隐寺"`) ||
			!strings.Contains(request.Contents[0].Parts[0].Text, "优先逐项对照") ||
			strings.Contains(request.Contents[0].Parts[0].Text, `"latitude"`) ||
			strings.Contains(request.Contents[0].Parts[0].Text, `"city_name"`) {
			t.Fatalf("unexpected reviewed catalog context: %q", request.Contents[0].Parts[0].Text)
		}
		return &http.Response{StatusCode: http.StatusOK, Body: io.NopCloser(strings.NewReader(`{"candidates":[{"content":{"parts":[{"text":"{\"cultural_element_key\":\"timber-bracket\",\"canonical_name\":\"斗拱\",\"category\":\"建筑构件\",\"confidence\":0.9,\"summary\":\"木构件\",\"rationale\":\"层叠出跳\",\"uncertainty\":\"需结合现场资料核验\",\"time_period\":\"宋\",\"region\":\"中国\",\"alternatives\":[]}"}]}}]}`)), Header: make(http.Header)}, nil
	})}
	promptPath, schemaPath := providerFiles(t)
	provider, err := New("https://generativelanguage.googleapis.com/v1beta", []string{"token"}, "gemini-3.6-flash", promptPath, schemaPath)
	if err != nil {
		t.Fatal(err)
	}
	provider.client = client
	result, model, err := provider.Recognize(
		context.Background(),
		recognition.MediaInput{ContextImage: []byte("jpeg"), ContextMIME: "image/jpeg"},
		reviewedProviderInput(),
	)
	if err != nil {
		t.Fatal(err)
	}
	if result.CanonicalName != "斗拱" || model != "gemini-3.6-flash" {
		t.Fatalf("unexpected result: %+v %s", result, model)
	}
}

func TestProviderUsesContextAndFocusedImage(t *testing.T) {
	client := &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		var request generateContentRequest
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Fatal(err)
		}
		parts := request.Contents[0].Parts
		if len(parts) != 5 {
			t.Fatalf("parts=%d, want 5", len(parts))
		}
		if parts[2].InlineData == nil ||
			parts[2].MediaResolution.Level != mediaResolutionMedium ||
			parts[4].InlineData == nil ||
			parts[4].MediaResolution.Level != mediaResolutionHigh {
			t.Fatalf("unexpected focused parts: %+v", parts)
		}
		if !strings.Contains(parts[3].Text, "用户框选") {
			t.Fatalf("missing focus instruction: %q", parts[3].Text)
		}
		return &http.Response{StatusCode: http.StatusOK, Body: io.NopCloser(strings.NewReader(`{"candidates":[{"content":{"parts":[{"text":"{\"cultural_element_key\":\"timber-bracket\",\"canonical_name\":\"斗拱\",\"category\":\"建筑构件\",\"confidence\":0.9,\"summary\":\"木构件\",\"rationale\":\"层叠出跳\",\"uncertainty\":\"需结合现场资料核验\",\"time_period\":\"宋\",\"region\":\"中国\",\"alternatives\":[{\"cultural_element_key\":\"\",\"canonical_name\":\"雀替\",\"category\":\"建筑构件\",\"confidence\":0.3,\"rationale\":\"缺少层叠出跳\"}]}"}]}}]}`)), Header: make(http.Header)}, nil
	})}
	promptPath, schemaPath := providerFiles(t)
	provider, err := New("https://generativelanguage.googleapis.com/v1beta", []string{"token"}, "gemini-3.6-flash", promptPath, schemaPath)
	if err != nil {
		t.Fatal(err)
	}
	provider.client = client
	_, _, err = provider.Recognize(
		context.Background(),
		recognition.MediaInput{
			ContextImage: []byte("context"),
			ContextMIME:  "image/jpeg",
			FocusImage:   []byte("focus"),
			FocusMIME:    "image/jpeg",
		},
		reviewedProviderInput(),
	)
	if err != nil {
		t.Fatal(err)
	}
}

func TestProviderRotatesOnlyAfterRateLimit(t *testing.T) {
	keys := []string{"first", "second", "third"}
	calls := 0
	client := &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		if got := r.Header.Get("x-goog-api-key"); got != keys[calls] {
			t.Fatalf("call %d key=%q", calls, got)
		}
		calls++
		if calls == 1 {
			return &http.Response{StatusCode: http.StatusTooManyRequests, Body: io.NopCloser(strings.NewReader(`{"error":{"status":"RESOURCE_EXHAUSTED"}}`)), Header: make(http.Header)}, nil
		}
		return &http.Response{StatusCode: http.StatusOK, Body: io.NopCloser(strings.NewReader(`{"candidates":[{"content":{"parts":[{"text":"{\"cultural_element_key\":\"timber-bracket\",\"canonical_name\":\"斗拱\",\"category\":\"建筑构件\",\"confidence\":0.9,\"summary\":\"木构件\",\"rationale\":\"层叠出跳\",\"uncertainty\":\"需结合现场资料核验\",\"time_period\":\"宋\",\"region\":\"中国\",\"alternatives\":[]}"}]}}]}`)), Header: make(http.Header)}, nil
	})}
	promptPath, schemaPath := providerFiles(t)
	provider, err := New("https://generativelanguage.googleapis.com/v1beta", keys, "gemini-3.6-flash", promptPath, schemaPath)
	if err != nil {
		t.Fatal(err)
	}
	provider.client = client
	if _, _, err := provider.Recognize(context.Background(), recognition.MediaInput{ContextImage: []byte("jpeg"), ContextMIME: "image/jpeg"}, reviewedProviderInput()); err != nil {
		t.Fatal(err)
	}
	if calls != 2 {
		t.Fatalf("calls=%d, want 2", calls)
	}
}

func reviewedProviderInput() recognition.ProviderInput {
	return recognition.ProviderInput{
		Request: recognition.Request{
			Location: &recognition.Location{
				Latitude:   31.23,
				Longitude:  121.47,
				CityName:   "上海市",
				RegionCode: "CN",
			},
		},
		KnowledgeCandidates: []recognition.KnowledgeCandidateContext{{
			Key:          "timber-bracket",
			Name:         "斗拱",
			Introduction: json.RawMessage(`{"schemaVersion":1,"blocks":[{"type":"paragraph","text":"传统木构件"}]}`),
			NearbyContexts: []recognition.PlaceKnowledgeContext{{
				IntroductionKey:  "lingyin-timber-bracket",
				IntroductionName: "灵隐寺斗拱",
				Introduction:     json.RawMessage(`{"schemaVersion":1,"blocks":[{"type":"paragraph","text":"现场介绍"}]}`),
				AttractionKey:    "lingyin-temple",
				AttractionName:   "灵隐寺",
			}},
		}},
	}
}

func providerFiles(t *testing.T) (string, string) {
	t.Helper()
	directory := t.TempDir()
	promptPath := filepath.Join(directory, "prompt.txt")
	schemaPath := filepath.Join(directory, "schema.json")
	if err := os.WriteFile(promptPath, []byte("prompt"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(schemaPath, []byte(`{"type":"object"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	return promptPath, schemaPath
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(request *http.Request) (*http.Response, error) { return f(request) }
