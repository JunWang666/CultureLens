package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/goudaijun/culturelens-backend/internal/api"
	"github.com/goudaijun/culturelens-backend/internal/config"
	"github.com/goudaijun/culturelens-backend/internal/contentadmin"
	"github.com/goudaijun/culturelens-backend/internal/knowledge"
	"github.com/goudaijun/culturelens-backend/internal/providers/googleai"
	"github.com/goudaijun/culturelens-backend/internal/recognition"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		slog.Error("invalid configuration", "error", err)
		os.Exit(1)
	}
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
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
		logger.Error("connect knowledge repository", "error", err)
		os.Exit(1)
	}
	defer repository.Close()
	var adminRepository contentadmin.Repository
	var postgresAdminRepository *contentadmin.PostgresRepository
	if cfg.AdminDatabaseURL != "" {
		adminContext, cancelAdmin := context.WithTimeout(
			context.Background(),
			5*time.Second,
		)
		postgresAdminRepository, err = contentadmin.NewPostgresRepository(
			adminContext,
			cfg.AdminDatabaseURL,
		)
		cancelAdmin()
		if err != nil {
			logger.Error("connect content admin repository", "error", err)
			os.Exit(1)
		}
		defer postgresAdminRepository.Close()
		adminRepository = postgresAdminRepository
	}
	contentStats := repository.Stats()
	var provider recognition.Provider
	if cfg.Mock {
		provider = recognition.MockProvider{}
	} else {
		p, err := googleai.New(
			cfg.GoogleAIStudioBaseURL,
			cfg.GoogleAIStudioAPIKeys,
			cfg.VisionModel,
			cfg.PromptPath,
			cfg.SchemaPath,
		)
		if err != nil {
			logger.Error("configure provider", "error", err)
			os.Exit(1)
		}
		provider = p
	}
	pipeline := recognition.NewPipeline(
		provider,
		repository,
		cfg.VisionModel,
		cfg.PromptVersion,
		cfg.SchemaVersion,
	)
	server := &http.Server{Addr: ":" + cfg.Port, Handler: api.NewWithAdminAndAudit(pipeline, repository, adminRepository, repository, postgresAdminRepository, logger), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 60 * time.Second, WriteTimeout: 65 * time.Second, IdleTimeout: 90 * time.Second}
	logger.Info(
		"culturelens backend started",
		"port",
		cfg.Port,
		"mock",
		cfg.Mock,
		"repository",
		"postgresql",
		"cultural_elements",
		contentStats.CulturalElementCount,
		"attraction_introductions",
		contentStats.IntroductionCount,
		"content_admin",
		adminRepository != nil,
	)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		logger.Error("server stopped", "error", err)
		os.Exit(1)
	}
}
