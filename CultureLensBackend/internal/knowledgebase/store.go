package knowledgebase

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"
)

func LoadWikipediaSeed(path string) (WikipediaSeed, error) {
	payload, err := os.ReadFile(path)
	if err != nil {
		return WikipediaSeed{}, err
	}
	var seed WikipediaSeed
	if err := json.Unmarshal(payload, &seed); err != nil {
		return WikipediaSeed{}, fmt.Errorf("decode Wikipedia seed: %w", err)
	}
	return seed, nil
}

func Load(path string) (Bundle, error) {
	payload, err := os.ReadFile(path)
	if err != nil {
		return Bundle{}, err
	}
	var bundle Bundle
	if err := json.Unmarshal(payload, &bundle); err != nil {
		return Bundle{}, fmt.Errorf("decode knowledge bundle: %w", err)
	}
	if err := Validate(bundle); err != nil {
		return Bundle{}, err
	}
	return bundle, nil
}

func WriteAtomic(path string, bundle Bundle) error {
	if err := Validate(bundle); err != nil {
		return err
	}
	payload, err := json.MarshalIndent(bundle, "", "  ")
	if err != nil {
		return err
	}
	payload = append(payload, '\n')
	directory := filepath.Dir(path)
	if err := os.MkdirAll(directory, 0o755); err != nil {
		return err
	}
	temp, err := os.CreateTemp(directory, ".knowledge-bundle-*.json")
	if err != nil {
		return err
	}
	tempPath := temp.Name()
	defer os.Remove(tempPath)
	if err := temp.Chmod(0o644); err != nil {
		temp.Close()
		return err
	}
	if _, err := temp.Write(payload); err != nil {
		temp.Close()
		return err
	}
	if err := temp.Sync(); err != nil {
		temp.Close()
		return err
	}
	if err := temp.Close(); err != nil {
		return err
	}
	return os.Rename(tempPath, path)
}

func Validate(bundle Bundle) error {
	if strings.TrimSpace(bundle.Version) == "" {
		return errors.New("knowledge bundle version is required")
	}
	if _, err := time.Parse(time.RFC3339, bundle.GeneratedAt); err != nil {
		return errors.New("knowledge bundle generated_at must be RFC3339")
	}
	if len(bundle.Records) == 0 {
		return errors.New("knowledge bundle must contain records")
	}

	recordIDs := make(map[string]Record, len(bundle.Records))
	sourceKeys := make(map[string]struct{}, len(bundle.Records))
	citationIDs := make(map[string]struct{}, len(bundle.Records))
	for index, record := range bundle.Records {
		if err := validateRecord(record); err != nil {
			return fmt.Errorf("knowledge record %d: %w", index, err)
		}
		normalizedID := strings.ToLower(record.ID)
		if _, exists := recordIDs[normalizedID]; exists {
			return fmt.Errorf("duplicate knowledge record ID %s", record.ID)
		}
		recordIDs[normalizedID] = record
		if _, exists := sourceKeys[record.SourceKey]; exists {
			return fmt.Errorf("duplicate knowledge source key %s", record.SourceKey)
		}
		sourceKeys[record.SourceKey] = struct{}{}
		for _, citation := range record.Citations {
			normalizedCitationID := strings.ToLower(citation.ID)
			if _, exists := citationIDs[normalizedCitationID]; exists {
				return fmt.Errorf("duplicate citation ID %s", citation.ID)
			}
			citationIDs[normalizedCitationID] = struct{}{}
		}
	}

	relationIDs := make(map[string]struct{}, len(bundle.Relations))
	for index, relation := range bundle.Relations {
		if err := validateRelation(relation, recordIDs, citationIDs); err != nil {
			return fmt.Errorf("knowledge relation %d: %w", index, err)
		}
		normalizedID := strings.ToLower(relation.ID)
		if _, exists := relationIDs[normalizedID]; exists {
			return fmt.Errorf("duplicate relation ID %s", relation.ID)
		}
		relationIDs[normalizedID] = struct{}{}
	}

	expected := calculateStatistics(bundle)
	if bundle.Statistics.TotalRecords != expected.TotalRecords ||
		bundle.Statistics.TotalRelations != expected.TotalRelations ||
		!mapsEqual(bundle.Statistics.ByKind, expected.ByKind) ||
		!mapsEqual(bundle.Statistics.BySource, expected.BySource) {
		return errors.New("knowledge bundle statistics do not match content")
	}
	if !slices.IsSortedFunc(bundle.Records, compareRecords) {
		return errors.New("knowledge records are not stably sorted")
	}
	if !slices.IsSortedFunc(bundle.Relations, compareRelations) {
		return errors.New("knowledge relations are not stably sorted")
	}
	return nil
}

func validateRecord(record Record) error {
	if _, err := uuid.Parse(record.ID); err != nil {
		return errors.New("record ID must be a UUID")
	}
	if strings.TrimSpace(record.SourceKey) == "" ||
		strings.TrimSpace(record.CanonicalName) == "" ||
		strings.TrimSpace(record.Summary) == "" ||
		strings.TrimSpace(record.ContentFingerprint) == "" ||
		!validKind(record.Kind) ||
		!validReviewStatus(record.ReviewStatus) {
		return errors.New("record identity, content, kind, and review status are required")
	}
	if len(record.ContentFingerprint) != 64 {
		return errors.New("record content fingerprint must be SHA-256")
	}
	seenAttributes := make(map[string]struct{}, len(record.Attributes))
	for _, attribute := range record.Attributes {
		if strings.TrimSpace(attribute.Key) == "" ||
			strings.TrimSpace(attribute.Value) == "" {
			return errors.New("attribute key and value are required")
		}
		key := attribute.Key + "\x00" + attribute.Value
		if _, exists := seenAttributes[key]; exists {
			return errors.New("duplicate attribute")
		}
		seenAttributes[key] = struct{}{}
	}
	if len(record.Citations) == 0 {
		return errors.New("at least one citation is required")
	}
	for _, citation := range record.Citations {
		if err := validateCitation(citation); err != nil {
			return err
		}
	}
	for _, media := range record.MediaReferences {
		if _, err := url.ParseRequestURI(media.URL); err != nil ||
			strings.TrimSpace(media.Role) == "" ||
			strings.TrimSpace(media.RightsStatement) == "" {
			return errors.New("media reference URL, role, and rights statement are required")
		}
	}
	if strings.HasPrefix(record.SourceKey, "srom:") {
		if record.ReviewStatus != ReviewStatusImported {
			return errors.New("SROM records cannot be auto-reviewed")
		}
		for _, citation := range record.Citations {
			if citation.License != "" {
				return errors.New("SROM citations must not invent a license")
			}
		}
	}
	if strings.HasPrefix(record.SourceKey, "wikipedia:") {
		revisionFound := false
		for _, attribute := range record.Attributes {
			if attribute.Key == "wikipedia_revision" && attribute.Value != "" {
				revisionFound = true
			}
		}
		if !revisionFound ||
			record.Citations[0].License != "CC BY-SA 4.0" ||
			!record.Citations[0].Modified {
			return errors.New("Wikipedia records require revision, CC BY-SA 4.0, and modified flag")
		}
	}
	return nil
}

func validateCitation(citation Citation) error {
	if _, err := uuid.Parse(citation.ID); err != nil {
		return errors.New("citation ID must be a UUID")
	}
	if strings.TrimSpace(citation.SourceType) == "" ||
		strings.TrimSpace(citation.Title) == "" ||
		strings.TrimSpace(citation.Publisher) == "" {
		return errors.New("citation type, title, and publisher are required")
	}
	if _, err := url.ParseRequestURI(citation.URL); err != nil {
		return errors.New("citation URL is invalid")
	}
	if _, err := time.Parse(time.RFC3339, citation.AccessedAt); err != nil {
		return errors.New("citation accessed_at must be RFC3339")
	}
	if (citation.License == "") != (citation.LicenseURL == "") {
		return errors.New("citation license and license URL must be supplied together")
	}
	return nil
}

func validateRelation(
	relation Relation,
	records map[string]Record,
	citations map[string]struct{},
) error {
	if _, err := uuid.Parse(relation.ID); err != nil {
		return errors.New("relation ID must be a UUID")
	}
	if _, exists := records[strings.ToLower(relation.SourceID)]; !exists {
		return errors.New("relation source does not exist")
	}
	if _, exists := records[strings.ToLower(relation.TargetID)]; !exists {
		return errors.New("relation target does not exist")
	}
	if relation.SourceID == relation.TargetID ||
		strings.TrimSpace(relation.Kind) == "" ||
		strings.TrimSpace(relation.Explanation) == "" ||
		!validReviewStatus(relation.ReviewStatus) ||
		len(relation.CitationIDs) == 0 {
		return errors.New("relation kind, explanation, review status, and citations are required")
	}
	for _, citationID := range relation.CitationIDs {
		if _, exists := citations[strings.ToLower(citationID)]; !exists {
			return errors.New("relation citation does not exist")
		}
	}
	return nil
}

func validKind(kind string) bool {
	switch kind {
	case "artifact", "route", "place", "person", "material", "concept":
		return true
	default:
		return false
	}
}

func validReviewStatus(status string) bool {
	return status == ReviewStatusImported || status == ReviewStatusReviewed
}

func mapsEqual(left, right map[string]int) bool {
	if len(left) != len(right) {
		return false
	}
	for key, value := range left {
		if right[key] != value {
			return false
		}
	}
	return true
}
