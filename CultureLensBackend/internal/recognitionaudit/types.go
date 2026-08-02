package recognitionaudit

import (
	"context"
	"encoding/json"
	"errors"
	"time"
)

var ErrImageNotFound = errors.New("recognition audit image not found")

type Record struct {
	RequestID            string
	ReceivedAt           time.Time
	CompletedAt          time.Time
	DurationMilliseconds int64
	HTTPStatus           int
	ErrorCode            string
	RequestBodyBytes     int64
	RequestPayload       json.RawMessage
	ContextImage         []byte
	ContextMIMEType      string
	FocusImage           []byte
	FocusMIMEType        string
	ResponsePayload      json.RawMessage
	ModelIdentifier      string
	PromptVersion        string
	SchemaVersion        string
	ResolutionStatus     string
	CulturalElementKey   string
	CanonicalName        string
}

type Summary struct {
	ID                   int64           `json:"id"`
	RequestID            string          `json:"requestId"`
	ReceivedAt           time.Time       `json:"receivedAt"`
	CompletedAt          time.Time       `json:"completedAt"`
	DurationMilliseconds int64           `json:"durationMilliseconds"`
	HTTPStatus           int             `json:"httpStatus"`
	ErrorCode            string          `json:"errorCode,omitempty"`
	RequestBodyBytes     int64           `json:"requestBodyBytes"`
	RequestPayload       json.RawMessage `json:"requestPayload,omitempty"`
	ContextMIMEType      string          `json:"contextMimeType,omitempty"`
	ContextImageBytes    int64           `json:"contextImageBytes"`
	FocusMIMEType        string          `json:"focusMimeType,omitempty"`
	FocusImageBytes      int64           `json:"focusImageBytes"`
	ResponsePayload      json.RawMessage `json:"responsePayload"`
	ModelIdentifier      string          `json:"modelIdentifier,omitempty"`
	PromptVersion        string          `json:"promptVersion,omitempty"`
	SchemaVersion        string          `json:"schemaVersion,omitempty"`
	ResolutionStatus     string          `json:"resolutionStatus,omitempty"`
	CulturalElementKey   string          `json:"culturalElementKey,omitempty"`
	CanonicalName        string          `json:"canonicalName,omitempty"`
}

type Image struct {
	MIMEType string
	Data     []byte
}

type Writer interface {
	SaveRecognitionRequest(context.Context, Record) error
}

type Reader interface {
	RecentRecognitionRequests(context.Context, int) ([]Summary, error)
	RecognitionRequestImage(context.Context, int64, string) (Image, error)
}
