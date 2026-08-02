package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/goudaijun/culturelens-backend/internal/knowledgebase"
)

const (
	defaultBundlePath = "knowledge/bundles/silk-road.v1.json"
	defaultSeedPath   = "knowledge/seeds/wikipedia.zh.v1.json"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "knowledge:", err)
		os.Exit(1)
	}
}

func run(arguments []string) error {
	if len(arguments) == 0 {
		return errors.New("expected sync, validate, or query")
	}
	switch arguments[0] {
	case "sync":
		return runSync(arguments[1:])
	case "validate":
		return runValidate(arguments[1:])
	case "query":
		return runQuery(arguments[1:])
	default:
		return fmt.Errorf("unknown command %q", arguments[0])
	}
}

func runSync(arguments []string) error {
	flags := flag.NewFlagSet("sync", flag.ContinueOnError)
	baseURL := flags.String(
		"srom-base-url",
		"https://srom.123bingo.cn",
		"SROM public site base URL",
	)
	seedPath := flags.String("wikipedia-seed", defaultSeedPath, "Wikipedia seed JSON")
	outputPath := flags.String("output", defaultBundlePath, "knowledge bundle output")
	version := flags.String("version", "silk-road-knowledge-v1", "bundle version")
	pageSize := flags.Int("page-size", 500, "SROM page size")
	timeout := flags.Duration("timeout", 2*time.Minute, "complete sync timeout")
	userAgent := flags.String(
		"user-agent",
		"CultureLensKnowledgeBuilder/0.1 (+https://culturelens-api.goudaijun.top)",
		"HTTP User-Agent",
	)
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return errors.New("sync does not accept positional arguments")
	}

	seed, err := knowledgebase.LoadWikipediaSeed(*seedPath)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()
	client := knowledgebase.SROMClient{
		BaseURL: *baseURL,
		HTTP: &http.Client{
			Timeout: min(*timeout, 90*time.Second),
		},
		UserAgent: *userAgent,
		PageSize:  *pageSize,
	}
	collections, err := client.FetchCollections(ctx)
	if err != nil {
		return err
	}
	bundle, err := knowledgebase.BuildBundle(
		*version,
		time.Now().UTC().Truncate(time.Second),
		collections,
		seed,
	)
	if err != nil {
		return err
	}
	if err := knowledgebase.WriteAtomic(*outputPath, bundle); err != nil {
		return err
	}
	fmt.Printf(
		"wrote %s: %d records (%d SROM, %d Wikipedia), %d relations\n",
		*outputPath,
		bundle.Statistics.TotalRecords,
		bundle.Statistics.BySource["srom"],
		bundle.Statistics.BySource["wikipedia"],
		bundle.Statistics.TotalRelations,
	)
	return nil
}

func runValidate(arguments []string) error {
	flags := flag.NewFlagSet("validate", flag.ContinueOnError)
	path := flags.String("file", defaultBundlePath, "knowledge bundle JSON")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return errors.New("validate does not accept positional arguments")
	}
	bundle, err := knowledgebase.Load(*path)
	if err != nil {
		return err
	}
	fmt.Printf(
		"valid %s: %d records, %d relations\n",
		*path,
		bundle.Statistics.TotalRecords,
		bundle.Statistics.TotalRelations,
	)
	return nil
}

func runQuery(arguments []string) error {
	flags := flag.NewFlagSet("query", flag.ContinueOnError)
	path := flags.String("file", defaultBundlePath, "knowledge bundle JSON")
	query := flags.String("q", "", "query text")
	limit := flags.Int("limit", 10, "maximum results")
	asJSON := flags.Bool("json", false, "print JSON results")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return errors.New("query does not accept positional arguments")
	}
	if strings.TrimSpace(*query) == "" {
		return errors.New("query requires -q")
	}
	bundle, err := knowledgebase.Load(*path)
	if err != nil {
		return err
	}
	results := knowledgebase.Search(bundle, *query, *limit)
	if *asJSON {
		encoder := json.NewEncoder(os.Stdout)
		encoder.SetIndent("", "  ")
		return encoder.Encode(results)
	}
	for _, result := range results {
		sourceURL := ""
		if len(result.Record.Citations) > 0 {
			sourceURL = result.Record.Citations[0].URL
		}
		fmt.Printf(
			"%3d  %s  [%s/%s]\n     %s\n     %s\n",
			result.Score,
			result.Record.CanonicalName,
			result.Record.Kind,
			result.Record.ReviewStatus,
			result.Record.Summary,
			sourceURL,
		)
	}
	return nil
}
