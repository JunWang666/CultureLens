package contentadmin

import (
	"encoding/json"
	"os"
	"testing"
)

func TestWestLakeBundle(t *testing.T) {
	data, err := os.ReadFile("../../content/hangzhou-west-lake.v1.json")
	if err != nil {
		t.Fatal(err)
	}
	var bundle Bundle
	if err := json.Unmarshal(data, &bundle); err != nil {
		t.Fatal(err)
	}
	if err := ValidateBundle(bundle); err != nil {
		t.Fatal(err)
	}
	if bundle.Version != "hangzhou-west-lake-v2" ||
		len(bundle.Elements) != 34 ||
		len(bundle.Attractions) != 7 ||
		len(bundle.Relations) != 44 ||
		len(bundle.Introductions) != 19 {
		t.Fatalf("unexpected bundle counts: %+v", bundle)
	}
	foundThreePoolsPath := false
	for _, relation := range bundle.Relations {
		if relation.ElementKey == "three-pools-mirroring-moon" &&
			relation.RelatedElementKey == "three-pools-stone-pagodas" {
			foundThreePoolsPath = true
		}
	}
	if !foundThreePoolsPath {
		t.Fatal("three-pools cultural path is missing")
	}
	for _, introduction := range bundle.Introductions {
		if introduction.CoordinateSourceURL == "" {
			t.Fatalf("missing coordinate source for %s", introduction.Key)
		}
	}
}

func TestValidateBundleRejectsMissingReference(t *testing.T) {
	bundle := Bundle{
		Version: "test-v1",
		Elements: []CulturalElement{{
			Key:          "element",
			Name:         "元素",
			Introduction: json.RawMessage(`{"schemaVersion":1,"blocks":[{"type":"paragraph","text":"正文"}]}`),
		}},
		Attractions: []Attraction{{Key: "attraction", Name: "景点"}},
		Introductions: []AttractionIntroduction{{
			Key:                "introduction",
			Name:               "介绍",
			Introduction:       json.RawMessage(`{"schemaVersion":1,"blocks":[{"type":"paragraph","text":"正文"}]}`),
			CulturalElementKey: "missing",
			AttractionKey:      "attraction",
			Latitude:           30,
			Longitude:          120,
		}},
	}
	if err := ValidateBundle(bundle); err == nil {
		t.Fatal("expected missing element reference to be rejected")
	}
}

func TestValidateRichTextAllowsImageBlocks(t *testing.T) {
	document := json.RawMessage(`{
		"schemaVersion": 1,
		"blocks": [
			{"type": "paragraph", "text": "正文"},
			{"type": "image", "url": "https://pub-example.r2.dev/culture/dougong.jpg", "caption": "斗拱"},
			{"type": "image", "url": "http://images.example.com/lienhuawen.png"}
		]
	}`)
	if err := validateRichText(document); err != nil {
		t.Fatalf("expected image blocks to pass: %v", err)
	}
}

func TestValidateRichTextRejectsInvalidImageBlocks(t *testing.T) {
	cases := map[string]string{
		"missing url":  `{"schemaVersion":1,"blocks":[{"type":"image"}]}`,
		"empty url":    `{"schemaVersion":1,"blocks":[{"type":"image","url":"  "}]}`,
		"ftp scheme":   `{"schemaVersion":1,"blocks":[{"type":"image","url":"ftp://example.com/a.jpg"}]}`,
		"relative url": `{"schemaVersion":1,"blocks":[{"type":"image","url":"/images/a.jpg"}]}`,
	}
	for name, document := range cases {
		if err := validateRichText(json.RawMessage(document)); err == nil {
			t.Fatalf("%s: expected rejection", name)
		}
	}
}
