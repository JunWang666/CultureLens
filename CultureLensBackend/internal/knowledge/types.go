package knowledge

import (
	"context"
	"encoding/json"
	"errors"
)

var ErrCulturalElementNotFound = errors.New("cultural element not found")

const (
	defaultCandidateLimit = 12
	maximumObjectLimit    = 20
)

type CulturalElement struct {
	Key          string          `json:"key"`
	Name         string          `json:"name"`
	Introduction json.RawMessage `json:"introduction"`
}

type RelatedElementSet struct {
	Element         CulturalElement   `json:"element"`
	RelatedElements []CulturalElement `json:"related_elements"`
}

type AttractionReference struct {
	Key  string `json:"key"`
	Name string `json:"name"`
}

type GeoCoordinate struct {
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
}

type AttractionIntroduction struct {
	Key             string              `json:"key"`
	Name            string              `json:"name"`
	Introduction    json.RawMessage     `json:"introduction"`
	CulturalElement CulturalElement     `json:"cultural_element"`
	Attraction      AttractionReference `json:"attraction"`
	Location        GeoCoordinate       `json:"location"`
	DistanceMeters  float64             `json:"distance_meters"`
}

type NearbyIntroductionQuery struct {
	Latitude     float64
	Longitude    float64
	RadiusMeters float64
	Limit        int
}

type NearbyIntroductionSet struct {
	Introductions []AttractionIntroduction
	TotalMatches  int
}

type RecognitionQuery struct {
	Latitude     float64
	Longitude    float64
	RadiusMeters float64
	HasLocation  bool
	Limit        int
}

type RecognitionElement struct {
	Key             string
	Name            string
	Introduction    json.RawMessage
	NearbyContexts  []AttractionIntroduction
	RelatedElements []CulturalElement
	GraphElements   []CulturalElement
	GraphRelations  []CulturalRelation
}

type CulturalRelation struct {
	ElementKey        string
	RelatedElementKey string
	Kind              string
	Explanation       string
}

type AttractionCandidate struct {
	Key                string
	Name               string
	CulturalElementKey string
	Summary            string
	DistanceMeters     float64
}

type RecognitionSet struct {
	Version              string
	Elements             []RecognitionElement
	AttractionCandidates []AttractionCandidate
	TotalElements        int
	NearbyContextCount   int
	LocationMatched      bool
}

type RecognitionRepository interface {
	RecognitionKnowledge(
		ctx context.Context,
		query RecognitionQuery,
	) (RecognitionSet, error)
}

type ContentRepository interface {
	RelatedElements(
		ctx context.Context,
		elementKey string,
		limit int,
	) (RelatedElementSet, error)
	NearbyIntroductions(
		ctx context.Context,
		query NearbyIntroductionQuery,
	) (NearbyIntroductionSet, error)
}
