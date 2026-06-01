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

const (
	FamilyDarwin  Family = "darwin"
	FamilyDebian  Family = "debian"
	FamilyRedHat  Family = "redhat"
	FamilyArch    Family = "arch"
	FamilyUnknown Family = "unknown"
)

type Target struct {
	GOOS      string
	ID        string
	IDLike    []string
	Family    Family
	VersionID string
	Codename  string
	Init      string
}

func Detect() Target {
	return DetectFrom(runtime.GOOS, "/etc/os-release")
}

func DetectFrom(goos, osReleasePath string) Target {
	target := Target{
		GOOS:   goos,
		Family: FamilyUnknown,
		Init:   detectInit(goos),
	}

	if goos == "darwin" {
		target.Family = FamilyDarwin
		return target
	}
	if goos != "linux" {
		return target
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
	case "rhel", "centos", "rocky", "almalinux", "fedora", "oracle", "oraclelinux", "ol":
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
