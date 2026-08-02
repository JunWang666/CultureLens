package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/goudaijun/culturelens-backend/internal/contentadmin"
)

// packManifest describes an exported knowledge pack for on-device consumers.
type packManifest struct {
	PackVersion  string `json:"packVersion"`
	GeneratedAt  string `json:"generatedAt"`
	RecordCounts struct {
		Elements      int `json:"elements"`
		Attractions   int `json:"attractions"`
		Relations     int `json:"relations"`
		Introductions int `json:"introductions"`
	} `json:"recordCounts"`
	SHA256 string `json:"sha256"`
}

func main() {
	if len(os.Args) < 2 || os.Args[1] != "export" {
		fmt.Fprintln(os.Stderr, "usage: culturelens-exportknowledge export -out <dir> -version <bundle-version>")
		os.Exit(2)
	}
	flags := flag.NewFlagSet("export", flag.ExitOnError)
	outDir := flags.String("out", "", "output directory for knowledge-pack.json and pack-manifest.json")
	version := flags.String("version", "", "bundle version recorded in knowledge-pack.json and the manifest")
	_ = flags.Parse(os.Args[2:])
	if strings.TrimSpace(*outDir) == "" {
		fmt.Fprintln(os.Stderr, "-out is required")
		os.Exit(2)
	}
	if strings.TrimSpace(*version) == "" {
		fmt.Fprintln(os.Stderr, "-version is required")
		os.Exit(2)
	}
	databaseURL := strings.TrimSpace(os.Getenv("CULTURELENS_ADMIN_DATABASE_URL"))
	if databaseURL == "" {
		fmt.Fprintln(os.Stderr, "CULTURELENS_ADMIN_DATABASE_URL is required")
		os.Exit(1)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	repository, err := contentadmin.NewPostgresRepository(ctx, databaseURL)
	if err != nil {
		fmt.Fprintln(os.Stderr, "connect content repository:", err)
		os.Exit(1)
	}
	defer repository.Close()
	snapshot, err := repository.Snapshot(ctx)
	if err != nil {
		fmt.Fprintln(os.Stderr, "read content snapshot:", err)
		os.Exit(1)
	}
	bundle := contentadmin.Bundle{
		Version:       strings.TrimSpace(*version),
		Elements:      snapshot.Elements,
		Attractions:   snapshot.Attractions,
		Relations:     snapshot.Relations,
		Introductions: snapshot.Introductions,
	}
	packData, err := json.MarshalIndent(bundle, "", "  ")
	if err != nil {
		fmt.Fprintln(os.Stderr, "encode knowledge pack:", err)
		os.Exit(1)
	}
	if err := os.MkdirAll(*outDir, 0o755); err != nil {
		fmt.Fprintln(os.Stderr, "create output directory:", err)
		os.Exit(1)
	}
	packPath := filepath.Join(*outDir, "knowledge-pack.json")
	if err := os.WriteFile(packPath, packData, 0o644); err != nil {
		fmt.Fprintln(os.Stderr, "write knowledge pack:", err)
		os.Exit(1)
	}
	sum := sha256.Sum256(packData)
	manifest := packManifest{
		PackVersion: bundle.Version,
		GeneratedAt: time.Now().UTC().Format(time.RFC3339),
		SHA256:      hex.EncodeToString(sum[:]),
	}
	manifest.RecordCounts.Elements = len(bundle.Elements)
	manifest.RecordCounts.Attractions = len(bundle.Attractions)
	manifest.RecordCounts.Relations = len(bundle.Relations)
	manifest.RecordCounts.Introductions = len(bundle.Introductions)
	manifestData, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		fmt.Fprintln(os.Stderr, "encode pack manifest:", err)
		os.Exit(1)
	}
	manifestPath := filepath.Join(*outDir, "pack-manifest.json")
	if err := os.WriteFile(manifestPath, manifestData, 0o644); err != nil {
		fmt.Fprintln(os.Stderr, "write pack manifest:", err)
		os.Exit(1)
	}
	fmt.Printf(
		"version=%s elements=%d attractions=%d relations=%d introductions=%d sha256=%s\n",
		manifest.PackVersion,
		manifest.RecordCounts.Elements,
		manifest.RecordCounts.Attractions,
		manifest.RecordCounts.Relations,
		manifest.RecordCounts.Introductions,
		manifest.SHA256,
	)
}
