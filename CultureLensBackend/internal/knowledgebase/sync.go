package knowledgebase

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

const (
	defaultSROMPageSize = 500
	maxSROMPages        = 100
	maxSROMResponseSize = 64 << 20
)

var knowledgeNamespace = uuid.MustParse("B9B98A1F-4678-5B4C-B0DE-B578043EE48A")

type SROMClient struct {
	BaseURL   string
	HTTP      *http.Client
	UserAgent string
	PageSize  int
}

type SROMCollection struct {
	CollectionID      int64  `json:"collectionId"`
	CollectionName    string `json:"collectionName"`
	ENCollectionName  string `json:"enCollectionName"`
	CollectionImage   string `json:"collectionImg"`
	Size              string `json:"size"`
	MaterialName      string `json:"materialName"`
	YearsName         string `json:"yearsName"`
	RegionName        string `json:"regionName"`
	RepositoryName    string `json:"repositoryName"`
	ThemeName         string `json:"themeName"`
	DescriptionHTML   string `json:"describe"`
	ENDescriptionHTML string `json:"enDescribe"`
}

type sromListResponse struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    struct {
		List  []SROMCollection `json:"list"`
		Total int              `json:"total"`
	} `json:"data"`
}

func (c SROMClient) FetchCollections(ctx context.Context) ([]SROMCollection, error) {
	if c.HTTP == nil {
		return nil, errors.New("SROM HTTP client is required")
	}
	baseURL := strings.TrimRight(strings.TrimSpace(c.BaseURL), "/")
	if _, err := url.ParseRequestURI(baseURL); err != nil {
		return nil, errors.New("SROM base URL is invalid")
	}
	pageSize := c.PageSize
	if pageSize <= 0 {
		pageSize = defaultSROMPageSize
	}

	first, err := c.fetchPage(ctx, baseURL, 1, pageSize)
	if err != nil {
		return nil, err
	}
	collections := append([]SROMCollection(nil), first.Data.List...)
	total := first.Data.Total
	if total < len(collections) {
		return nil, fmt.Errorf("SROM total %d is smaller than first page size %d", total, len(collections))
	}
	pageCount := max(1, (total+pageSize-1)/pageSize)
	if pageCount > maxSROMPages {
		return nil, fmt.Errorf("SROM page count %d exceeds safety limit", pageCount)
	}
	for page := 2; page <= pageCount; page++ {
		response, err := c.fetchPage(ctx, baseURL, page, pageSize)
		if err != nil {
			return nil, err
		}
		collections = append(collections, response.Data.List...)
	}
	if len(collections) != total {
		return nil, fmt.Errorf("SROM returned %d collections, expected %d", len(collections), total)
	}

	seen := make(map[int64]struct{}, len(collections))
	for _, collection := range collections {
		if collection.CollectionID <= 0 {
			return nil, errors.New("SROM collection ID must be positive")
		}
		if _, exists := seen[collection.CollectionID]; exists {
			return nil, fmt.Errorf("duplicate SROM collection ID %d", collection.CollectionID)
		}
		seen[collection.CollectionID] = struct{}{}
	}
	return collections, nil
}

func (c SROMClient) fetchPage(
	ctx context.Context,
	baseURL string,
	page, pageSize int,
) (sromListResponse, error) {
	body, err := json.Marshal(map[string]any{
		"materialId":       0,
		"page":             page,
		"regionId":         0,
		"repositoryId":     0,
		"size":             pageSize,
		"themeId":          0,
		"yearsId":          0,
		"collectionName":   "",
		"enCollectionName": "",
	})
	if err != nil {
		return sromListResponse{}, err
	}
	request, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		baseURL+"/api/collection/list_web",
		bytes.NewReader(body),
	)
	if err != nil {
		return sromListResponse{}, err
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Accept", "application/json")
	request.Header.Set("token", "empty")
	if strings.TrimSpace(c.UserAgent) != "" {
		request.Header.Set("User-Agent", c.UserAgent)
	}

	response, err := c.HTTP.Do(request)
	if err != nil {
		return sromListResponse{}, fmt.Errorf("fetch SROM page %d: %w", page, err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
		return sromListResponse{}, fmt.Errorf(
			"fetch SROM page %d: unexpected HTTP %d",
			page,
			response.StatusCode,
		)
	}

	limited := io.LimitReader(response.Body, maxSROMResponseSize+1)
	payload, err := io.ReadAll(limited)
	if err != nil {
		return sromListResponse{}, fmt.Errorf("read SROM page %d: %w", page, err)
	}
	if len(payload) > maxSROMResponseSize {
		return sromListResponse{}, fmt.Errorf("SROM page %d exceeds response limit", page)
	}
	var decoded sromListResponse
	if err := json.Unmarshal(payload, &decoded); err != nil {
		return sromListResponse{}, fmt.Errorf("decode SROM page %d: %w", page, err)
	}
	if decoded.Code != http.StatusOK {
		return sromListResponse{}, fmt.Errorf(
			"SROM page %d failed with code %d: %s",
			page,
			decoded.Code,
			decoded.Message,
		)
	}
	return decoded, nil
}

func BuildBundle(
	version string,
	generatedAt time.Time,
	collections []SROMCollection,
	wikipedia WikipediaSeed,
) (Bundle, error) {
	version = strings.TrimSpace(version)
	if version == "" {
		return Bundle{}, errors.New("knowledge bundle version is required")
	}
	if generatedAt.IsZero() {
		return Bundle{}, errors.New("knowledge bundle generation time is required")
	}

	records := make([]Record, 0, len(collections)+len(wikipedia.Records))
	for _, collection := range collections {
		record, err := recordFromSROM(collection, generatedAt)
		if err != nil {
			return Bundle{}, err
		}
		records = append(records, record)
	}
	wikipediaRecords, relations, err := recordsFromWikipedia(wikipedia)
	if err != nil {
		return Bundle{}, err
	}
	records = append(records, wikipediaRecords...)
	slices.SortFunc(records, compareRecords)
	slices.SortFunc(relations, compareRelations)

	bundle := Bundle{
		Version:     version,
		GeneratedAt: generatedAt.UTC().Format(time.RFC3339),
		Records:     records,
		Relations:   relations,
	}
	bundle.Statistics = calculateStatistics(bundle)
	if err := Validate(bundle); err != nil {
		return Bundle{}, err
	}
	return bundle, nil
}

func recordFromSROM(collection SROMCollection, accessedAt time.Time) (Record, error) {
	name := cleanText(collection.CollectionName)
	if collection.CollectionID <= 0 || name == "" {
		return Record{}, fmt.Errorf("invalid SROM collection %d", collection.CollectionID)
	}
	sourceKey := "srom:collection:" + strconv.FormatInt(collection.CollectionID, 10)
	recordID := stableID(sourceKey)
	sourceURL := "https://srom.123bingo.cn/collectionDetails?collectionId=" +
		strconv.FormatInt(collection.CollectionID, 10)
	citationID := stableID("citation:" + sourceKey)
	raw, err := json.Marshal(collection)
	if err != nil {
		return Record{}, err
	}
	record := Record{
		ID:            recordID,
		SourceKey:     sourceKey,
		Kind:          "artifact",
		CanonicalName: name,
		Summary:       sromSummary(collection),
		Attributes: []Attribute{{
			Key:   "external_id",
			Value: strconv.FormatInt(collection.CollectionID, 10),
		}},
		Citations: []Citation{{
			ID:              citationID,
			SourceType:      "srom",
			Title:           name,
			Publisher:       "丝绸之路数字博物馆（SROM）",
			URL:             sourceURL,
			AccessedAt:      accessedAt.UTC().Format(time.RFC3339),
			RightsStatement: "来源未提供可再分发许可；仅保存事实型元数据和来源链接。",
			Modified:        true,
		}},
		ReviewStatus:       ReviewStatusImported,
		ContentFingerprint: fingerprint(raw),
	}
	if alias := cleanText(collection.ENCollectionName); alias != "" &&
		!strings.EqualFold(alias, name) {
		record.Aliases = []string{alias}
	}
	record.Attributes = appendOptionalAttribute(
		record.Attributes,
		"material",
		collection.MaterialName,
	)
	record.Attributes = appendOptionalAttribute(
		record.Attributes,
		"period",
		collection.YearsName,
	)
	record.Attributes = appendOptionalAttribute(
		record.Attributes,
		"region",
		collection.RegionName,
	)
	record.Attributes = appendOptionalAttribute(
		record.Attributes,
		"holding_institution",
		collection.RepositoryName,
	)
	record.Attributes = appendOptionalAttribute(
		record.Attributes,
		"theme",
		collection.ThemeName,
	)
	record.Attributes = appendOptionalAttribute(
		record.Attributes,
		"dimensions",
		collection.Size,
	)
	if imageURL := cleanText(collection.CollectionImage); imageURL != "" {
		if _, err := url.ParseRequestURI(imageURL); err == nil {
			record.MediaReferences = []MediaReference{{
				URL:             imageURL,
				Role:            "source_reference",
				RightsStatement: "仅作来源定位；未下载、未打包，使用前需取得逐项授权。",
			}}
		}
	}
	return record, nil
}

func recordsFromWikipedia(seed WikipediaSeed) ([]Record, []Relation, error) {
	if strings.TrimSpace(seed.Version) == "" ||
		strings.TrimSpace(seed.AccessedAt) == "" ||
		strings.TrimSpace(seed.License) == "" ||
		strings.TrimSpace(seed.LicenseURL) == "" {
		return nil, nil, errors.New("Wikipedia seed metadata is incomplete")
	}
	if _, err := time.Parse(time.RFC3339, seed.AccessedAt); err != nil {
		return nil, nil, errors.New("Wikipedia seed accessed_at must be RFC3339")
	}
	records := make([]Record, 0, len(seed.Records))
	byTitle := make(map[string]Record, len(seed.Records))
	for _, item := range seed.Records {
		title := cleanText(item.Title)
		name := cleanText(item.CanonicalName)
		if title == "" || name == "" || cleanText(item.Summary) == "" ||
			cleanText(item.RevisionID) == "" {
			return nil, nil, errors.New("Wikipedia seed record is incomplete")
		}
		sourceKey := "wikipedia:zh:" + normalizeKey(title)
		recordID := stableID(sourceKey)
		citationID := stableID("citation:" + sourceKey)
		attributes := []Attribute{{
			Key:   "wikipedia_revision",
			Value: item.RevisionID,
		}}
		raw, err := json.Marshal(item)
		if err != nil {
			return nil, nil, err
		}
		record := Record{
			ID:            recordID,
			SourceKey:     sourceKey,
			Kind:          item.Kind,
			CanonicalName: name,
			Aliases:       cleanUnique(item.Aliases),
			Summary:       cleanText(item.Summary),
			Attributes:    attributes,
			Citations: []Citation{{
				ID:         citationID,
				SourceType: "wikipedia",
				Title:      title + "（固定修订版）",
				Publisher:  "中文维基百科贡献者",
				URL:        item.URL,
				AccessedAt: seed.AccessedAt,
				License:    seed.License,
				LicenseURL: seed.LicenseURL,
				Modified:   true,
				RevisionID: item.RevisionID,
			}},
			ReviewStatus:       ReviewStatusImported,
			ContentFingerprint: fingerprint(raw),
		}
		if _, exists := byTitle[normalizeKey(title)]; exists {
			return nil, nil, fmt.Errorf("duplicate Wikipedia title %q", title)
		}
		records = append(records, record)
		byTitle[normalizeKey(title)] = record
	}

	relations := make([]Relation, 0)
	for _, item := range seed.Records {
		source := byTitle[normalizeKey(item.Title)]
		for _, link := range item.Relations {
			target, exists := byTitle[normalizeKey(link.TargetTitle)]
			if !exists {
				return nil, nil, fmt.Errorf(
					"Wikipedia relation target %q is missing",
					link.TargetTitle,
				)
			}
			kind := cleanText(link.Kind)
			explanation := cleanText(link.Explanation)
			if kind == "" || explanation == "" {
				return nil, nil, errors.New("Wikipedia relation is incomplete")
			}
			relations = append(relations, Relation{
				ID:           stableID(source.ID + ":" + kind + ":" + target.ID),
				SourceID:     source.ID,
				TargetID:     target.ID,
				Kind:         kind,
				Explanation:  explanation,
				CitationIDs:  []string{source.Citations[0].ID, target.Citations[0].ID},
				ReviewStatus: ReviewStatusImported,
			})
		}
	}
	return records, relations, nil
}

func sromSummary(collection SROMCollection) string {
	name := cleanText(collection.CollectionName)
	parts := []string{"SROM 收录的" + name}
	if period := cleanText(collection.YearsName); period != "" {
		parts = append(parts, "年代为"+period)
	}
	if material := cleanText(collection.MaterialName); material != "" {
		parts = append(parts, "材质为"+material)
	}
	if region := cleanText(collection.RegionName); region != "" {
		parts = append(parts, "地区标注为"+region)
	}
	if repository := cleanText(collection.RepositoryName); repository != "" {
		parts = append(parts, "现藏"+repository)
	}
	return strings.Join(parts, "，") + "。"
}

func appendOptionalAttribute(
	attributes []Attribute,
	key, value string,
) []Attribute {
	value = cleanText(value)
	if value == "" {
		return attributes
	}
	return append(attributes, Attribute{Key: key, Value: value})
}

func calculateStatistics(bundle Bundle) Statistics {
	statistics := Statistics{
		TotalRecords:   len(bundle.Records),
		TotalRelations: len(bundle.Relations),
		ByKind:         make(map[string]int),
		BySource:       make(map[string]int),
	}
	for _, record := range bundle.Records {
		statistics.ByKind[record.Kind]++
		if len(record.Citations) > 0 {
			statistics.BySource[record.Citations[0].SourceType]++
		}
	}
	return statistics
}

func compareRecords(left, right Record) int {
	if result := strings.Compare(left.CanonicalName, right.CanonicalName); result != 0 {
		return result
	}
	return strings.Compare(left.ID, right.ID)
}

func compareRelations(left, right Relation) int {
	if result := strings.Compare(left.SourceID, right.SourceID); result != 0 {
		return result
	}
	if result := strings.Compare(left.Kind, right.Kind); result != 0 {
		return result
	}
	return strings.Compare(left.TargetID, right.TargetID)
}

func cleanText(value string) string {
	return strings.Join(strings.Fields(strings.TrimSpace(value)), " ")
}

func cleanUnique(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	cleaned := make([]string, 0, len(values))
	for _, value := range values {
		value = cleanText(value)
		key := normalizeKey(value)
		if key == "" {
			continue
		}
		if _, exists := seen[key]; exists {
			continue
		}
		seen[key] = struct{}{}
		cleaned = append(cleaned, value)
	}
	slices.Sort(cleaned)
	return cleaned
}

func normalizeKey(value string) string {
	return strings.ToLower(strings.Join(strings.Fields(strings.TrimSpace(value)), ""))
}

func stableID(value string) string {
	return uuid.NewSHA1(knowledgeNamespace, []byte(value)).String()
}

func fingerprint(payload []byte) string {
	sum := sha256.Sum256(payload)
	return hex.EncodeToString(sum[:])
}
