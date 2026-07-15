package execution_test

import (
	"testing"
	"time"

	"github.com/fanhuadesenlinnn/os-init/internal/execution"
)

func TestTimeoutFromEnv(t *testing.T) {
	tests := map[string]time.Duration{
		"":    execution.DefaultTimeout,
		"0":   0,
		"90":  90 * time.Second,
		"2m":  2 * time.Minute,
		"bad": execution.DefaultTimeout,
	}
	for value, want := range tests {
		if got := execution.TimeoutFromEnv(value); got != want {
			t.Fatalf("TimeoutFromEnv(%q) = %s, want %s", value, got, want)
		}
	}
}
