// Package state stores versioned execution records independently from the
// resource ownership state maintained by shell providers.
package state

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const SchemaVersion = 1

type Record struct {
	SchemaVersion    int       `json:"schema_version"`
	RecordedAt       time.Time `json:"recorded_at"`
	ModuleID         string    `json:"module_id"`
	Operation        string    `json:"operation"`
	Status           string    `json:"status"`
	ExitCode         int       `json:"exit_code"`
	ProviderProtocol int       `json:"provider_protocol,omitempty"`
	ProviderStatus   string    `json:"provider_status,omitempty"`
	AffectedPaths    []string  `json:"affected_paths,omitempty"`
	LogFile          string    `json:"log_file,omitempty"`
	Error            string    `json:"error,omitempty"`
}

type Recorder interface{ Save(Record) error }

type FileStore struct{ Dir string }

func Default() *FileStore {
	home, _ := os.UserHomeDir()
	return &FileStore{Dir: filepath.Join(home, ".local", "state", "os-init", "runs")}
}

func (s *FileStore) Save(record Record) error {
	if s == nil || s.Dir == "" {
		return nil
	}
	if record.SchemaVersion == 0 {
		record.SchemaVersion = SchemaVersion
	}
	if record.RecordedAt.IsZero() {
		record.RecordedAt = time.Now().UTC()
	}
	if err := os.MkdirAll(s.Dir, 0o700); err != nil {
		return fmt.Errorf("create state dir: %w", err)
	}
	data, err := json.MarshalIndent(record, "", "  ")
	if err != nil {
		return fmt.Errorf("encode state: %w", err)
	}
	name := fmt.Sprintf("%s-%s-%d.json", record.RecordedAt.Format("20060102T150405.000000000Z"), safeName(record.ModuleID), record.RecordedAt.UnixNano())
	tmp, err := os.CreateTemp(s.Dir, ".record-*.tmp")
	if err != nil {
		return fmt.Errorf("create state temp file: %w", err)
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if err := tmp.Chmod(0o600); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("secure state temp file: %w", err)
	}
	_, err = tmp.Write(append(data, '\n'))
	closeErr := tmp.Close()
	if err != nil {
		return fmt.Errorf("write state: %w", err)
	}
	if closeErr != nil {
		return fmt.Errorf("close state: %w", closeErr)
	}
	if err := os.Rename(tmpName, filepath.Join(s.Dir, name)); err != nil {
		return fmt.Errorf("commit state: %w", err)
	}
	return nil
}

func safeName(value string) string {
	value = strings.Map(func(r rune) rune {
		if r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '_' {
			return r
		}
		return '-'
	}, value)
	if value == "" {
		return "module"
	}
	return value
}
