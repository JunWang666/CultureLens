package contentadmin

import (
	"context"
	"encoding/json"
)

type CulturalElement struct {
	Key          string          `json:"key"`
	Name         string          `json:"name"`
	Introduction json.RawMessage `json:"introduction"`
}

type Attraction struct {
	Key  string `json:"key"`
	Name string `json:"name"`
}

type Relation struct {
	ElementKey        string `json:"elementKey"`
	RelatedElementKey string `json:"relatedElementKey"`
}

type AttractionIntroduction struct {
	Key                 string          `json:"key"`
	Name                string          `json:"name"`
	Introduction        json.RawMessage `json:"introduction"`
	CulturalElementKey  string          `json:"culturalElementKey"`
	CulturalElementName string          `json:"culturalElementName,omitempty"`
	AttractionKey       string          `json:"attractionKey"`
	AttractionName      string          `json:"attractionName,omitempty"`
	Latitude            float64         `json:"latitude"`
	Longitude           float64         `json:"longitude"`
	CoordinateSourceURL string          `json:"coordinateSourceUrl,omitempty"`
}

type Bundle struct {
	Version       string                   `json:"version"`
	Elements      []CulturalElement        `json:"elements"`
	Attractions   []Attraction             `json:"attractions"`
	Relations     []Relation               `json:"relations"`
	Introductions []AttractionIntroduction `json:"introductions"`
}

type Snapshot struct {
	Elements      []CulturalElement        `json:"elements"`
	Attractions   []Attraction             `json:"attractions"`
	Relations     []Relation               `json:"relations"`
	Introductions []AttractionIntroduction `json:"introductions"`
}

type ImportResult struct {
	Version       string `json:"version"`
	Elements      int    `json:"elements"`
	Attractions   int    `json:"attractions"`
	Relations     int    `json:"relations"`
	Introductions int    `json:"introductions"`
}

type Repository interface {
	Snapshot(context.Context) (Snapshot, error)
	UpsertElement(context.Context, CulturalElement) (CulturalElement, error)
	UpsertAttraction(context.Context, Attraction) (Attraction, error)
	UpsertIntroduction(
		context.Context,
		AttractionIntroduction,
	) (AttractionIntroduction, error)
	UpsertRelation(context.Context, Relation) error
	Import(context.Context, Bundle) (ImportResult, error)
}
