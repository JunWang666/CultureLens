package contentadmin

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/goudaijun/culturelens-backend/internal/database/dbgen"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresRepository struct {
	pool    *pgxpool.Pool
	queries *dbgen.Queries
}

func NewPostgresRepository(
	ctx context.Context,
	databaseURL string,
) (*PostgresRepository, error) {
	databaseURL = strings.TrimSpace(databaseURL)
	if databaseURL == "" {
		return nil, errors.New("admin database URL is required")
	}
	poolConfig, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse admin database URL: %w", err)
	}
	poolConfig.MaxConns = 2
	poolConfig.MinConns = 0
	poolConfig.MaxConnLifetime = 30 * time.Minute
	poolConfig.MaxConnIdleTime = 5 * time.Minute
	poolConfig.HealthCheckPeriod = time.Minute
	poolConfig.ConnConfig.RuntimeParams["application_name"] = "culturelens-admin"
	poolConfig.ConnConfig.RuntimeParams["timezone"] = "UTC"
	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		return nil, fmt.Errorf("open admin PostgreSQL pool: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping admin PostgreSQL: %w", err)
	}
	return &PostgresRepository{pool: pool, queries: dbgen.New(pool)}, nil
}

func (r *PostgresRepository) Close() {
	if r != nil && r.pool != nil {
		r.pool.Close()
	}
}

func (r *PostgresRepository) Snapshot(ctx context.Context) (Snapshot, error) {
	elements, err := r.queries.ListCulturalElements(ctx)
	if err != nil {
		return Snapshot{}, fmt.Errorf("list cultural elements: %w", err)
	}
	attractions, err := r.queries.ListAttractions(ctx)
	if err != nil {
		return Snapshot{}, fmt.Errorf("list attractions: %w", err)
	}
	relations, err := r.queries.ListCulturalElementRelations(ctx)
	if err != nil {
		return Snapshot{}, fmt.Errorf("list cultural element relations: %w", err)
	}
	introductions, err := r.queries.ListAllAttractionCulturalIntroductions(ctx)
	if err != nil {
		return Snapshot{}, fmt.Errorf("list attraction introductions: %w", err)
	}
	snapshot := Snapshot{
		Elements:      make([]CulturalElement, 0, len(elements)),
		Attractions:   make([]Attraction, 0, len(attractions)),
		Relations:     make([]Relation, 0, len(relations)),
		Introductions: make([]AttractionIntroduction, 0, len(introductions)),
	}
	for _, element := range elements {
		snapshot.Elements = append(snapshot.Elements, CulturalElement{
			Key:          element.Key,
			Name:         element.Name,
			Introduction: cloneJSON(element.Introduction),
		})
	}
	for _, attraction := range attractions {
		snapshot.Attractions = append(snapshot.Attractions, Attraction{
			Key:  attraction.Key,
			Name: attraction.Name,
		})
	}
	for _, relation := range relations {
		snapshot.Relations = append(snapshot.Relations, Relation{
			ElementKey:        relation.ElementKey,
			RelatedElementKey: relation.RelatedElementKey,
		})
	}
	for _, introduction := range introductions {
		snapshot.Introductions = append(
			snapshot.Introductions,
			mapIntroductionRow(introduction),
		)
	}
	return snapshot, nil
}

func (r *PostgresRepository) UpsertElement(
	ctx context.Context,
	element CulturalElement,
) (CulturalElement, error) {
	row, err := r.queries.UpsertCulturalElement(
		ctx,
		dbgen.UpsertCulturalElementParams{
			ElementKey:   element.Key,
			Name:         element.Name,
			Introduction: element.Introduction,
		},
	)
	if err != nil {
		return CulturalElement{}, fmt.Errorf("upsert cultural element: %w", err)
	}
	return CulturalElement{
		Key:          row.Key,
		Name:         row.Name,
		Introduction: cloneJSON(row.Introduction),
	}, nil
}

func (r *PostgresRepository) UpsertAttraction(
	ctx context.Context,
	attraction Attraction,
) (Attraction, error) {
	row, err := r.queries.UpsertAttraction(
		ctx,
		dbgen.UpsertAttractionParams{
			AttractionKey: attraction.Key,
			Name:          attraction.Name,
		},
	)
	if err != nil {
		return Attraction{}, fmt.Errorf("upsert attraction: %w", err)
	}
	return Attraction{Key: row.Key, Name: row.Name}, nil
}

func (r *PostgresRepository) UpsertIntroduction(
	ctx context.Context,
	introduction AttractionIntroduction,
) (AttractionIntroduction, error) {
	row, err := r.queries.UpsertAttractionCulturalIntroduction(
		ctx,
		dbgen.UpsertAttractionCulturalIntroductionParams{
			IntroductionKey:    introduction.Key,
			Name:               introduction.Name,
			Introduction:       introduction.Introduction,
			CulturalElementKey: introduction.CulturalElementKey,
			AttractionKey:      introduction.AttractionKey,
			Latitude:           introduction.Latitude,
			Longitude:          introduction.Longitude,
		},
	)
	if err != nil {
		return AttractionIntroduction{}, fmt.Errorf(
			"upsert attraction introduction: %w",
			err,
		)
	}
	return AttractionIntroduction{
		Key:                row.Key,
		Name:               row.Name,
		Introduction:       cloneJSON(row.Introduction),
		CulturalElementKey: row.CulturalElementKey,
		AttractionKey:      row.AttractionKey,
		Latitude:           row.Latitude,
		Longitude:          row.Longitude,
	}, nil
}

func (r *PostgresRepository) UpsertRelation(
	ctx context.Context,
	relation Relation,
) error {
	if err := r.queries.UpsertCulturalElementRelation(
		ctx,
		dbgen.UpsertCulturalElementRelationParams{
			ElementKey:        relation.ElementKey,
			RelatedElementKey: relation.RelatedElementKey,
		},
	); err != nil {
		return fmt.Errorf("upsert cultural element relation: %w", err)
	}
	return nil
}

func (r *PostgresRepository) Import(
	ctx context.Context,
	bundle Bundle,
) (ImportResult, error) {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return ImportResult{}, fmt.Errorf("begin content import: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	queries := r.queries.WithTx(tx)
	for _, element := range bundle.Elements {
		if _, err := queries.UpsertCulturalElement(
			ctx,
			dbgen.UpsertCulturalElementParams{
				ElementKey:   element.Key,
				Name:         element.Name,
				Introduction: element.Introduction,
			},
		); err != nil {
			return ImportResult{}, fmt.Errorf("import cultural element %q: %w", element.Key, err)
		}
	}
	for _, attraction := range bundle.Attractions {
		if _, err := queries.UpsertAttraction(
			ctx,
			dbgen.UpsertAttractionParams{
				AttractionKey: attraction.Key,
				Name:          attraction.Name,
			},
		); err != nil {
			return ImportResult{}, fmt.Errorf("import attraction %q: %w", attraction.Key, err)
		}
	}
	for _, relation := range bundle.Relations {
		if err := queries.UpsertCulturalElementRelation(
			ctx,
			dbgen.UpsertCulturalElementRelationParams{
				ElementKey:        relation.ElementKey,
				RelatedElementKey: relation.RelatedElementKey,
			},
		); err != nil {
			return ImportResult{}, fmt.Errorf("import cultural relation: %w", err)
		}
	}
	for _, introduction := range bundle.Introductions {
		if _, err := queries.UpsertAttractionCulturalIntroduction(
			ctx,
			dbgen.UpsertAttractionCulturalIntroductionParams{
				IntroductionKey:    introduction.Key,
				Name:               introduction.Name,
				Introduction:       introduction.Introduction,
				CulturalElementKey: introduction.CulturalElementKey,
				AttractionKey:      introduction.AttractionKey,
				Latitude:           introduction.Latitude,
				Longitude:          introduction.Longitude,
			},
		); err != nil {
			return ImportResult{}, fmt.Errorf(
				"import attraction introduction %q: %w",
				introduction.Key,
				err,
			)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return ImportResult{}, fmt.Errorf("commit content import: %w", err)
	}
	return ImportResult{
		Version:       bundle.Version,
		Elements:      len(bundle.Elements),
		Attractions:   len(bundle.Attractions),
		Relations:     len(bundle.Relations),
		Introductions: len(bundle.Introductions),
	}, nil
}

func cloneJSON(value []byte) json.RawMessage {
	return append(json.RawMessage(nil), value...)
}

func mapIntroductionRow(
	row dbgen.ListAllAttractionCulturalIntroductionsRow,
) AttractionIntroduction {
	return AttractionIntroduction{
		Key:                 row.Key,
		Name:                row.Name,
		Introduction:        cloneJSON(row.Introduction),
		CulturalElementKey:  row.CulturalElementKey,
		CulturalElementName: row.CulturalElementName,
		AttractionKey:       row.AttractionKey,
		AttractionName:      row.AttractionName,
		Latitude:            row.Latitude,
		Longitude:           row.Longitude,
	}
}
