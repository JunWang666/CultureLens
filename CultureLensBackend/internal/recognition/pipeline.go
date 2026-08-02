package recognition

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"math"
	"strings"
	"time"
	"unicode"

	"github.com/google/uuid"
	"github.com/goudaijun/culturelens-backend/internal/knowledge"
)

const maxBodyBytes = 18 << 20
const maxPixels = 16_000_000

var ErrInvalidRequest = errors.New("invalid request")
var ErrImageTooLarge = errors.New("image too large")
var ErrUnsupportedImage = errors.New("unsupported image")

type Pipeline struct {
	provider                            Provider
	knowledge                           knowledge.RecognitionRepository
	model, promptVersion, schemaVersion string
}

func NewPipeline(
	provider Provider,
	repository knowledge.RecognitionRepository,
	model, promptVersion, schemaVersion string,
) Pipeline {
	return Pipeline{
		provider:      provider,
		knowledge:     repository,
		model:         model,
		promptVersion: promptVersion,
		schemaVersion: schemaVersion,
	}
}

func (p Pipeline) Recognize(ctx context.Context, req Request) (Response, error) {
	if strings.TrimSpace(req.RequestID) == "" {
		req.RequestID = uuid.NewString()
	}
	if err := validateLocation(req.Location); err != nil {
		return Response{}, err
	}

	contextImage, err := decodeAndValidateImage(req.ImageBase64, req.MIMEType)
	if err != nil {
		return Response{}, err
	}

	var focusImage []byte
	switch {
	case req.FocusImageBase64 == "" && req.FocusMIMEType == "":
	case req.FocusImageBase64 == "" || req.FocusMIMEType == "":
		return Response{}, fmt.Errorf("%w: focus image and MIME type must be provided together", ErrInvalidRequest)
	default:
		focusImage, err = decodeAndValidateImage(req.FocusImageBase64, req.FocusMIMEType)
		if err != nil {
			return Response{}, fmt.Errorf("focus image: %w", err)
		}
	}

	media := MediaInput{
		ContextImage: contextImage,
		ContextMIME:  req.MIMEType,
		FocusImage:   focusImage,
		FocusMIME:    req.FocusMIMEType,
	}
	knowledgeSet, err := p.knowledge.RecognitionKnowledge(
		ctx,
		recognitionKnowledgeQuery(req.Location),
	)
	if err != nil {
		return Response{}, fmt.Errorf("retrieve recognition knowledge: %w", err)
	}
	providerCtx, cancel := context.WithTimeout(ctx, 55*time.Second)
	defer cancel()
	providerRequest := req
	providerRequest.ImageBase64 = ""
	providerRequest.FocusImageBase64 = ""
	providerRequest.Location = nil
	providerInput := ProviderInput{
		Request:              providerRequest,
		KnowledgeCandidates:  knowledgeContext(knowledgeSet.Elements),
		AttractionCandidates: attractionContext(knowledgeSet.AttractionCandidates),
	}
	decision, actualModel, err := p.provider.Recognize(providerCtx, media, providerInput)
	if err != nil {
		return Response{}, err
	}
	resolveKnowledgeReferences(&decision, providerInput.KnowledgeCandidates)
	if err := validateDecision(
		decision,
		providerInput.KnowledgeCandidates,
		providerInput.AttractionCandidates,
	); err != nil {
		return Response{}, err
	}
	return mapResponse(
		req,
		decision,
		actualModel,
		p.promptVersion,
		p.schemaVersion,
		knowledgeSet,
	), nil
}

func attractionContext(candidates []knowledge.AttractionCandidate) []AttractionCandidateContext {
	contexts := make([]AttractionCandidateContext, 0, len(candidates))
	for _, candidate := range candidates {
		contexts = append(contexts, AttractionCandidateContext{
			Key:                candidate.Key,
			Name:               candidate.Name,
			CulturalElementKey: candidate.CulturalElementKey,
		})
	}
	return contexts
}

func recognitionKnowledgeQuery(location *Location) knowledge.RecognitionQuery {
	if location == nil {
		return knowledge.RecognitionQuery{Limit: 12}
	}
	return knowledge.RecognitionQuery{
		Latitude:     location.Latitude,
		Longitude:    location.Longitude,
		RadiusMeters: 50_000,
		HasLocation:  true,
		Limit:        12,
	}
}

func knowledgeContext(elements []knowledge.RecognitionElement) []KnowledgeCandidateContext {
	candidates := make([]KnowledgeCandidateContext, 0, len(elements))
	for _, element := range elements {
		contexts := make([]PlaceKnowledgeContext, 0, len(element.NearbyContexts))
		for _, place := range element.NearbyContexts {
			contexts = append(contexts, PlaceKnowledgeContext{
				IntroductionKey:  place.Key,
				IntroductionName: place.Name,
				Introduction:     append(json.RawMessage(nil), place.Introduction...),
				AttractionKey:    place.Attraction.Key,
				AttractionName:   place.Attraction.Name,
			})
		}
		candidates = append(candidates, KnowledgeCandidateContext{
			Key:            element.Key,
			Name:           element.Name,
			Introduction:   append(json.RawMessage(nil), element.Introduction...),
			NearbyContexts: contexts,
		})
	}
	return candidates
}

func decodeAndValidateImage(encoded, mimeType string) ([]byte, error) {
	if len(encoded) == 0 {
		return nil, fmt.Errorf("%w: image is required", ErrInvalidRequest)
	}
	if len(encoded) > maxBodyBytes*2 {
		return nil, ErrImageTooLarge
	}
	if mimeType != "image/jpeg" && mimeType != "image/png" {
		return nil, ErrUnsupportedImage
	}

	imageData, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return nil, fmt.Errorf("%w: malformed image_base64", ErrInvalidRequest)
	}
	if len(imageData) > maxBodyBytes {
		return nil, ErrImageTooLarge
	}
	config, format, err := image.DecodeConfig(bytes.NewReader(imageData))
	if err != nil || config.Width < 1 || config.Height < 1 || config.Width*config.Height > maxPixels {
		return nil, ErrUnsupportedImage
	}
	if (format == "jpeg" && mimeType != "image/jpeg") || (format == "png" && mimeType != "image/png") {
		return nil, ErrUnsupportedImage
	}
	return imageData, nil
}

func validateLocation(location *Location) error {
	if location == nil {
		return nil
	}
	if !finite(location.Latitude) ||
		!finite(location.Longitude) ||
		location.Latitude < -90 ||
		location.Latitude > 90 ||
		location.Longitude < -180 ||
		location.Longitude > 180 ||
		!validLocationText(location.CityName, 80) ||
		!validLocationText(location.RegionName, 80) ||
		!validLocationText(location.DisplayName, 120) ||
		(location.RegionCode != "" && !validRegionCode(location.RegionCode)) {
		return fmt.Errorf("%w: invalid location", ErrInvalidRequest)
	}
	if location.AccuracyMeters != nil &&
		(!finite(*location.AccuracyMeters) ||
			*location.AccuracyMeters < 0 ||
			*location.AccuracyMeters > 10_000_000) {
		return fmt.Errorf("%w: invalid location accuracy", ErrInvalidRequest)
	}
	return nil
}

func finite(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
}

func validLocationText(value string, maxLength int) bool {
	if len([]rune(value)) > maxLength {
		return false
	}
	for _, character := range value {
		if unicode.IsControl(character) {
			return false
		}
	}
	return true
}

func validRegionCode(value string) bool {
	if len(value) != 2 {
		return false
	}
	for _, character := range value {
		if character < 'A' || character > 'Z' {
			return false
		}
	}
	return true
}

func resolveKnowledgeReferences(
	decision *ProviderRecognition,
	candidates []KnowledgeCandidateContext,
) {
	byName := make(map[string]string, len(candidates))
	for _, candidate := range candidates {
		byName[normalizeEntityName(candidate.Name)] = candidate.Key
	}
	if decision.CulturalElementKey == "" {
		decision.CulturalElementKey = byName[normalizeEntityName(decision.CanonicalName)]
	}
	for index := range decision.Alternatives {
		if decision.Alternatives[index].CulturalElementKey == "" {
			decision.Alternatives[index].CulturalElementKey =
				byName[normalizeEntityName(decision.Alternatives[index].CanonicalName)]
		}
	}
}

func validateDecision(
	d ProviderRecognition,
	candidates []KnowledgeCandidateContext,
	attractions []AttractionCandidateContext,
) error {
	if strings.TrimSpace(d.CanonicalName) == "" ||
		strings.TrimSpace(d.Summary) == "" ||
		strings.TrimSpace(d.Rationale) == "" ||
		!validCategory(d.Category) ||
		d.Confidence < 0 ||
		d.Confidence > 1 ||
		len(d.Alternatives) < 1 ||
		len(d.Alternatives) > 3 ||
		!validKnowledgeReference(d.CulturalElementKey, d.CanonicalName, candidates) ||
		!validAttractionReference(d.AttractionKey, attractions) {
		return errors.New("invalid provider output")
	}
	seen := map[string]struct{}{strings.ToLower(strings.TrimSpace(d.CanonicalName)): {}}
	seenKeys := make(map[string]struct{}, len(d.Alternatives)+1)
	if d.CulturalElementKey != "" {
		seenKeys[strings.ToLower(d.CulturalElementKey)] = struct{}{}
	}
	for _, candidate := range d.Alternatives {
		name := strings.ToLower(strings.TrimSpace(candidate.CanonicalName))
		if name == "" ||
			strings.TrimSpace(candidate.Rationale) == "" ||
			!validCategory(candidate.Category) ||
			candidate.Confidence < 0 ||
			candidate.Confidence > 1 ||
			!validKnowledgeReference(
				candidate.CulturalElementKey,
				candidate.CanonicalName,
				candidates,
			) {
			return errors.New("invalid provider output")
		}
		if _, exists := seen[name]; exists {
			return errors.New("invalid provider output")
		}
		seen[name] = struct{}{}
		if candidate.CulturalElementKey != "" {
			key := strings.ToLower(candidate.CulturalElementKey)
			if _, exists := seenKeys[key]; exists {
				return errors.New("invalid provider output")
			}
			seenKeys[key] = struct{}{}
		}
	}
	return nil
}

func validAttractionReference(key string, candidates []AttractionCandidateContext) bool {
	if key == "" {
		return true
	}
	for _, candidate := range candidates {
		if strings.EqualFold(candidate.Key, key) {
			return true
		}
	}
	return false
}

func validKnowledgeReference(
	key, name string,
	candidates []KnowledgeCandidateContext,
) bool {
	if key == "" {
		return true
	}
	for _, candidate := range candidates {
		if !strings.EqualFold(candidate.Key, key) {
			continue
		}
		return normalizeEntityName(name) == normalizeEntityName(candidate.Name)
	}
	return false
}

func normalizeEntityName(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	return strings.Map(func(character rune) rune {
		if unicode.IsSpace(character) {
			return -1
		}
		return character
	}, value)
}

func validCategory(category string) bool {
	switch category {
	case "建筑构件", "器物", "纹样", "展品", "空间", "其他":
		return true
	default:
		return false
	}
}
func mapResponse(
	req Request,
	d ProviderRecognition,
	model, prompt, schema string,
	knowledgeSet knowledge.RecognitionSet,
) Response {
	elementsByKey := make(map[string]knowledge.RecognitionElement, len(knowledgeSet.Elements))
	for _, element := range knowledgeSet.Elements {
		elementsByKey[strings.ToLower(element.Key)] = element
	}
	object, resolutionStatus := responseObject(req, d, elementsByKey, knowledgeSet.AttractionCandidates)
	uncertainty := d.Uncertainty
	if uncertainty == "" {
		uncertainty = "该判断基于可见特征，建议结合现场说明牌或馆藏资料进一步核验。"
	}
	alts := make([]Candidate, 0, min(len(knowledgeSet.AttractionCandidates), 3))
	for _, attraction := range knowledgeSet.AttractionCandidates {
		if d.AttractionKey != "" && strings.EqualFold(attraction.Key, d.AttractionKey) {
			continue
		}
		alts = append(alts, attractionCandidate(attraction))
		if len(alts) == 3 {
			break
		}
	}
	return Response{
		ID:                    uuid.NewSHA1(uuid.NameSpaceURL, []byte(req.RequestID+":result")).String(),
		Object:                object,
		Alternatives:          alts,
		Rationale:             d.Rationale,
		Uncertainty:           &uncertainty,
		ModelIdentifier:       model,
		UsedPlaceContext:      req.Location != nil,
		LocationInfluence:     repositoryLocationInfluence(req.Location, knowledgeSet),
		RequestID:             req.RequestID,
		PromptVersion:         prompt,
		SchemaVersion:         schema,
		ResolutionStatus:      resolutionStatus,
		CatalogVersion:        knowledgeSet.Version,
		CatalogCandidateCount: len(knowledgeSet.Elements),
	}
}

func responseObject(
	req Request,
	decision ProviderRecognition,
	elements map[string]knowledge.RecognitionElement,
	attractions []knowledge.AttractionCandidate,
) (CultureObject, string) {
	if decision.AttractionKey != "" {
		for _, attraction := range attractions {
			if !strings.EqualFold(attraction.Key, decision.AttractionKey) {
				continue
			}
			if element, exists := elements[strings.ToLower(attraction.CulturalElementKey)]; exists {
				object := knowledgeCultureObject(element, decision)
				object.CanonicalName = attraction.Name
				return object, "attraction"
			}
		}
	}
	if element, exists := elements[strings.ToLower(decision.CulturalElementKey)]; exists {
		return knowledgeCultureObject(element, decision), "resolved"
	}
	objectID := uuid.NewSHA1(
		uuid.NameSpaceURL,
		[]byte(req.RequestID+":unresolved:"+strings.ToLower(decision.CanonicalName)),
	).String()
	var timePeriod, region *string
	if decision.TimePeriod != "" {
		timePeriod = &decision.TimePeriod
	}
	if decision.Region != "" {
		region = &decision.Region
	}
	return CultureObject{
		ID:            objectID,
		CanonicalName: decision.CanonicalName,
		Summary:       decision.Summary,
		Category:      decision.Category,
		TimePeriod:    timePeriod,
		Region:        region,
		Confidence:    decision.Confidence,
		ArtworkSymbol: artworkSymbol(decision.Category),
		Concepts:      []any{},
		Relations:     []any{},
		Sources:       []Source{},
	}, "unresolved"
}

func knowledgeCultureObject(
	element knowledge.RecognitionElement,
	decision ProviderRecognition,
) CultureObject {
	var timePeriod, region *string
	if decision.TimePeriod != "" {
		timePeriod = &decision.TimePeriod
	}
	if decision.Region != "" {
		region = &decision.Region
	}
	summary := richTextPlainText(element.Introduction)
	if summary == "" {
		summary = decision.Summary
	}
	graphElements := element.GraphElements
	if len(graphElements) == 0 {
		graphElements = element.RelatedElements
	}
	graphEdges := element.GraphRelations
	if len(graphEdges) == 0 {
		graphEdges = fallbackGraphRelations(element.Key, element.RelatedElements)
	}
	return CultureObject{
		ID:                 culturalElementID(element.Key),
		CulturalElementKey: element.Key,
		CanonicalName:      element.Name,
		Summary:            summary,
		Category:           decision.Category,
		TimePeriod:         timePeriod,
		Region:             region,
		Confidence:         decision.Confidence,
		ArtworkSymbol:      artworkSymbol(decision.Category),
		Concepts:           graphConcepts(graphElements),
		Relations:          graphRelations(graphEdges),
		Sources:            []Source{},
	}
}

type graphConcept struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Kind    string `json:"kind"`
	Summary string `json:"summary"`
	Detail  string `json:"detail"`
}

type graphRelation struct {
	ID          string `json:"id"`
	SourceID    string `json:"sourceID"`
	TargetID    string `json:"targetID"`
	Kind        string `json:"kind"`
	Explanation string `json:"explanation"`
}

func graphConcepts(elements []knowledge.CulturalElement) []any {
	concepts := make([]any, 0, len(elements))
	for _, element := range elements {
		summary := richTextPlainText(element.Introduction)
		concepts = append(concepts, graphConcept{
			ID:      culturalElementID(element.Key),
			Name:    element.Name,
			Kind:    graphConceptKind(element.Key, element.Name),
			Summary: summary,
			Detail:  "",
		})
	}
	return concepts
}

func graphRelations(edges []knowledge.CulturalRelation) []any {
	relations := make([]any, 0, len(edges))
	for _, edge := range edges {
		relations = append(relations, graphRelation{
			ID: uuid.NewSHA1(
				uuid.NameSpaceURL,
				[]byte(edge.ElementKey+":"+edge.RelatedElementKey+":"+edge.Kind),
			).String(),
			SourceID:    culturalElementID(edge.ElementKey),
			TargetID:    culturalElementID(edge.RelatedElementKey),
			Kind:        edge.Kind,
			Explanation: edge.Explanation,
		})
	}
	return relations
}

func fallbackGraphRelations(
	elementKey string,
	related []knowledge.CulturalElement,
) []knowledge.CulturalRelation {
	relations := make([]knowledge.CulturalRelation, 0, len(related))
	for _, element := range related {
		relations = append(relations, knowledge.CulturalRelation{
			ElementKey:        elementKey,
			RelatedElementKey: element.Key,
			Kind:              "解释",
			Explanation:       "文化内容库记录了当前对象与该概念的显式关联；关系类型尚未细分。",
		})
	}
	return relations
}

func graphConceptKind(key, name string) string {
	key = strings.ToLower(key)
	switch {
	case strings.Contains(key, "su-shi"), strings.Contains(key, "bai-juyi"):
		return "人物"
	case strings.Contains(key, "song"), strings.Contains(name, "朝"), strings.Contains(name, "临安"):
		return "历史"
	case strings.Contains(key, "garden"), strings.Contains(key, "landscape"), strings.Contains(key, "moon"):
		return "审美"
	default:
		return "基础知识"
	}
}

func responseCandidate(
	requestID string,
	candidate ProviderCandidate,
	elements map[string]knowledge.RecognitionElement,
) Candidate {
	if element, exists := elements[strings.ToLower(candidate.CulturalElementKey)]; exists {
		return knowledgeCandidate(
			element,
			candidate.Category,
			candidate.Confidence,
			candidate.Rationale,
		)
	}
	return Candidate{
		ID:            uuid.NewSHA1(uuid.NameSpaceURL, []byte(requestID+":"+candidate.CanonicalName)).String(),
		CanonicalName: candidate.CanonicalName,
		Category:      candidate.Category,
		Confidence:    candidate.Confidence,
		Rationale:     candidate.Rationale,
	}
}

func attractionCandidate(attraction knowledge.AttractionCandidate) Candidate {
	return Candidate{
		ID:                 uuid.NewSHA1(uuid.NameSpaceURL, []byte("attraction:"+attraction.Key)).String(),
		AttractionKey:      attraction.Key,
		CulturalElementKey: attraction.CulturalElementKey,
		CanonicalName:      attraction.Name,
		Category:           "空间",
		Confidence:         0,
		Rationale:          "根据当前位置列出的附近景点，仍需结合画面确认。",
		Summary:            attraction.Summary,
		ResolutionStatus:   "attraction",
	}
}

func knowledgeCandidate(
	element knowledge.RecognitionElement,
	category string,
	confidence float64,
	rationale string,
) Candidate {
	if !validCategory(category) {
		category = "其他"
	}
	return Candidate{
		ID:                 culturalElementID(element.Key),
		CulturalElementKey: element.Key,
		CanonicalName:      element.Name,
		Category:           category,
		Confidence:         confidence,
		Rationale:          rationale,
		Summary:            richTextPlainText(element.Introduction),
		ArtworkSymbol:      artworkSymbol(category),
		Sources:            []Source{},
		ResolutionStatus:   "resolved",
	}
}

func containsResolvedCandidate(candidates []Candidate) bool {
	for _, candidate := range candidates {
		if candidate.ResolutionStatus == "resolved" {
			return true
		}
	}
	return false
}

func repositoryLocationInfluence(
	location *Location,
	knowledgeSet knowledge.RecognitionSet,
) *LocationInfluence {
	if location == nil {
		return nil
	}
	if knowledgeSet.LocationMatched {
		return &LocationInfluence{
			Effect: "reordered",
			Summary: fmt.Sprintf(
				"位置匹配到 %d 条景点现场介绍，整理出 %d 个附近景点候选；文化元素仅作为解释知识。",
				knowledgeSet.NearbyContextCount,
				len(knowledgeSet.AttractionCandidates),
			),
		}
	}
	return &LocationInfluence{
		Effect: "none",
		Summary: fmt.Sprintf(
			"附近没有匹配到景点现场介绍，模型仍按图片和现有 %d 条文化元素候选判断。",
			len(knowledgeSet.Elements),
		),
	}
}

func culturalElementID(key string) string {
	return uuid.NewSHA1(
		uuid.NameSpaceURL,
		[]byte("culturelens:cultural-element:"+strings.ToLower(key)),
	).String()
}

func richTextPlainText(value json.RawMessage) string {
	var document struct {
		Blocks []struct {
			Text string `json:"text"`
		} `json:"blocks"`
	}
	if json.Unmarshal(value, &document) != nil {
		return ""
	}
	parts := make([]string, 0, len(document.Blocks))
	for _, block := range document.Blocks {
		if text := strings.TrimSpace(block.Text); text != "" {
			parts = append(parts, text)
		}
	}
	return strings.Join(parts, "\n")
}

func artworkSymbol(category string) string {
	switch category {
	case "建筑构件":
		return "building.columns.fill"
	case "器物":
		return "shippingbox.fill"
	case "纹样":
		return "seal.fill"
	case "展品":
		return "photo.on.rectangle.angled"
	case "空间":
		return "map.fill"
	default:
		return "sparkles"
	}
}
