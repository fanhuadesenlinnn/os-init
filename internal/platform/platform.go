package platform

import (
	"bufio"
	"io"
	"os"
	"runtime"
	"strconv"
	"strings"
)

type Family string
type Environment string

const (
	FamilyDarwin  Family = "darwin"
	FamilyDebian  Family = "debian"
	FamilyRedHat  Family = "redhat"
	FamilyArch    Family = "arch"
	FamilyUnknown Family = "unknown"
)

const (
	EnvironmentNative Environment = "native"
	EnvironmentWSL    Environment = "wsl"
)

type Target struct {
	GOOS        string      `json:"goos"`
	ID          string      `json:"id"`
	IDLike      []string    `json:"id_like,omitempty"`
	Family      Family      `json:"family"`
	VersionID   string      `json:"version_id,omitempty"`
	Codename    string      `json:"codename,omitempty"`
	Init        string      `json:"init"`
	Environment Environment `json:"environment"`
	WSLVersion  int         `json:"wsl_version,omitempty"`
	WSLg        bool        `json:"wslg,omitempty"`
}

func Detect() Target {
	return DetectFromPaths(runtime.GOOS, "/etc/os-release", "/proc/sys/kernel/osrelease", "/mnt/wslg")
}

func DetectFrom(goos, osReleasePath string) Target {
	return DetectFromPaths(goos, osReleasePath, "/proc/sys/kernel/osrelease", "/mnt/wslg")
}

// DetectFromPaths exposes the environment probes for deterministic platform
// tests while keeping distribution classification based on os-release.
func DetectFromPaths(goos, osReleasePath, kernelReleasePath, wslgPath string) Target {
	target := Target{
		GOOS:        goos,
		Family:      FamilyUnknown,
		Init:        detectInit(goos),
		Environment: EnvironmentNative,
	}

	if goos == "darwin" {
		target.Family = FamilyDarwin
		return target
	}
	if goos != "linux" {
		return target
	}
	target.Environment, target.WSLVersion = detectLinuxEnvironment(kernelReleasePath)
	if target.Environment == EnvironmentWSL {
		if info, err := os.Stat(wslgPath); err == nil && info.IsDir() {
			target.WSLg = true
		}
	}

	f, err := os.Open(osReleasePath)
	if err != nil {
		return target
	}
	defer f.Close()

	values, err := ParseOSRelease(f)
	if err != nil {
		return target
	}

	target.ID = strings.ToLower(values["ID"])
	target.IDLike = splitLowerFields(values["ID_LIKE"])
	target.VersionID = values["VERSION_ID"]
	target.Codename = firstNonEmpty(values["VERSION_CODENAME"], values["UBUNTU_CODENAME"])
	target.Family = ClassifyFamily(target.ID, target.IDLike)
	return target
}

func detectLinuxEnvironment(kernelReleasePath string) (Environment, int) {
	data, err := os.ReadFile(kernelReleasePath)
	if err != nil {
		return EnvironmentNative, 0
	}
	release := strings.ToLower(string(data))
	if !strings.Contains(release, "microsoft") && !strings.Contains(release, "wsl") {
		return EnvironmentNative, 0
	}
	if strings.Contains(release, "wsl2") || strings.Contains(release, "microsoft-standard") {
		return EnvironmentWSL, 2
	}
	return EnvironmentWSL, 1
}

func ParseOSRelease(r io.Reader) (map[string]string, error) {
	values := map[string]string{}
	scanner := bufio.NewScanner(r)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		if key == "" {
			continue
		}
		values[key] = parseOSReleaseValue(value)
	}
	return values, scanner.Err()
}

func ClassifyFamily(id string, idLike []string) Family {
	id = strings.ToLower(id)
	switch id {
	case "arch", "manjaro", "endeavouros":
		return FamilyArch
	case "debian", "ubuntu", "linuxmint", "kali":
		return FamilyDebian
	case "rhel", "centos", "rocky", "almalinux", "fedora", "oracle", "oraclelinux", "ol", "kylin":
		return FamilyRedHat
	}

	for _, like := range idLike {
		switch strings.ToLower(like) {
		case "arch":
			return FamilyArch
		case "debian", "ubuntu":
			return FamilyDebian
		case "rhel", "fedora", "centos":
			return FamilyRedHat
		}
	}
	return FamilyUnknown
}

func parseOSReleaseValue(value string) string {
	value = strings.TrimSpace(value)
	if len(value) < 2 {
		return value
	}

	quote := value[0]
	if (quote == '"' || quote == '\'') && value[len(value)-1] == quote {
		unquoted, err := strconv.Unquote(value)
		if err == nil {
			return unquoted
		}
		return strings.Trim(value, string(quote))
	}
	return value
}

func splitLowerFields(value string) []string {
	fields := strings.Fields(value)
	out := make([]string, 0, len(fields))
	for _, field := range fields {
		out = append(out, strings.ToLower(field))
	}
	return out
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

func detectInit(goos string) string {
	if goos != "linux" {
		return "unknown"
	}
	if _, err := os.Stat("/run/systemd/system"); err == nil {
		return "systemd"
	}
	if _, err := os.Stat("/sbin/openrc"); err == nil {
		return "openrc"
	}
	return "unknown"
}
