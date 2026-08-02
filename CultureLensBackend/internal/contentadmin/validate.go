package contentadmin

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/url"
	"regexp"
	"strings"
)

var contentKeyPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]{0,127}$`)

func ValidateElement(element CulturalElement) error {
	if !validKey(element.Key) || !validName(element.Name) {
		return errors.New("invalid cultural element key or name")
	}
	return validateRichText(element.Introduction)
}

func ValidateAttraction(attraction Attraction) error {
	if !validKey(attraction.Key) || !validName(attraction.Name) {
		return errors.New("invalid attraction key or name")
	}
	return nil
}

func ValidateRelation(relation Relation) error {
	if !validKey(relation.ElementKey) ||
		!validKey(relation.RelatedElementKey) ||
		relation.ElementKey == relation.RelatedElementKey {
		return errors.New("invalid cultural element relation")
	}
	return nil
}

func ValidateIntroduction(introduction AttractionIntroduction) error {
	if !validKey(introduction.Key) ||
		!validName(introduction.Name) ||
		!validKey(introduction.CulturalElementKey) ||
		!validKey(introduction.AttractionKey) ||
		!finite(introduction.Latitude) ||
		!finite(introduction.Longitude) ||
		introduction.Latitude < -90 || introduction.Latitude > 90 ||
		introduction.Longitude < -180 || introduction.Longitude > 180 {
		return errors.New("invalid attraction introduction fields")
	}
	if err := validateRichText(introduction.Introduction); err != nil {
		return err
	}
	if source := strings.TrimSpace(introduction.CoordinateSourceURL); source != "" {
		parsed, err := url.Parse(source)
		if err != nil || parsed.Scheme != "https" || parsed.Host == "" {
			return errors.New("coordinate source URL must use HTTPS")
		}
	}
	return nil
}

func ValidateBundle(bundle Bundle) error {
	if strings.TrimSpace(bundle.Version) == "" ||
		len(bundle.Elements) == 0 ||
		len(bundle.Attractions) == 0 ||
		len(bundle.Introductions) == 0 {
		return errors.New("content bundle is incomplete")
	}
	elementKeys := make(map[string]struct{}, len(bundle.Elements))
	for _, element := range bundle.Elements {
		if err := ValidateElement(element); err != nil {
			return fmt.Errorf("element %q: %w", element.Key, err)
		}
		if _, exists := elementKeys[element.Key]; exists {
			return fmt.Errorf("duplicate element key %q", element.Key)
		}
		elementKeys[element.Key] = struct{}{}
	}
	attractionKeys := make(map[string]struct{}, len(bundle.Attractions))
	for _, attraction := range bundle.Attractions {
		if err := ValidateAttraction(attraction); err != nil {
			return fmt.Errorf("attraction %q: %w", attraction.Key, err)
		}
		if _, exists := attractionKeys[attraction.Key]; exists {
			return fmt.Errorf("duplicate attraction key %q", attraction.Key)
		}
		attractionKeys[attraction.Key] = struct{}{}
	}
	for _, relation := range bundle.Relations {
		if err := ValidateRelation(relation); err != nil {
			return err
		}
		if _, exists := elementKeys[relation.ElementKey]; !exists {
			return fmt.Errorf("relation references missing element %q", relation.ElementKey)
		}
		if _, exists := elementKeys[relation.RelatedElementKey]; !exists {
			return fmt.Errorf("relation references missing element %q", relation.RelatedElementKey)
		}
	}
	introductionKeys := make(map[string]struct{}, len(bundle.Introductions))
	for _, introduction := range bundle.Introductions {
		if err := ValidateIntroduction(introduction); err != nil {
			return fmt.Errorf("introduction %q: %w", introduction.Key, err)
		}
		if _, exists := introductionKeys[introduction.Key]; exists {
			return fmt.Errorf("duplicate introduction key %q", introduction.Key)
		}
		introductionKeys[introduction.Key] = struct{}{}
		if _, exists := elementKeys[introduction.CulturalElementKey]; !exists {
			return fmt.Errorf(
				"introduction references missing element %q",
				introduction.CulturalElementKey,
			)
		}
		if _, exists := attractionKeys[introduction.AttractionKey]; !exists {
			return fmt.Errorf(
				"introduction references missing attraction %q",
				introduction.AttractionKey,
			)
		}
	}
	return nil
}

func validKey(value string) bool {
	return contentKeyPattern.MatchString(value)
}

func validName(value string) bool {
	value = strings.TrimSpace(value)
	return value != "" && len([]rune(value)) <= 200
}

func finite(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
}

func validateRichText(value json.RawMessage) error {
	var document struct {
		SchemaVersion int `json:"schemaVersion"`
		Blocks        []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"blocks"`
	}
	if err := json.Unmarshal(value, &document); err != nil {
		return errors.New("introduction must be valid JSON")
	}
	if document.SchemaVersion != 1 || len(document.Blocks) == 0 {
		return errors.New("introduction must use schemaVersion 1 with blocks")
	}
	for _, block := range document.Blocks {
		if strings.TrimSpace(block.Type) == "" || strings.TrimSpace(block.Text) == "" {
			return errors.New("introduction blocks require type and text")
		}
	}
	return nil
}
