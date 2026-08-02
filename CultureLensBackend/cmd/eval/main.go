package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"image"
	"image/draw"
	"image/jpeg"
	_ "image/png"
	"log/slog"
	"math"
	"os"
	"path/filepath"
	"runtime/debug"
	"slices"
	"strings"
	"time"

	"github.com/goudaijun/culturelens-backend/internal/config"
	"github.com/goudaijun/culturelens-backend/internal/knowledge"
	"github.com/goudaijun/culturelens-backend/internal/providers/googleai"
	"github.com/goudaijun/culturelens-backend/internal/recognition"
)

type strategy string
type locationContextMode string

const (
	strategyWhole        strategy = "whole"
	strategyCrop         strategy = "crop"
	strategyContextFocus strategy = "context-focus"

	locationContextDataset locationContextMode = "dataset"
	locationContextOff     locationContextMode = "off"
)

type normalizedRegion struct {
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

type evalCase struct {
	ID            string                `json:"id"`
	ImagePath     string                `json:"image_path"`
	Focus         *normalizedRegion     `json:"focus,omitempty"`
	ExpectedNames []string              `json:"expected_names"`
	Known         bool                  `json:"known"`
	Tags          []string              `json:"tags,omitempty"`
	Location      *recognition.Location `json:"location,omitempty"`
	ContextNote   string                `json:"context_note,omitempty"`
}

type caseResult struct {
	ID                    string   `json:"id"`
	Known                 bool     `json:"known"`
	Expected              []string `json:"expected_names"`
	Predicted             string   `json:"predicted_name,omitempty"`
	Alternatives          []string `json:"alternatives,omitempty"`
	Top1Hit               bool     `json:"top1_hit"`
	Top3Hit               bool     `json:"top3_hit"`
	Rejected              bool     `json:"rejected"`
	LatencyMS             int64    `json:"latency_ms"`
	Error                 string   `json:"error,omitempty"`
	Tags                  []string `json:"tags,omitempty"`
	LocationEffect        string   `json:"location_effect,omitempty"`
	ResolutionStatus      string   `json:"resolution_status,omitempty"`
	CatalogVersion        string   `json:"catalog_version,omitempty"`
	CatalogCandidateCount int      `json:"catalog_candidate_count"`
}

type report struct {
	DatasetVersion           string              `json:"dataset_version"`
	DatasetPath              string              `json:"dataset_path"`
	GitCommit                string              `json:"git_commit"`
	Model                    string              `json:"model"`
	PromptVersion            string              `json:"prompt_version"`
	SchemaVersion            string              `json:"schema_version"`
	Strategy                 strategy            `json:"strategy"`
	LocationContext          locationContextMode `json:"location_context"`
	TotalCases               int                 `json:"total_cases"`
	StructuredSuccessRate    float64             `json:"structured_success_rate"`
	Top1Accuracy             float64             `json:"top1_accuracy"`
	Top3Recall               float64             `json:"top3_recall"`
	UnknownRejectionRate     float64             `json:"unknown_rejection_rate"`
	KnownFalseRejectionRate  float64             `json:"known_false_rejection_rate"`
	P50LatencyMS             int64               `json:"p50_latency_ms"`
	P95LatencyMS             int64               `json:"p95_latency_ms"`
	LocationNoneCount        int                 `json:"location_none_count"`
	LocationReorderedCount   int                 `json:"location_reordered_count"`
	LocationNarrowedCount    int                 `json:"location_narrowed_count"`
	CatalogVersion           string              `json:"catalog_version,omitempty"`
	ResolvedRate             float64             `json:"resolved_rate"`
	AverageCatalogCandidates float64             `json:"average_catalog_candidates"`
	GeneratedAt              time.Time           `json:"generated_at"`
	Cases                    []caseResult        `json:"cases"`
}

func main() {
	var (
		datasetPath  string
		datasetVer   string
		outputPath   string
		model        string
		promptVer    string
		schemaVer    string
		strategyFlag string
		locationFlag string
	)
	flag.StringVar(&datasetPath, "dataset", "", "JSONL evaluation dataset")
	flag.StringVar(&datasetVer, "dataset-version", "unversioned", "stable dataset version")
	flag.StringVar(&outputPath, "output", "", "optional JSON report path")
	flag.StringVar(&model, "model", "", "Gemini model override")
	flag.StringVar(&promptVer, "prompt", "", "prompt version label override")
	flag.StringVar(&schemaVer, "schema", "", "schema version label override")
	flag.StringVar(&strategyFlag, "strategy", string(strategyContextFocus), "whole, crop, or context-focus")
	flag.StringVar(&locationFlag, "location-context", string(locationContextDataset), "dataset or off")
	flag.Parse()

	if datasetPath == "" {
		exitError(errors.New("-dataset is required"))
	}
	selectedStrategy := strategy(strategyFlag)
	if selectedStrategy != strategyWhole &&
		selectedStrategy != strategyCrop &&
		selectedStrategy != strategyContextFocus {
		exitError(fmt.Errorf("unsupported strategy %q", strategyFlag))
	}
	selectedLocationContext := locationContextMode(locationFlag)
	if selectedLocationContext != locationContextDataset &&
		selectedLocationContext != locationContextOff {
		exitError(fmt.Errorf("unsupported location context %q", locationFlag))
	}

	cfg, err := config.Load()
	if err != nil {
		exitError(err)
	}
	if model == "" {
		model = cfg.VisionModel
	}
	if promptVer == "" {
		promptVer = cfg.PromptVersion
	}
	if schemaVer == "" {
		schemaVer = cfg.SchemaVersion
	}

	var provider recognition.Provider
	if cfg.Mock {
		provider = recognition.MockProvider{}
	} else {
		provider, err = googleai.New(
			cfg.GoogleAIStudioBaseURL,
			cfg.GoogleAIStudioAPIKeys,
			model,
			cfg.PromptPath,
			cfg.SchemaPath,
		)
		if err != nil {
			exitError(err)
		}
	}
	databaseContext, cancelDatabase := context.WithTimeout(
		context.Background(),
		5*time.Second,
	)
	repository, err := knowledge.NewPostgresRepository(
		databaseContext,
		cfg.DatabaseURL,
	)
	cancelDatabase()
	if err != nil {
		exitError(err)
	}
	defer repository.Close()
	pipeline := recognition.NewPipeline(
		provider,
		repository,
		model,
		promptVer,
		schemaVer,
	)
	cases, err := loadDataset(datasetPath)
	if err != nil {
		exitError(err)
	}
	result := runEvaluation(
		context.Background(),
		pipeline,
		datasetPath,
		datasetVer,
		model,
		promptVer,
		schemaVer,
		selectedStrategy,
		selectedLocationContext,
		cases,
	)

	data, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		exitError(err)
	}
	data = append(data, '\n')
	if outputPath == "" {
		_, _ = os.Stdout.Write(data)
		return
	}
	if err := os.MkdirAll(filepath.Dir(outputPath), 0o755); err != nil {
		exitError(err)
	}
	if err := os.WriteFile(outputPath, data, 0o600); err != nil {
		exitError(err)
	}
}

func runEvaluation(
	ctx context.Context,
	pipeline recognition.Pipeline,
	datasetPath, datasetVersion, model, prompt, schema string,
	selectedStrategy strategy,
	selectedLocationContext locationContextMode,
	cases []evalCase,
) report {
	results := make([]caseResult, 0, len(cases))
	for _, testCase := range cases {
		results = append(
			results,
			runCase(
				ctx,
				pipeline,
				filepath.Dir(datasetPath),
				selectedStrategy,
				selectedLocationContext,
				testCase,
			),
		)
	}
	return summarize(
		datasetPath,
		datasetVersion,
		model,
		prompt,
		schema,
		selectedStrategy,
		selectedLocationContext,
		results,
	)
}

func runCase(
	ctx context.Context,
	pipeline recognition.Pipeline,
	datasetDirectory string,
	selectedStrategy strategy,
	selectedLocationContext locationContextMode,
	testCase evalCase,
) caseResult {
	result := caseResult{
		ID:       testCase.ID,
		Known:    testCase.Known,
		Expected: testCase.ExpectedNames,
		Tags:     testCase.Tags,
	}
	contextData, contextMIME, focusData, err := prepareMedia(
		filepath.Join(datasetDirectory, testCase.ImagePath),
		testCase.Focus,
		selectedStrategy,
	)
	if err != nil {
		result.Error = err.Error()
		return result
	}

	request := recognition.Request{
		RequestID:   "eval-" + testCase.ID,
		ImageBase64: base64.StdEncoding.EncodeToString(contextData),
		MIMEType:    contextMIME,
		Location:    locationForMode(selectedLocationContext, testCase.Location),
		ContextNote: testCase.ContextNote,
		Locale:      "zh_CN",
	}
	if len(focusData) > 0 {
		request.FocusImageBase64 = base64.StdEncoding.EncodeToString(focusData)
		request.FocusMIMEType = "image/jpeg"
	}

	started := time.Now()
	response, err := pipeline.Recognize(ctx, request)
	result.LatencyMS = time.Since(started).Milliseconds()
	if err != nil {
		result.Error = err.Error()
		return result
	}

	result.Predicted = response.Object.CanonicalName
	result.ResolutionStatus = response.ResolutionStatus
	result.CatalogVersion = response.CatalogVersion
	result.CatalogCandidateCount = response.CatalogCandidateCount
	if response.LocationInfluence != nil {
		result.LocationEffect = response.LocationInfluence.Effect
	}
	result.Rejected = normalizeName(result.Predicted) == normalizeName("其他")
	for _, candidate := range response.Alternatives {
		result.Alternatives = append(result.Alternatives, candidate.CanonicalName)
	}
	result.Top1Hit = nameMatches(result.Predicted, testCase.ExpectedNames)
	result.Top3Hit = result.Top1Hit
	if !result.Top3Hit {
		topAlternatives := result.Alternatives[:min(2, len(result.Alternatives))]
		for _, candidate := range topAlternatives {
			if nameMatches(candidate, testCase.ExpectedNames) {
				result.Top3Hit = true
				break
			}
		}
	}
	return result
}

func locationForMode(
	mode locationContextMode,
	location *recognition.Location,
) *recognition.Location {
	if mode == locationContextOff {
		return nil
	}
	return location
}

func prepareMedia(
	path string,
	focus *normalizedRegion,
	selectedStrategy strategy,
) ([]byte, string, []byte, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, "", nil, err
	}
	mime, err := supportedMIME(data)
	if err != nil {
		return nil, "", nil, err
	}
	if selectedStrategy == strategyWhole {
		return data, mime, nil, nil
	}
	if focus == nil {
		return nil, "", nil, errors.New("strategy requires a focus region")
	}
	cropped, err := cropJPEG(data, *focus)
	if err != nil {
		return nil, "", nil, err
	}
	if selectedStrategy == strategyCrop {
		return cropped, "image/jpeg", nil, nil
	}
	return data, mime, cropped, nil
}

func supportedMIME(data []byte) (string, error) {
	_, format, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return "", err
	}
	switch format {
	case "jpeg":
		return "image/jpeg", nil
	case "png":
		return "image/png", nil
	default:
		return "", fmt.Errorf("unsupported image format %q", format)
	}
}

func cropJPEG(data []byte, focus normalizedRegion) ([]byte, error) {
	if focus.X < 0 ||
		focus.Y < 0 ||
		focus.Width <= 0 ||
		focus.Height <= 0 ||
		focus.X+focus.Width > 1 ||
		focus.Y+focus.Height > 1 {
		return nil, errors.New("focus region must stay inside 0...1")
	}
	source, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	bounds := source.Bounds()
	cropBounds := image.Rect(
		bounds.Min.X+int(math.Floor(focus.X*float64(bounds.Dx()))),
		bounds.Min.Y+int(math.Floor(focus.Y*float64(bounds.Dy()))),
		bounds.Min.X+int(math.Ceil((focus.X+focus.Width)*float64(bounds.Dx()))),
		bounds.Min.Y+int(math.Ceil((focus.Y+focus.Height)*float64(bounds.Dy()))),
	).Intersect(bounds)
	if cropBounds.Dx() < 2 || cropBounds.Dy() < 2 {
		return nil, errors.New("focus region is too small")
	}
	cropped := image.NewRGBA(image.Rect(0, 0, cropBounds.Dx(), cropBounds.Dy()))
	draw.Draw(cropped, cropped.Bounds(), source, cropBounds.Min, draw.Src)
	var output bytes.Buffer
	if err := jpeg.Encode(&output, cropped, &jpeg.Options{Quality: 88}); err != nil {
		return nil, err
	}
	return output.Bytes(), nil
}

func loadDataset(path string) ([]evalCase, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var cases []evalCase
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 64*1024), 2<<20)
	lineNumber := 0
	for scanner.Scan() {
		lineNumber++
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		var testCase evalCase
		if err := json.Unmarshal([]byte(line), &testCase); err != nil {
			return nil, fmt.Errorf("line %d: %w", lineNumber, err)
		}
		if testCase.ID == "" ||
			testCase.ImagePath == "" ||
			(testCase.Known && len(testCase.ExpectedNames) == 0) {
			return nil, fmt.Errorf("line %d: id, image_path, and expected_names for known cases are required", lineNumber)
		}
		cases = append(cases, testCase)
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	if len(cases) == 0 {
		return nil, errors.New("dataset contains no cases")
	}
	return cases, nil
}

func summarize(
	datasetPath, datasetVersion, model, prompt, schema string,
	selectedStrategy strategy,
	selectedLocationContext locationContextMode,
	results []caseResult,
) report {
	var successful, known, top1, top3, unknown, unknownRejected, knownRejected int
	var locationNone, locationReordered, locationNarrowed int
	var resolved, catalogCandidateTotal int
	var catalogVersion string
	var latencies []int64
	for index, result := range results {
		if result.Error != "" {
			continue
		}
		successful++
		catalogCandidateTotal += result.CatalogCandidateCount
		if result.ResolutionStatus == "resolved" {
			resolved++
		}
		if catalogVersion == "" {
			catalogVersion = result.CatalogVersion
		}
		switch result.LocationEffect {
		case "none":
			locationNone++
		case "reordered":
			locationReordered++
		case "narrowed":
			locationNarrowed++
		}
		latencies = append(latencies, result.LatencyMS)
		if !result.Known {
			unknown++
			if result.Rejected {
				unknownRejected++
			}
			continue
		}
		known++
		if result.Top1Hit {
			top1++
		}
		if result.Top3Hit {
			top3++
		}
		if result.Rejected {
			knownRejected++
		}
		results[index] = result
	}
	slices.Sort(latencies)
	return report{
		DatasetVersion:           datasetVersion,
		DatasetPath:              datasetPath,
		GitCommit:                gitCommit(),
		Model:                    model,
		PromptVersion:            prompt,
		SchemaVersion:            schema,
		Strategy:                 selectedStrategy,
		LocationContext:          selectedLocationContext,
		TotalCases:               len(results),
		StructuredSuccessRate:    ratio(successful, len(results)),
		Top1Accuracy:             ratio(top1, known),
		Top3Recall:               ratio(top3, known),
		UnknownRejectionRate:     ratio(unknownRejected, unknown),
		KnownFalseRejectionRate:  ratio(knownRejected, known),
		P50LatencyMS:             percentile(latencies, 0.50),
		P95LatencyMS:             percentile(latencies, 0.95),
		LocationNoneCount:        locationNone,
		LocationReorderedCount:   locationReordered,
		LocationNarrowedCount:    locationNarrowed,
		CatalogVersion:           catalogVersion,
		ResolvedRate:             ratio(resolved, successful),
		AverageCatalogCandidates: ratio(catalogCandidateTotal, successful),
		GeneratedAt:              time.Now().UTC(),
		Cases:                    results,
	}
}

func nameMatches(predicted string, expected []string) bool {
	predicted = normalizeName(predicted)
	for _, name := range expected {
		if predicted == normalizeName(name) {
			return true
		}
	}
	return false
}

func normalizeName(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	replacer := strings.NewReplacer(" ", "", "·", "", "・", "", "-", "")
	return replacer.Replace(value)
}

func ratio(numerator, denominator int) float64 {
	if denominator == 0 {
		return 0
	}
	return float64(numerator) / float64(denominator)
}

func percentile(values []int64, fraction float64) int64 {
	if len(values) == 0 {
		return 0
	}
	index := int(math.Ceil(fraction*float64(len(values)))) - 1
	return values[max(0, min(index, len(values)-1))]
}

func gitCommit() string {
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return "unknown"
	}
	for _, setting := range info.Settings {
		if setting.Key == "vcs.revision" {
			return setting.Value
		}
	}
	return "unknown"
}

func exitError(err error) {
	slog.Error("evaluation failed", "error", err)
	os.Exit(1)
}
