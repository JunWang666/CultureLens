package main

import (
	"testing"

	"github.com/goudaijun/culturelens-backend/internal/recognition"
)

func TestNameMatchesAliases(t *testing.T) {
	if !nameMatches("清代·斗拱", []string{"清代斗拱", "斗拱"}) {
		t.Fatal("expected punctuation-normalized alias match")
	}
}

func TestSummarizeMetrics(t *testing.T) {
	results := []caseResult{
		{ID: "known-1", Known: true, Expected: []string{"斗拱"}, Predicted: "斗拱", Top1Hit: true, Top3Hit: true, LatencyMS: 100, LocationEffect: "reordered"},
		{ID: "known-2", Known: true, Expected: []string{"雀替"}, Predicted: "其他", Rejected: true, LatencyMS: 200},
		{ID: "unknown-1", Known: false, Predicted: "其他", Rejected: true, LatencyMS: 300},
		{ID: "broken", Error: "upstream error"},
	}
	report := summarize(
		"dataset.jsonl",
		"v1",
		"model",
		"prompt",
		"schema",
		strategyWhole,
		locationContextOff,
		results,
	)
	if report.StructuredSuccessRate != 0.75 ||
		report.Top1Accuracy != 0.5 ||
		report.Top3Recall != 0.5 ||
		report.UnknownRejectionRate != 1 ||
		report.KnownFalseRejectionRate != 0.5 ||
		report.P50LatencyMS != 200 ||
		report.P95LatencyMS != 300 ||
		report.LocationReorderedCount != 1 {
		t.Fatalf("unexpected report: %+v", report)
	}
}

func TestLocationContextModeCreatesPairedControl(t *testing.T) {
	location := &recognition.Location{Latitude: 31.23, Longitude: 121.47}
	if locationForMode(locationContextDataset, location) != location {
		t.Fatal("dataset mode must preserve the case location")
	}
	if locationForMode(locationContextOff, location) != nil {
		t.Fatal("off mode must remove the case location")
	}
}
