package platform_test

import (
	"os"
	"strings"
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/platform"
)

func TestDetectFrom_ClassifiesLinuxFamilies(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		content string
		want    platform.Family
	}{
		{
			name: "ubuntu",
			content: `
ID=ubuntu
ID_LIKE=debian
VERSION_ID="24.04"
VERSION_CODENAME=noble
`,
			want: platform.FamilyDebian,
		},
		{
			name: "debian",
			content: `
ID=debian
VERSION_ID=12
VERSION_CODENAME=bookworm
`,
			want: platform.FamilyDebian,
		},
		{
			name: "rocky",
			content: `
ID="rocky"
ID_LIKE="rhel centos fedora"
VERSION_ID="9.4"
`,
			want: platform.FamilyRedHat,
		},
		{
			name: "almalinux",
			content: `
ID=almalinux
ID_LIKE="rhel centos fedora"
`,
			want: platform.FamilyRedHat,
		},
		{
			name: "centos",
			content: `
ID=centos
ID_LIKE="rhel fedora"
`,
			want: platform.FamilyRedHat,
		},
		{
			name: "rhel",
			content: `
ID=rhel
`,
			want: platform.FamilyRedHat,
		},
		{
			name: "fedora",
			content: `
ID=fedora
`,
			want: platform.FamilyRedHat,
		},
		{
			name: "arch",
			content: `
ID=arch
`,
			want: platform.FamilyArch,
		},
		{
			name: "manjaro",
			content: `
ID=manjaro
ID_LIKE=arch
`,
			want: platform.FamilyArch,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			target := detectFromContent(t, tt.content)
			if target.Family != tt.want {
				t.Fatalf("family = %q, want %q", target.Family, tt.want)
			}
		})
	}
}

func TestDetectFrom_Darwin(t *testing.T) {
	t.Parallel()

	target := platform.DetectFrom("darwin", "/path/that/does/not/exist")
	if target.Family != platform.FamilyDarwin {
		t.Fatalf("family = %q, want %q", target.Family, platform.FamilyDarwin)
	}
}

func TestDetectFrom_MissingOSReleaseReturnsUnknown(t *testing.T) {
	t.Parallel()

	target := platform.DetectFrom("linux", "/path/that/does/not/exist")
	if target.Family != platform.FamilyUnknown {
		t.Fatalf("family = %q, want %q", target.Family, platform.FamilyUnknown)
	}
}

func TestParseOSRelease_QuotedValuesAndIDLike(t *testing.T) {
	t.Parallel()

	values, err := platform.ParseOSRelease(strings.NewReader(`
# comment
ID="rocky"
ID_LIKE="rhel centos fedora"
VERSION_ID="9.4"
VERSION_CODENAME='Blue Onyx'
`))
	if err != nil {
		t.Fatalf("ParseOSRelease failed: %v", err)
	}
	if values["ID"] != "rocky" {
		t.Fatalf("ID = %q, want rocky", values["ID"])
	}
	if values["ID_LIKE"] != "rhel centos fedora" {
		t.Fatalf("ID_LIKE = %q", values["ID_LIKE"])
	}
	if values["VERSION_CODENAME"] != "Blue Onyx" {
		t.Fatalf("VERSION_CODENAME = %q", values["VERSION_CODENAME"])
	}
}

func detectFromContent(t *testing.T, content string) platform.Target {
	t.Helper()

	path := t.TempDir() + "/os-release"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write os-release: %v", err)
	}
	return platform.DetectFrom("linux", path)
}
