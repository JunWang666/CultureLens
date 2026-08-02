package recognition

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"image"
	"image/color"
	"image/jpeg"
	"strings"
	"testing"

	"github.com/goudaijun/culturelens-backend/internal/knowledge"
)

type stubProvider struct {
	decision ProviderRecognition
	input    ProviderInput
	called   bool
}

func (p *stubProvider) Recognize(
	_ context.Context,
	_ MediaInput,
	input ProviderInput,
) (ProviderRecognition, string, error) {
	p.called = true
	p.input = input
	return p.decision, "stub-model", nil
}

type stubRecognitionRepository struct {
	set   knowledge.RecognitionSet
	err   error
	query knowledge.RecognitionQuery
}

func (r *stubRecognitionRepository) RecognitionKnowledge(
	_ context.Context,
	query knowledge.RecognitionQuery,
) (knowledge.RecognitionSet, error) {
	r.query = query
	return r.set, r.err
}

func TestPipelineResolvesCulturalElementAndUsesDatabaseIntroduction(t *testing.T) {
	provider := &stubProvider{decision: ProviderRecognition{
		CulturalElementKey: "timber-bracket",
		CanonicalName:      "斗拱",
		Category:           "建筑构件",
		Confidence:         0.82,
		Summary:            "模型生成的摘要不应进入已解析对象。",
		Rationale:          "框选处可见层层出跳的木构件。",
		Uncertainty:        "仍需侧面角度。",
		TimePeriod:         "宋代",
		Region:             "中国",
		Alternatives: []ProviderCandidate{{
			CanonicalName: "雀替",
			Category:      "建筑构件",
			Confidence:    0.22,
			Rationale:     "缺少层叠出跳。",
		}},
	}}
	repository := &stubRecognitionRepository{set: recognitionSet()}
	response, err := testPipeline(provider, repository).Recognize(
		context.Background(),
		testRequest(),
	)
	if err != nil {
		t.Fatal(err)
	}
	if provider.input.Request.Location != nil {
		t.Fatal("raw location must not reach the provider")
	}
	if response.Object.CulturalElementKey != "timber-bracket" ||
		response.Object.CanonicalName != "斗拱" ||
		response.Object.Summary != "数据库中的斗拱介绍。" ||
		response.Object.Summary == provider.decision.Summary ||
		response.ResolutionStatus != "resolved" ||
		response.CatalogVersion != "cultural-elements-v1" {
		t.Fatalf("cultural content facts were not applied: %+v", response)
	}
	if len(response.Object.Concepts) != 1 || len(response.Object.Relations) != 1 {
		t.Fatalf("cultural graph was not returned: concepts=%v relations=%v", response.Object.Concepts, response.Object.Relations)
	}
	if repository.query.Latitude != 30.248963 ||
		repository.query.Longitude != 120.148691 ||
		!repository.query.HasLocation {
		t.Fatalf("full-precision location was not used for repository lookup: %+v", repository.query)
	}
}

func TestPipelineRejectsCulturalElementKeyOutsideRetrievedCandidates(t *testing.T) {
	provider := &stubProvider{decision: ProviderRecognition{
		CulturalElementKey: "invented-key",
		CanonicalName:      "斗拱",
		Category:           "建筑构件",
		Confidence:         0.82,
		Summary:            "木构件",
		Rationale:          "层叠出跳",
		Uncertainty:        "需补拍",
		Alternatives: []ProviderCandidate{{
			CanonicalName: "其他",
			Category:      "其他",
			Confidence:    0.1,
			Rationale:     "可能为未收录对象。",
		}},
	}}
	_, err := testPipeline(provider, &stubRecognitionRepository{set: recognitionSet()}).Recognize(
		context.Background(),
		testRequest(),
	)
	if err == nil || !strings.Contains(err.Error(), "invalid provider output") {
		t.Fatalf("expected invalid candidate reference, got %v", err)
	}
}

func TestAttractionUsesCanonicalCulturalElementGraph(t *testing.T) {
	introduction := json.RawMessage(
		`{"schemaVersion":1,"blocks":[{"type":"paragraph","text":"正文"}]}`,
	)
	root := knowledge.RecognitionElement{
		Key:          "three-pools-mirroring-moon",
		Name:         "三潭印月",
		Introduction: introduction,
		GraphElements: []knowledge.CulturalElement{{
			Key:          "three-pools-stone-pagodas",
			Name:         "三座水中石塔",
			Introduction: introduction,
		}},
		GraphRelations: []knowledge.CulturalRelation{{
			ElementKey:        "three-pools-mirroring-moon",
			RelatedElementKey: "three-pools-stone-pagodas",
			Kind:              "核心构筑物",
			Explanation:       "三座石塔是核心现场实体。",
		}},
	}
	wrongFirstIntroduction := knowledge.RecognitionElement{
		Key:          "west-lake-moon-viewing",
		Name:         "西湖月景与倒影营造",
		Introduction: introduction,
	}
	elements := map[string]knowledge.RecognitionElement{
		root.Key:                   root,
		wrongFirstIntroduction.Key: wrongFirstIntroduction,
	}
	object, status := responseObject(
		Request{RequestID: "request"},
		ProviderRecognition{
			AttractionKey: "three-pools-mirroring-moon",
			Category:      "空间",
			Confidence:    0.92,
		},
		elements,
		[]knowledge.AttractionCandidate{{
			Key:                "three-pools-mirroring-moon",
			Name:               "三潭印月",
			CulturalElementKey: root.Key,
		}},
	)
	if status != "attraction" || object.CulturalElementKey != root.Key ||
		object.CanonicalName != "三潭印月" || len(object.Concepts) != 1 ||
		len(object.Relations) != 1 {
		t.Fatalf("attraction did not use its primary graph: %+v, status=%s", object, status)
	}
}

func TestAttractionPrimaryIsExcludedFromAlternativesAndCandidatesUseReviewedSummary(t *testing.T) {
	introduction := json.RawMessage(
		`{"schemaVersion":1,"blocks":[{"type":"paragraph","text":"审核后的文化介绍。"}]}`,
	)
	provider := &stubProvider{decision: ProviderRecognition{
		CulturalElementKey: "three-pools-mirroring-moon",
		AttractionKey:      "three-pools-mirroring-moon",
		CanonicalName:      "三潭印月",
		Category:           "空间",
		Confidence:         0.92,
		Summary:            "模型摘要",
		Rationale:          "画面可见三座石塔。",
		Alternatives: []ProviderCandidate{{
			CanonicalName: "其他",
			Category:      "其他",
			Confidence:    0.1,
			Rationale:     "其他可能。",
		}},
	}}
	repository := &stubRecognitionRepository{set: knowledge.RecognitionSet{
		Version: "cultural-elements-v1",
		Elements: []knowledge.RecognitionElement{
			{
				Key:          "three-pools-mirroring-moon",
				Name:         "三潭印月",
				Introduction: introduction,
			},
			{
				Key:          "leifeng-pagoda",
				Name:         "雷峰塔",
				Introduction: introduction,
			},
		},
		AttractionCandidates: []knowledge.AttractionCandidate{
			{
				Key:                "three-pools-mirroring-moon",
				Name:               "三潭印月",
				CulturalElementKey: "three-pools-mirroring-moon",
				Summary:            "三潭印月自己的现场介绍。",
			},
			{
				Key:                "leifeng-pagoda",
				Name:               "雷峰塔",
				CulturalElementKey: "leifeng-pagoda",
				Summary:            "雷峰塔的审核现场介绍。",
			},
		},
		NearbyContextCount: 2,
		LocationMatched:    true,
	}}

	response, err := testPipeline(provider, repository).Recognize(
		context.Background(),
		testRequest(),
	)
	if err != nil {
		t.Fatal(err)
	}
	if response.Object.CanonicalName != "三潭印月" || len(response.Alternatives) != 1 {
		t.Fatalf("primary attraction was not removed from alternatives: %+v", response)
	}
	if candidate := response.Alternatives[0]; candidate.CanonicalName != "雷峰塔" ||
		candidate.Summary != "雷峰塔的审核现场介绍。" {
		t.Fatalf("candidate did not use reviewed introduction: %+v", candidate)
	}
}

func TestPipelineCallsProviderWhenCulturalElementsAreEmpty(t *testing.T) {
	provider := &stubProvider{decision: ProviderRecognition{
		CanonicalName: "雀替",
		Category:      "建筑构件",
		Confidence:    0.55,
		Summary:       "可能为雀替。",
		Rationale:     "位于梁柱交接处。",
		Uncertainty:   "需补拍结构侧面。",
		Alternatives: []ProviderCandidate{{
			CanonicalName: "其他",
			Category:      "其他",
			Confidence:    0.2,
			Rationale:     "细节不足。",
		}},
	}}
	repository := &stubRecognitionRepository{set: knowledge.RecognitionSet{
		Version:  "cultural-elements-v1",
		Elements: []knowledge.RecognitionElement{},
	}}
	response, err := testPipeline(provider, repository).Recognize(
		context.Background(),
		testRequest(),
	)
	if err != nil {
		t.Fatal(err)
	}
	if !provider.called ||
		len(provider.input.KnowledgeCandidates) != 0 ||
		response.ResolutionStatus != "unresolved" ||
		response.CatalogCandidateCount != 0 {
		t.Fatalf("empty knowledge must continue as open-set recognition: %+v", response)
	}
}

func TestPipelineStopsWhenRecognitionKnowledgeQueryFails(t *testing.T) {
	provider := &stubProvider{}
	_, err := testPipeline(
		provider,
		&stubRecognitionRepository{err: errors.New("database unavailable")},
	).Recognize(context.Background(), testRequest())
	if err == nil || provider.called {
		t.Fatalf("database failures must stop before provider: err=%v", err)
	}
}

func TestPipelineReportsNearbyContextReordering(t *testing.T) {
	provider := &stubProvider{decision: ProviderRecognition{
		CulturalElementKey: "timber-bracket",
		CanonicalName:      "斗拱",
		Category:           "建筑构件",
		Confidence:         0.8,
		Summary:            "斗拱",
		Rationale:          "层叠木构件",
		Alternatives: []ProviderCandidate{{
			CanonicalName: "雀替",
			Category:      "建筑构件",
			Confidence:    0.2,
			Rationale:     "可能为另一种构件。",
		}},
	}}
	response, err := testPipeline(
		provider,
		&stubRecognitionRepository{set: recognitionSet()},
	).Recognize(context.Background(), testRequest())
	if err != nil {
		t.Fatal(err)
	}
	if response.LocationInfluence == nil ||
		response.LocationInfluence.Effect != "reordered" ||
		!strings.Contains(response.LocationInfluence.Summary, "1 条景点现场介绍") {
		t.Fatalf("unexpected location influence: %+v", response.LocationInfluence)
	}
}

func recognitionSet() knowledge.RecognitionSet {
	introduction := json.RawMessage(
		`{"schemaVersion":1,"blocks":[{"type":"paragraph","text":"数据库中的斗拱介绍。"}]}`,
	)
	return knowledge.RecognitionSet{
		Version: "cultural-elements-v1",
		Elements: []knowledge.RecognitionElement{{
			Key:          "timber-bracket",
			Name:         "斗拱",
			Introduction: introduction,
			RelatedElements: []knowledge.CulturalElement{{
				Key:          "building-rank",
				Name:         "建筑等级",
				Introduction: introduction,
			}},
			NearbyContexts: []knowledge.AttractionIntroduction{{
				Key:          "west-lake.timber-bracket",
				Name:         "西湖斗拱",
				Introduction: introduction,
				CulturalElement: knowledge.CulturalElement{
					Key:  "timber-bracket",
					Name: "斗拱",
				},
				Attraction: knowledge.AttractionReference{
					Key:  "west-lake",
					Name: "西湖",
				},
			}},
		}},
		TotalElements:      1,
		NearbyContextCount: 1,
		LocationMatched:    true,
	}
}

func testPipeline(provider Provider, repository knowledge.RecognitionRepository) Pipeline {
	return NewPipeline(
		provider,
		repository,
		"stub-model",
		"recognition-v5",
		"provider-recognition-v5",
	)
}

func testRequest() Request {
	return Request{
		RequestID:   "pipeline-test",
		ImageBase64: testJPEGBase64(),
		MIMEType:    "image/jpeg",
		Location: &Location{
			Latitude:  30.248963,
			Longitude: 120.148691,
		},
		Locale: "zh_CN",
	}
}

func testJPEGBase64() string {
	var output bytes.Buffer
	pixels := image.NewRGBA(image.Rect(0, 0, 2, 2))
	pixels.Set(0, 0, color.Black)
	if err := jpeg.Encode(&output, pixels, nil); err != nil {
		panic(errors.New("encode test image"))
	}
	return base64.StdEncoding.EncodeToString(output.Bytes())
}
