package config

import (
	"strings"
	"testing"
)

func TestParseEnv(t *testing.T) {
	t.Parallel()

	got := ParseEnv(strings.NewReader(`
# comment
export HTTP_PROXY="http://127.0.0.1:7890"
NO_PROXY='localhost,127.0.0.1'
GO_VERSION=go1.26.3
bad-key=value
`))

	if got["HTTP_PROXY"] != "http://127.0.0.1:7890" {
		t.Fatalf("unexpected HTTP_PROXY: %q", got["HTTP_PROXY"])
	}
	if got["NO_PROXY"] != "localhost,127.0.0.1" {
		t.Fatalf("unexpected NO_PROXY: %q", got["NO_PROXY"])
	}
	if got["GO_VERSION"] != "go1.26.3" {
		t.Fatalf("unexpected GO_VERSION: %q", got["GO_VERSION"])
	}
	if _, ok := got["bad-key"]; ok {
		t.Fatal("invalid key should be ignored")
	}
}
