package knowledge

import (
	"encoding/json"
	"testing"

	"github.com/goudaijun/culturelens-backend/internal/database/dbgen"
)

func TestRecognitionGraphReturnsBoundedMultiHopPath(t *testing.T) {
	text := json.RawMessage(`{"schemaVersion":1,"blocks":[{"type":"paragraph","text":"正文"}]}`)
	elements := map[string]RecognitionElement{}
	for _, key := range []string{"three-pools", "stone-pagodas", "su-shi", "su-causeway", "outside"} {
		elements[key] = RecognitionElement{Key: key, Name: key, Introduction: text}
	}
	relations := []dbgen.ListCulturalElementRelationsRow{
		{ElementKey: "three-pools", RelatedElementKey: "stone-pagodas"},
		{ElementKey: "stone-pagodas", RelatedElementKey: "su-shi"},
		{ElementKey: "su-shi", RelatedElementKey: "su-causeway"},
		{ElementKey: "su-causeway", RelatedElementKey: "outside"},
	}
	concepts, edges := recognitionGraph("three-pools", elements, relations, 3, 32)
	if len(concepts) != 3 || len(edges) != 3 {
		t.Fatalf("unexpected bounded graph: concepts=%+v edges=%+v", concepts, edges)
	}
	if concepts[0].Key != "stone-pagodas" || concepts[1].Key != "su-shi" ||
		concepts[2].Key != "su-causeway" {
		t.Fatalf("graph is not breadth-first ordered: %+v", concepts)
	}
}
