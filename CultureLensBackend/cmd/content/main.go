package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/goudaijun/culturelens-backend/internal/contentadmin"
)

func main() {
	if len(os.Args) < 2 || os.Args[1] != "import" {
		fmt.Fprintln(os.Stderr, "usage: culturelens-content import [-file path]")
		os.Exit(2)
	}
	flags := flag.NewFlagSet("import", flag.ExitOnError)
	filePath := flags.String(
		"file",
		"content/hangzhou-west-lake.v1.json",
		"content bundle path",
	)
	_ = flags.Parse(os.Args[2:])
	databaseURL := strings.TrimSpace(os.Getenv("CULTURELENS_ADMIN_DATABASE_URL"))
	if databaseURL == "" {
		fmt.Fprintln(os.Stderr, "CULTURELENS_ADMIN_DATABASE_URL is required")
		os.Exit(1)
	}
	data, err := os.ReadFile(*filePath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "read content bundle:", err)
		os.Exit(1)
	}
	var bundle contentadmin.Bundle
	if err := json.Unmarshal(data, &bundle); err != nil {
		fmt.Fprintln(os.Stderr, "decode content bundle:", err)
		os.Exit(1)
	}
	if err := contentadmin.ValidateBundle(bundle); err != nil {
		fmt.Fprintln(os.Stderr, "validate content bundle:", err)
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
	result, err := repository.Import(ctx, bundle)
	if err != nil {
		fmt.Fprintln(os.Stderr, "import content bundle:", err)
		os.Exit(1)
	}
	fmt.Printf(
		"version=%s elements=%d attractions=%d relations=%d introductions=%d\n",
		result.Version,
		result.Elements,
		result.Attractions,
		result.Relations,
		result.Introductions,
	)
}
