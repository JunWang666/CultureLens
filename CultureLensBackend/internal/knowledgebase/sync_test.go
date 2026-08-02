package knowledgebase

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestSROMClientFetchesAllPages(t *testing.T) {
	requestedPages := make([]int, 0, 2)
	httpClient := &http.Client{
		Transport: roundTripFunc(func(request *http.Request) (*http.Response, error) {
			if request.Method != http.MethodPost ||
				request.URL.Path != "/api/collection/list_web" ||
				request.Header.Get("User-Agent") != "CultureLensTest/1.0" {
				t.Fatalf("unexpected request: %s %s", request.Method, request.URL.Path)
			}
			var body struct {
				Page int `json:"page"`
				Size int `json:"size"`
			}
			if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
				t.Fatal(err)
			}
			requestedPages = append(requestedPages, body.Page)
			if body.Size != 2 {
				t.Fatalf("unexpected page size %d", body.Size)
			}
			list := []SROMCollection{
				{CollectionID: 1, CollectionName: "丝绸"},
				{CollectionID: 2, CollectionName: "瓷器"},
			}
			if body.Page == 2 {
				list = []SROMCollection{{CollectionID: 3, CollectionName: "青铜器"}}
			}
			payload, err := json.Marshal(map[string]any{
				"code":    200,
				"message": "成功",
				"data": map[string]any{
					"list":  list,
					"total": 3,
				},
			})
			if err != nil {
				return nil, err
			}
			return &http.Response{
				StatusCode: http.StatusOK,
				Header:     make(http.Header),
				Body:       io.NopCloser(strings.NewReader(string(payload))),
				Request:    request,
			}, nil
		}),
	}

	client := SROMClient{
		BaseURL:   "https://srom.example.test",
		HTTP:      httpClient,
		UserAgent: "CultureLensTest/1.0",
		PageSize:  2,
	}
	collections, err := client.FetchCollections(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(collections) != 3 ||
		len(requestedPages) != 2 ||
		requestedPages[0] != 1 ||
		requestedPages[1] != 2 {
		t.Fatalf("unexpected pagination: pages=%v collections=%v", requestedPages, collections)
	}
}

func TestSROMClientRejectsInvalidResponses(t *testing.T) {
	tests := []struct {
		name       string
		statusCode int
		payload    string
	}{
		{
			name:       "HTTP error",
			statusCode: http.StatusBadGateway,
			payload:    `{"code":502}`,
		},
		{
			name:       "invalid JSON",
			statusCode: http.StatusOK,
			payload:    `{`,
		},
		{
			name:       "total mismatch",
			statusCode: http.StatusOK,
			payload: `{
				"code": 200,
				"data": {
					"list": [{"collectionId": 1, "collectionName": "藏品"}],
					"total": 2
				}
			}`,
		},
		{
			name:       "duplicate collection ID",
			statusCode: http.StatusOK,
			payload: `{
				"code": 200,
				"data": {
					"list": [
						{"collectionId": 1, "collectionName": "藏品一"},
						{"collectionId": 1, "collectionName": "藏品二"}
					],
					"total": 2
				}
			}`,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			httpClient := &http.Client{
				Transport: roundTripFunc(func(request *http.Request) (*http.Response, error) {
					return &http.Response{
						StatusCode: test.statusCode,
						Header:     make(http.Header),
						Body:       io.NopCloser(strings.NewReader(test.payload)),
						Request:    request,
					}, nil
				}),
			}
			client := SROMClient{
				BaseURL:  "https://srom.example.test",
				HTTP:     httpClient,
				PageSize: 10,
			}
			if _, err := client.FetchCollections(context.Background()); err == nil {
				t.Fatal("expected invalid SROM response to fail")
			}
		})
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (function roundTripFunc) RoundTrip(
	request *http.Request,
) (*http.Response, error) {
	return function(request)
}

func TestBuildBundleIsStableAndDoesNotCopySROMDescription(t *testing.T) {
	generatedAt := time.Date(2026, 7, 30, 7, 0, 0, 0, time.UTC)
	collections := []SROMCollection{{
		CollectionID:      224200258224160,
		CollectionName:    "南宋青釉瓷碗与珊瑚胶结块",
		ENCollectionName:  "Bowl",
		CollectionImage:   "https://example.test/object.jpg",
		Size:              "通高22.3厘米",
		MaterialName:      "瓷",
		YearsName:         "南宋",
		RegionName:        "中国",
		RepositoryName:    "海南省博物馆",
		ThemeName:         "丝绸之路",
		DescriptionHTML:   "<p>不应进入知识库的长篇描述</p>",
		ENDescriptionHTML: "<p>Long description must not be copied.</p>",
	}}
	seed := testWikipediaSeed()
	first, err := BuildBundle("test-v1", generatedAt, collections, seed)
	if err != nil {
		t.Fatal(err)
	}
	second, err := BuildBundle("test-v1", generatedAt, collections, seed)
	if err != nil {
		t.Fatal(err)
	}
	firstJSON, _ := json.Marshal(first)
	secondJSON, _ := json.Marshal(second)
	if string(firstJSON) != string(secondJSON) {
		t.Fatal("fixed input did not produce a deterministic bundle")
	}
	if strings.Contains(string(firstJSON), "不应进入知识库") ||
		strings.Contains(string(firstJSON), "Long description") {
		t.Fatal("SROM description leaked into the knowledge bundle")
	}
	if first.Statistics.BySource["srom"] != 1 ||
		first.Statistics.BySource["wikipedia"] != 2 ||
		first.Statistics.TotalRelations != 1 {
		t.Fatalf("unexpected statistics: %+v", first.Statistics)
	}
}

func TestWikipediaRequiresRevisionAndShareAlikeMetadata(t *testing.T) {
	seed := testWikipediaSeed()
	seed.Records[0].RevisionID = ""
	_, err := BuildBundle(
		"test-v1",
		time.Date(2026, 7, 30, 7, 0, 0, 0, time.UTC),
		[]SROMCollection{{CollectionID: 1, CollectionName: "藏品"}},
		seed,
	)
	if err == nil {
		t.Fatal("expected missing Wikipedia revision to fail")
	}
}

func testWikipediaSeed() WikipediaSeed {
	return WikipediaSeed{
		Version:    "test-seed",
		AccessedAt: "2026-07-30T07:00:00Z",
		License:    "CC BY-SA 4.0",
		LicenseURL: "https://creativecommons.org/licenses/by-sa/4.0/",
		Records: []WikipediaSeedRecord{
			{
				Title:         "丝绸之路",
				CanonicalName: "丝绸之路",
				URL:           "https://zh.wikipedia.org/w/index.php?title=丝绸之路&oldid=1",
				RevisionID:    "1",
				Kind:          "route",
				Summary:       "跨区域贸易与文化交流网络。",
			},
			{
				Title:         "丝绸",
				CanonicalName: "丝绸",
				URL:           "https://zh.wikipedia.org/w/index.php?title=丝绸&oldid=2",
				RevisionID:    "2",
				Kind:          "material",
				Summary:       "以蚕丝织成的纺织品。",
				Relations: []WikipediaSeedRelation{{
					Kind:        "交流物",
					TargetTitle: "丝绸之路",
					Explanation: "丝绸是代表性贸易商品。",
				}},
			},
		},
	}
}
