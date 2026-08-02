package knowledgebase

import (
	"slices"
	"strings"
)

type SearchResult struct {
	Record Record `json:"record"`
	Score  int    `json:"score"`
}

func Search(bundle Bundle, query string, limit int) []SearchResult {
	query = normalizeKey(query)
	if query == "" {
		return nil
	}
	if limit <= 0 {
		limit = 20
	}
	results := make([]SearchResult, 0)
	for _, record := range bundle.Records {
		score := searchScore(record, query)
		if score == 0 {
			continue
		}
		results = append(results, SearchResult{Record: record, Score: score})
	}
	slices.SortFunc(results, func(left, right SearchResult) int {
		if left.Score != right.Score {
			return right.Score - left.Score
		}
		return compareRecords(left.Record, right.Record)
	})
	return results[:min(limit, len(results))]
}

func searchScore(record Record, query string) int {
	name := normalizeKey(record.CanonicalName)
	switch {
	case name == query:
		return 100
	case strings.Contains(name, query):
		return 80
	}
	for _, alias := range record.Aliases {
		normalized := normalizeKey(alias)
		switch {
		case normalized == query:
			return 95
		case strings.Contains(normalized, query):
			return 75
		}
	}
	if strings.Contains(normalizeKey(record.Summary), query) {
		return 40
	}
	for _, attribute := range record.Attributes {
		if strings.Contains(normalizeKey(attribute.Value), query) {
			return 20
		}
	}
	return 0
}
