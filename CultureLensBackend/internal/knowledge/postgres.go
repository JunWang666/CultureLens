package knowledge

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/goudaijun/culturelens-backend/internal/database/dbgen"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type ContentStats struct {
	CulturalElementCount int
	IntroductionCount    int
}

type PostgresRepository struct {
	pool    *pgxpool.Pool
	queries *dbgen.Queries
	stats   ContentStats
}

func NewPostgresRepository(
	ctx context.Context,
	databaseURL string,
) (*PostgresRepository, error) {
	databaseURL = strings.TrimSpace(databaseURL)
	if databaseURL == "" {
		return nil, errors.New("database URL is required")
	}
	poolConfig, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse database URL: %w", err)
	}
	poolConfig.MaxConns = 4
	poolConfig.MinConns = 1
	poolConfig.MaxConnLifetime = 30 * time.Minute
	poolConfig.MaxConnIdleTime = 5 * time.Minute
	poolConfig.HealthCheckPeriod = time.Minute
	poolConfig.ConnConfig.RuntimeParams["application_name"] = "culturelens-api"
	poolConfig.ConnConfig.RuntimeParams["timezone"] = "UTC"

	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		return nil, fmt.Errorf("open PostgreSQL pool: %w", err)
	}
	closeOnError := true
	defer func() {
		if closeOnError {
			pool.Close()
		}
	}()
	if err := pool.Ping(ctx); err != nil {
		return nil, fmt.Errorf("ping PostgreSQL: %w", err)
	}
	queries := dbgen.New(pool)
	contentStats, err := queries.GetCulturalContentStats(ctx)
	if err != nil {
		return nil, fmt.Errorf("read cultural content stats: %w", err)
	}
	repository := &PostgresRepository{
		pool:    pool,
		queries: queries,
		stats: ContentStats{
			CulturalElementCount: int(contentStats.CulturalElementCount),
			IntroductionCount:    int(contentStats.IntroductionCount),
		},
	}
	closeOnError = false
	return repository, nil
}

func (r *PostgresRepository) RelatedElements(
	ctx context.Context,
	elementKey string,
	limit int,
) (RelatedElementSet, error) {
	elementKey = strings.TrimSpace(elementKey)
	if limit <= 0 {
		limit = defaultCandidateLimit
	} else if limit > maximumObjectLimit {
		limit = maximumObjectLimit
	}
	originRow, err := r.queries.GetCulturalElement(ctx, elementKey)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return RelatedElementSet{}, ErrCulturalElementNotFound
		}
		return RelatedElementSet{}, fmt.Errorf(
			"query PostgreSQL cultural element %q: %w",
			elementKey,
			err,
		)
	}
	origin := hydrateCulturalElement(
		originRow.Key,
		originRow.Name,
		originRow.Introduction,
	)
	rows, err := r.queries.ListRelatedCulturalElements(
		ctx,
		dbgen.ListRelatedCulturalElementsParams{
			ElementKey:   elementKey,
			RelatedLimit: int32(limit),
		},
	)
	if err != nil {
		return RelatedElementSet{}, fmt.Errorf(
			"query PostgreSQL related cultural elements for %q: %w",
			elementKey,
			err,
		)
	}
	related := make([]CulturalElement, 0, len(rows))
	for _, row := range rows {
		related = append(
			related,
			hydrateCulturalElement(row.Key, row.Name, row.Introduction),
		)
	}
	return RelatedElementSet{
		Element:         origin,
		RelatedElements: related,
	}, nil
}

func (r *PostgresRepository) NearbyIntroductions(
	ctx context.Context,
	query NearbyIntroductionQuery,
) (NearbyIntroductionSet, error) {
	limit := query.Limit
	if limit <= 0 {
		limit = defaultCandidateLimit
	} else if limit > maximumObjectLimit {
		limit = maximumObjectLimit
	}
	if !finiteCoordinate(query.Latitude) ||
		!finiteCoordinate(query.Longitude) ||
		!finiteCoordinate(query.RadiusMeters) ||
		query.Latitude < -90 || query.Latitude > 90 ||
		query.Longitude < -180 || query.Longitude > 180 ||
		query.RadiusMeters <= 0 {
		return NearbyIntroductionSet{}, errors.New("invalid nearby introduction query")
	}
	rows, err := r.queries.ListNearbyAttractionCulturalIntroductions(
		ctx,
		dbgen.ListNearbyAttractionCulturalIntroductionsParams{
			Latitude:     query.Latitude,
			Longitude:    query.Longitude,
			RadiusMeters: query.RadiusMeters,
			ResultLimit:  int32(limit),
		},
	)
	if err != nil {
		return NearbyIntroductionSet{}, fmt.Errorf(
			"query nearby attraction introductions: %w",
			err,
		)
	}
	introductions := make([]AttractionIntroduction, 0, len(rows))
	totalMatches := 0
	for _, row := range rows {
		totalMatches = int(row.TotalMatches)
		introductions = append(introductions, AttractionIntroduction{
			Key:          row.Key,
			Name:         row.Name,
			Introduction: append(json.RawMessage(nil), row.Introduction...),
			CulturalElement: CulturalElement{
				Key:  row.CulturalElementKey,
				Name: row.CulturalElementName,
			},
			Attraction: AttractionReference{
				Key:  row.AttractionKey,
				Name: row.AttractionName,
			},
			Location: GeoCoordinate{
				Latitude:  row.Latitude,
				Longitude: row.Longitude,
			},
			DistanceMeters: row.DistanceMeters,
		})
	}
	return NearbyIntroductionSet{
		Introductions: introductions,
		TotalMatches:  totalMatches,
	}, nil
}

func hydrateCulturalElement(
	key string,
	name string,
	introduction []byte,
) CulturalElement {
	return CulturalElement{
		Key:          key,
		Name:         name,
		Introduction: append(json.RawMessage(nil), introduction...),
	}
}

func finiteCoordinate(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
}

func (r *PostgresRepository) Close() {
	if r != nil && r.pool != nil {
		r.pool.Close()
	}
}

func (r *PostgresRepository) Stats() ContentStats {
	if r == nil {
		return ContentStats{}
	}
	return r.stats
}

func (r *PostgresRepository) RecognitionKnowledge(
	ctx context.Context,
	query RecognitionQuery,
) (RecognitionSet, error) {
	rows, err := r.queries.ListCulturalElements(ctx)
	if err != nil {
		return RecognitionSet{}, fmt.Errorf(
			"query recognition cultural elements: %w",
			err,
		)
	}

	limit := query.Limit
	if limit <= 0 {
		limit = defaultCandidateLimit
	} else if limit > maximumObjectLimit {
		limit = maximumObjectLimit
	}
	elementsByKey := make(map[string]RecognitionElement, len(rows))
	orderedKeys := make([]string, 0, len(rows))
	for _, row := range rows {
		elementsByKey[row.Key] = RecognitionElement{
			Key:             row.Key,
			Name:            row.Name,
			Introduction:    append(json.RawMessage(nil), row.Introduction...),
			NearbyContexts:  []AttractionIntroduction{},
			RelatedElements: []CulturalElement{},
			GraphElements:   []CulturalElement{},
			GraphRelations:  []CulturalRelation{},
		}
		orderedKeys = append(orderedKeys, row.Key)
	}

	var nearby []AttractionIntroduction
	if query.HasLocation && len(rows) > 0 {
		radius := query.RadiusMeters
		if radius <= 0 {
			radius = 50_000
		}
		set, err := r.NearbyIntroductions(
			ctx,
			NearbyIntroductionQuery{
				Latitude:     query.Latitude,
				Longitude:    query.Longitude,
				RadiusMeters: radius,
				Limit:        maximumObjectLimit,
			},
		)
		if err != nil {
			return RecognitionSet{}, fmt.Errorf(
				"query recognition place contexts: %w",
				err,
			)
		}
		nearby = set.Introductions
		for _, introduction := range nearby {
			element, exists := elementsByKey[introduction.CulturalElement.Key]
			if !exists {
				continue
			}
			element.NearbyContexts = append(
				element.NearbyContexts,
				introduction,
			)
			elementsByKey[element.Key] = element
		}
	}

	attractionRoots := make(map[string]string)
	attractionNames := make(map[string]string)
	attractionBindings := make(map[string]map[string]struct{})
	for _, introduction := range nearby {
		attractionKey := introduction.Attraction.Key
		if _, exists := attractionRoots[attractionKey]; !exists {
			attractionRoots[attractionKey] = introduction.CulturalElement.Key
			attractionNames[attractionKey] = introduction.Attraction.Name
		}
		if attractionBindings[attractionKey] == nil {
			attractionBindings[attractionKey] = make(map[string]struct{})
		}
		attractionBindings[attractionKey][introduction.CulturalElement.Key] = struct{}{}
	}

	prioritizedKeys := make([]string, 0, len(orderedKeys))
	seen := make(map[string]struct{}, len(orderedKeys))
	for _, introduction := range nearby {
		key := attractionRoots[introduction.Attraction.Key]
		if _, exists := seen[key]; exists {
			continue
		}
		seen[key] = struct{}{}
		prioritizedKeys = append(prioritizedKeys, key)
	}
	for _, introduction := range nearby {
		key := introduction.CulturalElement.Key
		if _, exists := elementsByKey[key]; !exists {
			continue
		}
		if _, exists := seen[key]; exists {
			continue
		}
		seen[key] = struct{}{}
		prioritizedKeys = append(prioritizedKeys, key)
	}
	for _, key := range orderedKeys {
		if _, exists := seen[key]; exists {
			continue
		}
		seen[key] = struct{}{}
		prioritizedKeys = append(prioritizedKeys, key)
	}

	selectedKeys := prioritizedKeys[:min(limit, len(prioritizedKeys))]
	relationRows, err := r.queries.ListCulturalElementRelations(ctx)
	if err != nil {
		return RecognitionSet{}, fmt.Errorf("query recognition graph relations: %w", err)
	}
	elements := make([]RecognitionElement, 0, len(selectedKeys))
	for _, key := range selectedKeys {
		relatedRows, err := r.queries.ListRelatedCulturalElements(
			ctx,
			dbgen.ListRelatedCulturalElementsParams{
				ElementKey:   key,
				RelatedLimit: int32(maximumObjectLimit),
			},
		)
		if err != nil {
			return RecognitionSet{}, fmt.Errorf(
				"query recognition cultural relations for %q: %w",
				key,
				err,
			)
		}
		element := elementsByKey[key]
		element.RelatedElements = make([]CulturalElement, 0, len(relatedRows))
		for _, relatedRow := range relatedRows {
			element.RelatedElements = append(element.RelatedElements, hydrateCulturalElement(
				relatedRow.Key,
				relatedRow.Name,
				relatedRow.Introduction,
			))
		}
		element.GraphElements, element.GraphRelations = recognitionGraph(
			key,
			elementsByKey,
			relationRows,
			3,
			32,
		)
		element.GraphElements, element.GraphRelations = appendAttractionBindings(
			key,
			attractionRoots,
			attractionNames,
			attractionBindings,
			elementsByKey,
			element.GraphElements,
			element.GraphRelations,
		)
		elements = append(elements, element)
	}
	attractionCandidates := make([]AttractionCandidate, 0, len(nearby))
	seenAttractions := make(map[string]struct{}, len(nearby))
	for _, introduction := range nearby {
		if _, exists := seenAttractions[introduction.Attraction.Key]; exists {
			continue
		}
		seenAttractions[introduction.Attraction.Key] = struct{}{}
		attractionCandidates = append(attractionCandidates, AttractionCandidate{
			Key:                introduction.Attraction.Key,
			Name:               introduction.Attraction.Name,
			CulturalElementKey: attractionRoots[introduction.Attraction.Key],
			Summary:            richTextPlainText(introduction.Introduction),
			DistanceMeters:     introduction.DistanceMeters,
		})
	}
	return RecognitionSet{
		Version:              "cultural-elements-v1",
		Elements:             elements,
		AttractionCandidates: attractionCandidates,
		TotalElements:        len(rows),
		NearbyContextCount:   len(nearby),
		LocationMatched:      len(nearby) > 0,
	}, nil
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
	return strings.Join(parts, "\n\n")
}

func recognitionGraph(
	rootKey string,
	elements map[string]RecognitionElement,
	relations []dbgen.ListCulturalElementRelationsRow,
	maxDepth int,
	maxNodes int,
) ([]CulturalElement, []CulturalRelation) {
	depths := map[string]int{rootKey: 0}
	queue := []string{rootKey}
	for len(queue) > 0 && len(depths) < maxNodes+1 {
		current := queue[0]
		queue = queue[1:]
		depth := depths[current]
		if depth >= maxDepth {
			continue
		}
		for _, relation := range relations {
			next := ""
			if relation.ElementKey == current {
				next = relation.RelatedElementKey
			} else if relation.RelatedElementKey == current {
				next = relation.ElementKey
			}
			if next == "" {
				continue
			}
			if _, exists := elements[next]; exists {
				if _, seen := depths[next]; !seen && len(depths) < maxNodes+1 {
					depths[next] = depth + 1
					queue = append(queue, next)
				}
			}
		}
	}
	graphElements := make([]CulturalElement, 0, len(depths)-1)
	for _, key := range sortedGraphKeys(depths) {
		if key == rootKey {
			continue
		}
		element := elements[key]
		graphElements = append(graphElements, CulturalElement{
			Key:          element.Key,
			Name:         element.Name,
			Introduction: append(json.RawMessage(nil), element.Introduction...),
		})
	}
	graphRelations := make([]CulturalRelation, 0)
	for _, relation := range relations {
		if _, sourceExists := depths[relation.ElementKey]; !sourceExists {
			continue
		}
		if _, targetExists := depths[relation.RelatedElementKey]; !targetExists {
			continue
		}
		graphRelations = append(graphRelations, CulturalRelation{
			ElementKey:        relation.ElementKey,
			RelatedElementKey: relation.RelatedElementKey,
			Kind:              "解释",
			Explanation:       "文化内容库记录了两个概念之间的显式关联。",
		})
	}
	return graphElements, graphRelations
}

func appendAttractionBindings(
	rootKey string,
	attractionRoots map[string]string,
	attractionNames map[string]string,
	bindings map[string]map[string]struct{},
	elements map[string]RecognitionElement,
	graphElements []CulturalElement,
	graphRelations []CulturalRelation,
) ([]CulturalElement, []CulturalRelation) {
	seenElements := make(map[string]struct{}, len(graphElements)+1)
	seenElements[rootKey] = struct{}{}
	for _, element := range graphElements {
		seenElements[element.Key] = struct{}{}
	}
	seenEdges := make(map[string]struct{}, len(graphRelations))
	for _, relation := range graphRelations {
		seenEdges[relation.ElementKey+"\x00"+relation.RelatedElementKey] = struct{}{}
		seenEdges[relation.RelatedElementKey+"\x00"+relation.ElementKey] = struct{}{}
	}
	attractionKeys := make([]string, 0, len(attractionRoots))
	for attractionKey := range attractionRoots {
		attractionKeys = append(attractionKeys, attractionKey)
	}
	sort.Strings(attractionKeys)
	for _, attractionKey := range attractionKeys {
		candidateRoot := attractionRoots[attractionKey]
		if candidateRoot != rootKey {
			continue
		}
		boundKeys := make([]string, 0, len(bindings[attractionKey]))
		for boundKey := range bindings[attractionKey] {
			boundKeys = append(boundKeys, boundKey)
		}
		sort.Strings(boundKeys)
		for _, boundKey := range boundKeys {
			if boundKey == rootKey {
				continue
			}
			if _, exists := seenElements[boundKey]; !exists {
				element, available := elements[boundKey]
				if !available {
					continue
				}
				graphElements = append(graphElements, CulturalElement{
					Key:          element.Key,
					Name:         element.Name,
					Introduction: append(json.RawMessage(nil), element.Introduction...),
				})
				seenElements[boundKey] = struct{}{}
			}
			edgeKey := rootKey + "\x00" + boundKey
			if _, exists := seenEdges[edgeKey]; exists {
				continue
			}
			graphRelations = append(graphRelations, CulturalRelation{
				ElementKey:        rootKey,
				RelatedElementKey: boundKey,
				Kind:              "解释",
				Explanation:       "该文化元素通过“" + attractionNames[attractionKey] + "”的现场介绍直接关联到当前景点。",
			})
			seenEdges[edgeKey] = struct{}{}
			seenEdges[boundKey+"\x00"+rootKey] = struct{}{}
		}
	}
	return graphElements, graphRelations
}

func sortedGraphKeys(depths map[string]int) []string {
	keys := make([]string, 0, len(depths))
	for key := range depths {
		keys = append(keys, key)
	}
	sort.Slice(keys, func(i, j int) bool {
		if depths[keys[i]] != depths[keys[j]] {
			return depths[keys[i]] < depths[keys[j]]
		}
		return keys[i] < keys[j]
	})
	return keys
}
