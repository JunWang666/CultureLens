package api

import (
	"context"
	"net/http"
	"reflect"
	"strings"

	"github.com/danielgtaylor/huma/v2"
	"github.com/danielgtaylor/huma/v2/adapters/humago"
	"github.com/goudaijun/culturelens-backend/internal/recognition"
)

const (
	apiDocumentationVersion = "1.2.0"
	productionServerURL     = "https://cl.codight.online"
)

type healthResponse struct {
	Status string `json:"status" enum:"ok" example:"ok" doc:"Service process health."`
}

type documentedHealthInput struct {
	RequestID string `header:"X-Request-ID" required:"false" doc:"Optional caller-supplied request ID."`
}

type documentedHealthOutput struct {
	RequestID string         `header:"X-Request-ID" doc:"Request ID used for this response."`
	Body      healthResponse `contentType:"application/json"`
}

type documentedRecognitionInput struct {
	RequestID string              `header:"X-Request-ID" required:"false" doc:"Optional caller-supplied request ID."`
	Body      recognition.Request `contentType:"application/json" required:"true"`
}

type documentedRecognitionOutput struct {
	RequestID string               `header:"X-Request-ID" doc:"Request ID used for this response."`
	Body      recognition.Response `contentType:"application/json"`
}

type documentedRecommendationsInput struct {
	RequestID    string  `header:"X-Request-ID" required:"false" doc:"Optional caller-supplied request ID."`
	Latitude     float64 `query:"latitude" required:"true" minimum:"-90" maximum:"90" doc:"WGS84 latitude in decimal degrees."`
	Longitude    float64 `query:"longitude" required:"true" minimum:"-180" maximum:"180" doc:"WGS84 longitude in decimal degrees."`
	RadiusMeters float64 `query:"radiusMeters" required:"false" minimum:"1" maximum:"50000" default:"5000" doc:"Maximum great-circle distance from the requested coordinate."`
	Limit        int     `query:"limit" required:"false" minimum:"1" maximum:"20" default:"12" doc:"Maximum number of introductions to return."`
}

type documentedRecommendationsOutput struct {
	RequestID string                      `header:"X-Request-ID" doc:"Request ID used for this response."`
	Body      nearbyIntroductionsResponse `contentType:"application/json"`
}

type documentedRelatedObjectsInput struct {
	RequestID  string `header:"X-Request-ID" required:"false" doc:"Optional caller-supplied request ID."`
	ElementKey string `path:"elementKey" pattern:"^[a-z0-9][a-z0-9._-]{0,127}$" doc:"Stable key of a cultural element."`
	Limit      int    `query:"limit" required:"false" minimum:"1" maximum:"20" default:"12" doc:"Maximum number of related elements to return."`
}

type documentedRelatedObjectsOutput struct {
	RequestID string                  `header:"X-Request-ID" doc:"Request ID used for this response."`
	Body      relatedElementsResponse `contentType:"application/json"`
}

type documentedError struct {
	Code      string `json:"code" example:"invalid_request" doc:"Stable machine-readable error code."`
	Message   string `json:"message" example:"请求参数无效。" doc:"User-facing localized error message."`
	Retryable bool   `json:"retryable" example:"false" doc:"Whether retrying the same operation may succeed."`
}

type documentedErrorEnvelope struct {
	RequestID string          `json:"request_id" format:"uuid" doc:"Request ID used for diagnostics."`
	Error     documentedError `json:"error"`
}

func newDocumentationHandler() http.Handler {
	mux := http.NewServeMux()
	config := huma.DefaultConfig("CultureLens API", apiDocumentationVersion)
	config.Info.Description = "CultureLens visual recognition and location-aware cultural content API."
	config.Servers = []*huma.Server{{
		URL:         productionServerURL,
		Description: "Production",
	}}
	config.Tags = []*huma.Tag{
		{Name: "System", Description: "Service health and operational endpoints."},
		{Name: "Recognition", Description: "Visual recognition using full-scene and optional focus images."},
		{Name: "Knowledge", Description: "Read-only access to cultural elements and location-specific attraction introductions."},
	}
	// The real handlers do not add Huma schema links or mutate response bodies.
	config.CreateHooks = nil

	documentationAPI := humago.New(mux, config)
	registerDocumentationOperations(documentationAPI)
	return mux
}

func registerDocumentationOperations(documentationAPI huma.API) {
	huma.Register(
		documentationAPI,
		huma.Operation{
			OperationID: "get-health",
			Method:      http.MethodGet,
			Path:        "/health",
			Summary:     "Check service health",
			Description: "Returns process health. It does not call Gemini or verify downstream dependencies.",
			Tags:        []string{"System"},
		},
		func(context.Context, *documentedHealthInput) (*documentedHealthOutput, error) {
			return &documentedHealthOutput{Body: healthResponse{Status: "ok"}}, nil
		},
	)

	huma.Register(
		documentationAPI,
		huma.Operation{
			OperationID:  "create-recognition",
			Method:       http.MethodPost,
			Path:         "/v1/recognitions",
			Summary:      "Recognize a cultural object",
			Description:  "Validates a full-scene image and optional user-selected focus image, retrieves reviewed catalog candidates, and asks Gemini to rank or identify the object. The JSON request body is limited to 18 MiB. Images are processed in memory and are not persisted by this service.",
			Tags:         []string{"Recognition"},
			MaxBodyBytes: 18 << 20,
			Responses:    documentedErrorResponses(documentationAPI),
		},
		func(context.Context, *documentedRecognitionInput) (*documentedRecognitionOutput, error) {
			return &documentedRecognitionOutput{}, nil
		},
	)

	huma.Register(
		documentationAPI,
		huma.Operation{
			OperationID: "recommend-attraction-introductions",
			Method:      http.MethodGet,
			Path:        "/v1/attraction-introductions/recommendations",
			Summary:     "Recommend attraction introductions near a coordinate",
			Description: "Returns location-specific cultural introductions within a WGS84 radius, ordered by Haversine great-circle distance. An empty radius match returns an empty list without catalog fallback.",
			Tags:        []string{"Knowledge"},
			Responses: documentedKnowledgeErrorResponses(
				documentationAPI,
				false,
			),
		},
		func(
			context.Context,
			*documentedRecommendationsInput,
		) (*documentedRecommendationsOutput, error) {
			return &documentedRecommendationsOutput{}, nil
		},
	)

	huma.Register(
		documentationAPI,
		huma.Operation{
			OperationID: "list-related-cultural-elements",
			Method:      http.MethodGet,
			Path:        "/v1/cultural-elements/{elementKey}/related",
			Summary:     "List related cultural elements",
			Description: "Returns explicit undirected cultural-element relations from PostgreSQL. It never infers relationships from names or introduction text.",
			Tags:        []string{"Knowledge"},
			Responses: documentedKnowledgeErrorResponses(
				documentationAPI,
				true,
			),
		},
		func(
			context.Context,
			*documentedRelatedObjectsInput,
		) (*documentedRelatedObjectsOutput, error) {
			return &documentedRelatedObjectsOutput{}, nil
		},
	)
}

func documentedErrorResponses(documentationAPI huma.API) map[string]*huma.Response {
	schema := huma.SchemaFromType(
		documentationAPI.OpenAPI().Components.Schemas,
		reflect.TypeOf(documentedErrorEnvelope{}),
	)
	response := func(description string) *huma.Response {
		return &huma.Response{
			Description: description,
			Content: map[string]*huma.MediaType{
				"application/json": {Schema: schema},
			},
		}
	}
	return map[string]*huma.Response{
		"400": response("The JSON or request parameters are invalid."),
		"413": response("The image or request body is too large."),
		"415": response("The image format or content is unsupported."),
		"502": response("Gemini returned output that failed schema validation."),
		"503": response("The recognition service is temporarily unavailable."),
		"504": response("The upstream recognition request timed out."),
	}
}

func documentedKnowledgeErrorResponses(
	documentationAPI huma.API,
	includeNotFound bool,
) map[string]*huma.Response {
	schema := huma.SchemaFromType(
		documentationAPI.OpenAPI().Components.Schemas,
		reflect.TypeOf(documentedErrorEnvelope{}),
	)
	response := func(description string) *huma.Response {
		return &huma.Response{
			Description: description,
			Content: map[string]*huma.MediaType{
				"application/json": {Schema: schema},
			},
		}
	}
	responses := map[string]*huma.Response{
		"400": response("The element key, coordinate, radius, or limit is invalid."),
		"503": response("The cultural content repository is temporarily unavailable."),
	}
	if includeNotFound {
		responses["404"] = response(
			"The requested cultural element does not exist.",
		)
	}
	return responses
}

func isDocumentationPath(path string) bool {
	switch path {
	case "/docs", "/openapi.json", "/openapi.yaml",
		"/openapi-3.0.json", "/openapi-3.0.yaml":
		return true
	default:
		return strings.HasPrefix(path, "/schemas/")
	}
}
