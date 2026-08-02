# CultureLens recognition evaluation datasets

Only place images here when CultureLens has explicit permission to use them for model
evaluation. Do not copy user scans or arbitrary web images into this directory.

Each non-empty JSONL line has this shape:

```json
{
  "id": "case-001",
  "image_path": "images/case-001.jpg",
  "focus": {"x": 0.18, "y": 0.22, "width": 0.44, "height": 0.51},
  "expected_names": ["斗拱"],
  "known": true,
  "tags": ["建筑构件", "复杂背景"],
  "context_note": "古建筑屋檐",
  "location": {
    "latitude": 31.23,
    "longitude": 121.47,
    "accuracy_meters": 1000,
    "city_name": "上海市",
    "region_name": "中国大陆",
    "region_code": "CN",
    "display_name": "上海市，中国大陆"
  }
}
```

`image_path` is relative to the JSONL file. For unknown cases, set `known` to `false`
and use an empty `expected_names` array. Location is optional, must be coarse, and
must not contain a street, venue, POI, or exact exhibit location.

Run all three image strategies against the same dataset:

```bash
go run ./cmd/eval -dataset evals/datasets/culture-v1.jsonl -dataset-version culture-v1 -strategy whole -output evals/reports/whole.json
go run ./cmd/eval -dataset evals/datasets/culture-v1.jsonl -dataset-version culture-v1 -strategy crop -output evals/reports/crop.json
go run ./cmd/eval -dataset evals/datasets/culture-v1.jsonl -dataset-version culture-v1 -strategy context-focus -output evals/reports/context-focus.json
```

For a paired location comparison, keep every other argument unchanged:

```bash
go run ./cmd/eval -dataset evals/datasets/culture-v1.jsonl -dataset-version culture-v1 -strategy context-focus -location-context dataset -output evals/reports/with-location.json
go run ./cmd/eval -dataset evals/datasets/culture-v1.jsonl -dataset-version culture-v1 -strategy context-focus -location-context off -output evals/reports/without-location.json
```

Do not claim a winning strategy from the Mock provider or fewer than 30 authorized,
representative images.
