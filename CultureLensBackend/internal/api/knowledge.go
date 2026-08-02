package api

import (
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"strconv"
	"strings"

	"github.com/goudaijun/culturelens-backend/internal/knowledge"
)

const (
	defaultKnowledgeLimit = 12
	maximumKnowledgeLimit = 20
	defaultRadiusMeters   = 5000
	maximumRadiusMeters   = 50000
)

type culturalElementResponse struct {
	Key          string          `json:"key"`
	Name         string          `json:"name"`
	Introduction json.RawMessage `json:"introduction"`
}

type relatedElementsResponse struct {
	Element         culturalElementResponse   `json:"element"`
	RelatedElements []culturalElementResponse `json:"relatedElements"`
}

type requestedCoordinate struct {
	Latitude     float64 `json:"latitude"`
	Longitude    float64 `json:"longitude"`
	RadiusMeters float64 `json:"radiusMeters"`
}

type contentReference struct {
	Key  string `json:"key"`
	Name string `json:"name"`
}

type coordinateResponse struct {
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
}

type attractionIntroductionResponse struct {
	Key             string             `json:"key"`
	Name            string             `json:"name"`
	Introduction    json.RawMessage    `json:"introduction"`
	CulturalElement contentReference   `json:"culturalElement"`
	Attraction      contentReference   `json:"attraction"`
	Location        coordinateResponse `json:"location"`
	DistanceMeters  float64            `json:"distanceMeters"`
}

type nearbyIntroductionsResponse struct {
	RequestedLocation requestedCoordinate              `json:"requestedLocation"`
	TotalMatches      int                              `json:"totalMatches"`
	Introductions     []attractionIntroductionResponse `json:"introductions"`
}

func (s Server) relatedCulturalElements(w http.ResponseWriter, r *http.Request) {
	elementKey := strings.TrimSpace(r.PathValue("elementKey"))
	limit, validLimit := parseKnowledgeLimit(r.URL.Query().Get("limit"))
	if !validContentKey(elementKey) || !validLimit {
		s.writeError(
			w,
			r,
			http.StatusBadRequest,
			"invalid_request",
			"请求参数无效。",
			false,
		)
		return
	}

	set, err := s.content.RelatedElements(r.Context(), elementKey, limit)
	if err != nil {
		if errors.Is(err, knowledge.ErrCulturalElementNotFound) {
			s.writeError(
				w,
				r,
				http.StatusNotFound,
				"cultural_element_not_found",
				"未找到该文化元素。",
				false,
			)
			return
		}
		s.logger.Error(
			"query related cultural elements",
			"request_id",
			requestID(r.Context()),
			"element_key",
			elementKey,
			"error",
			err,
		)
		s.writeError(
			w,
			r,
			http.StatusServiceUnavailable,
			"knowledge_unavailable",
			"文化知识服务暂时不可用，请稍后重试。",
			true,
		)
		return
	}
	related := make([]culturalElementResponse, 0, len(set.RelatedElements))
	for _, element := range set.RelatedElements {
		related = append(related, mapCulturalElement(element))
	}
	response := relatedElementsResponse{
		Element:         mapCulturalElement(set.Element),
		RelatedElements: related,
	}
	s.logger.Info(
		"related cultural elements completed",
		"request_id",
		requestID(r.Context()),
		"element_key",
		elementKey,
		"related_count",
		len(related),
	)
	writeJSON(w, http.StatusOK, response)
}

func (s Server) recommendAttractionIntroductions(
	w http.ResponseWriter,
	r *http.Request,
) {
	latitude, validLatitude := parseRequiredFloat(
		r.URL.Query().Get("latitude"),
	)
	longitude, validLongitude := parseRequiredFloat(
		r.URL.Query().Get("longitude"),
	)
	radiusMeters, validRadius := parseOptionalFloat(
		r.URL.Query().Get("radiusMeters"),
		defaultRadiusMeters,
	)
	limit, validLimit := parseKnowledgeLimit(r.URL.Query().Get("limit"))
	if !validLatitude || !validLongitude || !validRadius || !validLimit ||
		latitude < -90 || latitude > 90 ||
		longitude < -180 || longitude > 180 ||
		radiusMeters < 1 || radiusMeters > maximumRadiusMeters {
		s.writeError(
			w,
			r,
			http.StatusBadRequest,
			"invalid_request",
			"请求参数无效。",
			false,
		)
		return
	}

	set, err := s.content.NearbyIntroductions(
		r.Context(),
		knowledge.NearbyIntroductionQuery{
			Latitude:     latitude,
			Longitude:    longitude,
			RadiusMeters: radiusMeters,
			Limit:        limit,
		},
	)
	if err != nil {
		s.logger.Error(
			"recommend attraction introductions",
			"request_id",
			requestID(r.Context()),
			"radius_meters",
			radiusMeters,
			"error",
			err,
		)
		s.writeError(
			w,
			r,
			http.StatusServiceUnavailable,
			"knowledge_unavailable",
			"文化知识服务暂时不可用，请稍后重试。",
			true,
		)
		return
	}
	introductions := make(
		[]attractionIntroductionResponse,
		0,
		len(set.Introductions),
	)
	for _, introduction := range set.Introductions {
		introductions = append(
			introductions,
			mapAttractionIntroduction(introduction),
		)
	}
	response := nearbyIntroductionsResponse{
		RequestedLocation: requestedCoordinate{
			Latitude:     latitude,
			Longitude:    longitude,
			RadiusMeters: radiusMeters,
		},
		TotalMatches:  set.TotalMatches,
		Introductions: introductions,
	}
	s.logger.Info(
		"attraction introduction recommendations completed",
		"request_id",
		requestID(r.Context()),
		"radius_meters",
		radiusMeters,
		"result_count",
		len(introductions),
		"total_matches",
		set.TotalMatches,
	)
	writeJSON(w, http.StatusOK, response)
}

func parseKnowledgeLimit(value string) (int, bool) {
	value = strings.TrimSpace(value)
	if value == "" {
		return defaultKnowledgeLimit, true
	}
	limit, err := strconv.Atoi(value)
	if err != nil || limit < 1 || limit > maximumKnowledgeLimit {
		return 0, false
	}
	return limit, true
}

func parseRequiredFloat(value string) (float64, bool) {
	value = strings.TrimSpace(value)
	if value == "" {
		return 0, false
	}
	parsed, err := strconv.ParseFloat(value, 64)
	return parsed, err == nil && finiteFloat(parsed)
}

func parseOptionalFloat(value string, fallback float64) (float64, bool) {
	if strings.TrimSpace(value) == "" {
		return fallback, true
	}
	return parseRequiredFloat(value)
}

func finiteFloat(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
}

func validContentKey(value string) bool {
	if len(value) < 1 || len(value) > 128 {
		return false
	}
	for index, character := range []byte(value) {
		valid := character >= 'a' && character <= 'z' ||
			character >= '0' && character <= '9' ||
			index > 0 && (character == '.' || character == '_' || character == '-')
		if !valid {
			return false
		}
	}
	return true
}

func mapCulturalElement(element knowledge.CulturalElement) culturalElementResponse {
	return culturalElementResponse{
		Key:          element.Key,
		Name:         element.Name,
		Introduction: element.Introduction,
	}
}

func mapAttractionIntroduction(
	introduction knowledge.AttractionIntroduction,
) attractionIntroductionResponse {
	return attractionIntroductionResponse{
		Key:          introduction.Key,
		Name:         introduction.Name,
		Introduction: introduction.Introduction,
		CulturalElement: contentReference{
			Key:  introduction.CulturalElement.Key,
			Name: introduction.CulturalElement.Name,
		},
		Attraction: contentReference{
			Key:  introduction.Attraction.Key,
			Name: introduction.Attraction.Name,
		},
		Location: coordinateResponse{
			Latitude:  introduction.Location.Latitude,
			Longitude: introduction.Location.Longitude,
		},
		DistanceMeters: math.Round(introduction.DistanceMeters*10) / 10,
	}
}
