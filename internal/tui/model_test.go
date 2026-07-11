package tui

import (
	"errors"
	"io/fs"
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
)

type failingFS struct{}

func (failingFS) Open(string) (fs.File, error) {
	return nil, errors.New("broken assets")
}

func TestStartExecutionReportsAssetExtractionFailure(t *testing.T) {
	m := Model{config: Config{Assets: failingFS{}}, selectedModules: []modules.Module{{ID: "test", Label: "Test"}}}
	defer func() {
		if recovered := recover(); recovered != nil {
			t.Fatalf("startExecution panicked instead of reporting extraction failure: %v", recovered)
		}
	}()
	next, _ := m.startExecution()
	if next.screen != screenSummary || len(next.summary.results) != 1 || next.summary.results[0].ExitCode == 0 {
		t.Fatalf("extraction failure summary = %+v", next.summary)
	}
}
