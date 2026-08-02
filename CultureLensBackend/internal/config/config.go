package config

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Port                  string
	Mock                  bool
	DatabaseURL           string
	AdminDatabaseURL      string
	GoogleAIStudioBaseURL string
	GoogleAIStudioAPIKeys []string
	VisionModel           string
	PromptVersion         string
	SchemaVersion         string
	PromptPath            string
	SchemaPath            string
}

func Load() (Config, error) {
	if err := loadDotEnv(".env"); err != nil && !os.IsNotExist(err) {
		return Config{}, fmt.Errorf("read .env: %w", err)
	}
	mock, err := strconv.ParseBool(defaultValue("MOCK_RECOGNITION", "false"))
	if err != nil {
		return Config{}, fmt.Errorf("MOCK_RECOGNITION must be a boolean")
	}
	c := Config{
		Port:                  defaultValue("PORT", "8080"),
		Mock:                  mock,
		DatabaseURL:           strings.TrimSpace(os.Getenv("DATABASE_URL")),
		AdminDatabaseURL:      strings.TrimSpace(os.Getenv("CULTURELENS_ADMIN_DATABASE_URL")),
		GoogleAIStudioBaseURL: defaultValue("GOOGLE_AI_STUDIO_BASE_URL", "https://generativelanguage.googleapis.com/v1beta"),
		GoogleAIStudioAPIKeys: parseCSV(defaultValue("GOOGLE_AI_STUDIO_API_KEYS", os.Getenv("GOOGLE_AI_STUDIO_API_KEY"))),
		VisionModel:           defaultValue("CULTURELENS_VISION_MODEL", "gemini-3.6-flash"),
		PromptVersion:         defaultValue("CULTURELENS_PROMPT_VERSION", "recognition-v5"),
		SchemaVersion:         defaultValue("CULTURELENS_SCHEMA_VERSION", "provider-recognition-v5"),
		PromptPath:            defaultValue("CULTURELENS_PROMPT_PATH", "prompts/recognition/v5.txt"),
		SchemaPath:            defaultValue("CULTURELENS_SCHEMA_PATH", "prompts/recognition/v5.schema.json"),
	}
	if c.DatabaseURL == "" {
		return Config{}, fmt.Errorf("DATABASE_URL is required")
	}
	if !c.Mock && len(c.GoogleAIStudioAPIKeys) == 0 {
		return Config{}, fmt.Errorf("GOOGLE_AI_STUDIO_API_KEYS is required when MOCK_RECOGNITION is false")
	}
	return c, nil
}

func parseCSV(value string) []string {
	parts := strings.Split(value, ",")
	keys := make([]string, 0, len(parts))
	for _, part := range parts {
		if key := strings.TrimSpace(part); key != "" {
			keys = append(keys, key)
		}
	}
	return keys
}

func loadDotEnv(path string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok || strings.TrimSpace(key) == "" {
			return fmt.Errorf("invalid environment line")
		}
		if _, present := os.LookupEnv(strings.TrimSpace(key)); !present {
			_ = os.Setenv(strings.TrimSpace(key), strings.Trim(strings.TrimSpace(value), `"`))
		}
	}
	return scanner.Err()
}
func defaultValue(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}
