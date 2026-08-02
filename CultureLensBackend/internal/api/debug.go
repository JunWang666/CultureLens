package api

import (
	_ "embed"
	"net/http"
)

//go:embed debug.html
var debugPage []byte

func (s Server) debug(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set(
		"Content-Security-Policy",
		"default-src 'self'; style-src 'unsafe-inline'; "+
			"script-src 'unsafe-inline'; connect-src 'self'; "+
			"img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'",
	)
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(debugPage)
}
