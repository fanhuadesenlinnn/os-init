package tui

import "strings"

const (
	statusInstalled = "[已安装]"
	statusUpdate    = "[可更新 %s → %s]"
)

func statusInstalledWithVersion(version string) string {
	if version == "" {
		return statusInstalled
	}
	return "[已安装 " + version + "]"
}

func isInstalledStatus(status string) bool {
	return strings.HasPrefix(status, "[已安装")
}

func isUpdateStatus(status string) bool {
	return strings.HasPrefix(status, "[可更新")
}
