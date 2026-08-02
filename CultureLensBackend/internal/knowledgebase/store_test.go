package knowledgebase

import (
	"path/filepath"
	"testing"
	"time"
)

func TestWriteLoadAndSearchBundle(t *testing.T) {
	bundle, err := BuildBundle(
		"test-v1",
		time.Date(2026, 7, 30, 7, 0, 0, 0, time.UTC),
		[]SROMCollection{{
			CollectionID:   10,
			CollectionName: "南宋瓷碗",
			MaterialName:   "瓷",
			YearsName:      "南宋",
			RepositoryName: "测试博物馆",
		}},
		testWikipediaSeed(),
	)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "bundle.json")
	if err := WriteAtomic(path, bundle); err != nil {
		t.Fatal(err)
	}
	loaded, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	results := Search(loaded, "丝绸", 10)
	if len(results) < 2 ||
		results[0].Record.CanonicalName != "丝绸" ||
		results[0].Score != 100 {
		t.Fatalf("unexpected search results: %+v", results)
	}
}

func TestValidateRejectsMissingRelationEndpoint(t *testing.T) {
	bundle, err := BuildBundle(
		"test-v1",
		time.Date(2026, 7, 30, 7, 0, 0, 0, time.UTC),
		[]SROMCollection{{CollectionID: 10, CollectionName: "藏品"}},
		testWikipediaSeed(),
	)
	if err != nil {
		t.Fatal(err)
	}
	bundle.Relations[0].TargetID = "4D64B72C-0B1D-4B15-AE9C-833A1DCAAB57"
	if err := Validate(bundle); err == nil {
		t.Fatal("expected missing relation endpoint to fail")
	}
}
