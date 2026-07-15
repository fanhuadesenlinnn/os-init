package state_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/state"
)

func TestFileStoreWritesVersionedPrivateRecord(t *testing.T) {
	dir := t.TempDir()
	store := &state.FileStore{Dir: dir}
	if err := store.Save(state.Record{ModuleID: "shell-zsh", Operation: "install", Status: "passed"}); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil || len(entries) != 1 {
		t.Fatalf("entries=%d err=%v", len(entries), err)
	}
	path := filepath.Join(dir, entries[0].Name())
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var record state.Record
	if err := json.Unmarshal(data, &record); err != nil {
		t.Fatal(err)
	}
	if record.SchemaVersion != state.SchemaVersion || record.ModuleID != "shell-zsh" {
		t.Fatalf("record=%+v", record)
	}
	info, _ := os.Stat(path)
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("mode=%o", info.Mode().Perm())
	}
}
