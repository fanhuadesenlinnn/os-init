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
			name: "kylin advanced server",
			content: `
NAME="Kylin Linux Advanced Server"
VERSION="V10 (Halberd)"
ID="kylin"
VERSION_ID="V10"
PRETTY_NAME="Kylin Linux Advanced Server V10 (Halberd)"
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

func TestDetectFrom_DarwinReturnsDarwinFamily(t *testing.T) {
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

func TestDetectFromPaths_DetectsWSL2AndWSLg(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	osRelease := dir + "/os-release"
	kernelRelease := dir + "/kernel-release"
	wslg := dir + "/wslg"
	if err := os.WriteFile(osRelease, []byte("ID=ubuntu\nID_LIKE=debian\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(kernelRelease, []byte("6.6.87.2-microsoft-standard-WSL2\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(wslg, 0o755); err != nil {
		t.Fatal(err)
	}

	target := platform.DetectFromPaths("linux", osRelease, kernelRelease, wslg)
	if target.Environment != platform.EnvironmentWSL || target.WSLVersion != 2 || !target.WSLg {
		t.Fatalf("unexpected WSL target: %#v", target)
	}
	if target.Family != platform.FamilyDebian {
		t.Fatalf("family = %q, want debian", target.Family)
	}
}

func TestDetectFromPaths_DistinguishesWSL1(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	osRelease := dir + "/os-release"
	kernelRelease := dir + "/kernel-release"
	if err := os.WriteFile(osRelease, []byte("ID=debian\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(kernelRelease, []byte("4.4.0-19041-Microsoft\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	target := platform.DetectFromPaths("linux", osRelease, kernelRelease, dir+"/missing-wslg")
	if target.Environment != platform.EnvironmentWSL || target.WSLVersion != 1 || target.WSLg {
		t.Fatalf("unexpected WSL1 target: %#v", target)
	}
}

func TestDetectFromPaths_DetectsOrbStack(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	osRelease := dir + "/os-release"
	kernelRelease := dir + "/kernel-release"
	if err := os.WriteFile(osRelease, []byte("ID=archarm\nID_LIKE=arch\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(kernelRelease, []byte("7.0.11-orbstack-00360\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	target := platform.DetectFromPaths("linux", osRelease, kernelRelease, dir+"/missing-wslg")
	if target.Environment != platform.EnvironmentOrbStack || target.Family != platform.FamilyArch {
		t.Fatalf("unexpected OrbStack target: %#v", target)
	}
}

func TestDetectFromPathsWithContainerContext_DetectsMarkersAndCgroups(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	osRelease := dir + "/os-release"
	kernelRelease := dir + "/kernel-release"
	cgroup := dir + "/cgroup"
	marker := dir + "/.dockerenv"
	if err := os.WriteFile(osRelease, []byte("ID=debian\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(kernelRelease, []byte("6.12.0-linux\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(cgroup, []byte("0::/user.slice\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(marker, nil, 0o644); err != nil {
		t.Fatal(err)
	}

	target := platform.DetectFromPathsWithContainerContext("linux", osRelease, kernelRelease, dir+"/missing-wslg", cgroup, marker)
	if target.Environment != platform.EnvironmentContainer {
		t.Fatalf("environment = %q, want container", target.Environment)
	}

	if err := os.Remove(marker); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(cgroup, []byte("0::/docker/abcdef\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	target = platform.DetectFromPathsWithContainerContext("linux", osRelease, kernelRelease, dir+"/missing-wslg", cgroup, marker)
	if target.Environment != platform.EnvironmentContainer {
		t.Fatalf("cgroup environment = %q, want container", target.Environment)
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
