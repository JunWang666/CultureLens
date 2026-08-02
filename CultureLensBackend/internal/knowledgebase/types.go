package knowledgebase

const (
	ReviewStatusImported = "imported"
	ReviewStatusReviewed = "reviewed"
)

type Bundle struct {
	Version     string     `json:"version"`
	GeneratedAt string     `json:"generated_at"`
	Records     []Record   `json:"records"`
	Relations   []Relation `json:"relations"`
	Statistics  Statistics `json:"statistics"`
}

type Record struct {
	ID                 string           `json:"id"`
	SourceKey          string           `json:"source_key"`
	Kind               string           `json:"kind"`
	CanonicalName      string           `json:"canonical_name"`
	Aliases            []string         `json:"aliases,omitempty"`
	Summary            string           `json:"summary"`
	Attributes         []Attribute      `json:"attributes,omitempty"`
	Citations          []Citation       `json:"citations"`
	MediaReferences    []MediaReference `json:"media_references,omitempty"`
	ReviewStatus       string           `json:"review_status"`
	ContentFingerprint string           `json:"content_fingerprint"`
}

type Attribute struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

type Citation struct {
	ID              string `json:"id"`
	SourceType      string `json:"source_type"`
	Title           string `json:"title"`
	Publisher       string `json:"publisher"`
	URL             string `json:"url"`
	AccessedAt      string `json:"accessed_at"`
	License         string `json:"license,omitempty"`
	LicenseURL      string `json:"license_url,omitempty"`
	RightsStatement string `json:"rights_statement,omitempty"`
	Modified        bool   `json:"modified"`
	RevisionID      string `json:"revision_id,omitempty"`
}

type MediaReference struct {
	URL             string `json:"url"`
	Role            string `json:"role"`
	RightsStatement string `json:"rights_statement"`
}

type Relation struct {
	ID           string   `json:"id"`
	SourceID     string   `json:"source_id"`
	TargetID     string   `json:"target_id"`
	Kind         string   `json:"kind"`
	Explanation  string   `json:"explanation"`
	CitationIDs  []string `json:"citation_ids"`
	ReviewStatus string   `json:"review_status"`
}

type Statistics struct {
	TotalRecords   int            `json:"total_records"`
	TotalRelations int            `json:"total_relations"`
	ByKind         map[string]int `json:"by_kind"`
	BySource       map[string]int `json:"by_source"`
}

type WikipediaSeed struct {
	Version    string                `json:"version"`
	AccessedAt string                `json:"accessed_at"`
	License    string                `json:"license"`
	LicenseURL string                `json:"license_url"`
	Records    []WikipediaSeedRecord `json:"records"`
}

type WikipediaSeedRecord struct {
	Title          string                  `json:"title"`
	CanonicalName  string                  `json:"canonical_name"`
	URL            string                  `json:"url"`
	RevisionID     string                  `json:"revision_id"`
	Kind           string                  `json:"kind"`
	Aliases        []string                `json:"aliases,omitempty"`
	Summary        string                  `json:"summary"`
	LastModifiedAt string                  `json:"last_modified_at,omitempty"`
	Relations      []WikipediaSeedRelation `json:"relations,omitempty"`
}

type WikipediaSeedRelation struct {
	Kind        string `json:"kind"`
	TargetTitle string `json:"target_title"`
	Explanation string `json:"explanation"`
}
