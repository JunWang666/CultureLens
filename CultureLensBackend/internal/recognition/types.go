package recognition

import (
	"context"
	"encoding/json"
)

type Request struct {
	RequestID        string    `json:"request_id" format:"uuid" doc:"Client-generated request ID. The server generates one when omitted."`
	ImageBase64      string    `json:"image_base64" required:"true" doc:"Base64-encoded full-scene JPEG or PNG image."`
	MIMEType         string    `json:"mime_type" required:"true" enum:"image/jpeg,image/png" doc:"MIME type matching the decoded full-scene image."`
	FocusImageBase64 string    `json:"focus_image_base64,omitempty" doc:"Optional Base64-encoded user-selected focus image. Must be provided with focus_mime_type."`
	FocusMIMEType    string    `json:"focus_mime_type,omitempty" enum:"image/jpeg,image/png" doc:"MIME type matching the decoded focus image."`
	Location         *Location `json:"location,omitempty" doc:"Optional recorded or current location used only to prioritize cultural elements and retrieve nearby attraction context."`
	ContextNote      string    `json:"context_note,omitempty" doc:"Optional user-provided scene context."`
	Locale           string    `json:"locale" example:"zh_CN" doc:"Preferred response locale."`
}

type MediaInput struct {
	ContextImage []byte
	ContextMIME  string
	FocusImage   []byte
	FocusMIME    string
}

func (m MediaInput) HasFocus() bool {
	return len(m.FocusImage) > 0
}

type Location struct {
	Latitude       float64  `json:"latitude" minimum:"-90" maximum:"90" doc:"WGS84 latitude in decimal degrees."`
	Longitude      float64  `json:"longitude" minimum:"-180" maximum:"180" doc:"WGS84 longitude in decimal degrees."`
	AccuracyMeters *float64 `json:"accuracy_meters,omitempty" minimum:"0" maximum:"10000000" doc:"Recorded location accuracy radius in meters."`
	CityName       string   `json:"city_name,omitempty" maxLength:"80" doc:"City-level name without street or POI detail."`
	RegionName     string   `json:"region_name,omitempty" maxLength:"80" doc:"Country or region display name."`
	RegionCode     string   `json:"region_code,omitempty" pattern:"^[A-Z]{2}$" doc:"Two-letter uppercase region code."`
	DisplayName    string   `json:"display_name,omitempty" maxLength:"120" doc:"Coarse display label."`
}
type LocationInfluence struct {
	Effect  string `json:"effect"`
	Summary string `json:"summary"`
}
type Candidate struct {
	ID                 string   `json:"id"`
	AttractionKey      string   `json:"attractionKey,omitempty"`
	CulturalElementKey string   `json:"culturalElementKey,omitempty"`
	CanonicalName      string   `json:"canonicalName"`
	Category           string   `json:"category"`
	Confidence         float64  `json:"confidence"`
	Rationale          string   `json:"rationale"`
	Summary            string   `json:"summary,omitempty"`
	TimePeriod         *string  `json:"timePeriod,omitempty"`
	Region             *string  `json:"region,omitempty"`
	ArtworkSymbol      string   `json:"artworkSymbol,omitempty"`
	Sources            []Source `json:"sources,omitempty"`
	ResolutionStatus   string   `json:"resolutionStatus,omitempty"`
}
type Source struct {
	ID        string  `json:"id"`
	Title     string  `json:"title"`
	Publisher string  `json:"publisher"`
	URL       *string `json:"url,omitempty"`
}
type CultureObject struct {
	ID                 string   `json:"id"`
	CulturalElementKey string   `json:"culturalElementKey,omitempty"`
	CanonicalName      string   `json:"canonicalName"`
	Summary            string   `json:"summary"`
	Category           string   `json:"category"`
	TimePeriod         *string  `json:"timePeriod,omitempty"`
	Region             *string  `json:"region,omitempty"`
	Confidence         float64  `json:"confidence"`
	ArtworkSymbol      string   `json:"artworkSymbol"`
	Concepts           []any    `json:"concepts"`
	Relations          []any    `json:"relations"`
	Sources            []Source `json:"sources"`
}
type Response struct {
	ID                    string             `json:"id"`
	Object                CultureObject      `json:"object"`
	Alternatives          []Candidate        `json:"alternatives"`
	Rationale             string             `json:"rationale"`
	Uncertainty           *string            `json:"uncertainty,omitempty"`
	ModelIdentifier       string             `json:"modelIdentifier"`
	UsedPlaceContext      bool               `json:"usedPlaceContext"`
	LocationInfluence     *LocationInfluence `json:"locationInfluence,omitempty"`
	RequestID             string             `json:"requestID,omitempty"`
	PromptVersion         string             `json:"promptVersion,omitempty"`
	SchemaVersion         string             `json:"schemaVersion,omitempty"`
	ResolutionStatus      string             `json:"resolutionStatus,omitempty"`
	CatalogVersion        string             `json:"catalogVersion,omitempty"`
	CatalogCandidateCount int                `json:"catalogCandidateCount"`
}
type ProviderRecognition struct {
	CulturalElementKey string              `json:"cultural_element_key"`
	AttractionKey      string              `json:"attraction_key"`
	CanonicalName      string              `json:"canonical_name"`
	Category           string              `json:"category"`
	Confidence         float64             `json:"confidence"`
	Summary            string              `json:"summary"`
	Rationale          string              `json:"rationale"`
	Uncertainty        string              `json:"uncertainty"`
	TimePeriod         string              `json:"time_period"`
	Region             string              `json:"region"`
	Alternatives       []ProviderCandidate `json:"alternatives"`
}
type ProviderCandidate struct {
	CulturalElementKey string  `json:"cultural_element_key"`
	CanonicalName      string  `json:"canonical_name"`
	Category           string  `json:"category"`
	Confidence         float64 `json:"confidence"`
	Rationale          string  `json:"rationale"`
}

type PlaceKnowledgeContext struct {
	IntroductionKey  string          `json:"introduction_key"`
	IntroductionName string          `json:"introduction_name"`
	Introduction     json.RawMessage `json:"introduction"`
	AttractionKey    string          `json:"attraction_key"`
	AttractionName   string          `json:"attraction_name"`
}

type KnowledgeCandidateContext struct {
	Key            string                  `json:"key"`
	Name           string                  `json:"name"`
	Introduction   json.RawMessage         `json:"introduction"`
	NearbyContexts []PlaceKnowledgeContext `json:"nearby_contexts,omitempty"`
}

type ProviderInput struct {
	Request              Request
	KnowledgeCandidates  []KnowledgeCandidateContext
	AttractionCandidates []AttractionCandidateContext
}

type AttractionCandidateContext struct {
	Key                string `json:"key"`
	Name               string `json:"name"`
	CulturalElementKey string `json:"cultural_element_key"`
}

type Provider interface {
	Recognize(ctx context.Context, media MediaInput, input ProviderInput) (ProviderRecognition, string, error)
}
