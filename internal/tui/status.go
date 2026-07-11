package tui

import "strings"

func statusInstalledWithVersion(version string) string {
	if version == "" {
		return statusInstalled()
	}
	return text("[已安装 "+version+"]", "[installed "+version+"]")
}

func statusInstalled() string {
	return text("[已安装]", "[installed]")
}

func statusUpdate(installed, latest string) string {
	return text("[可更新 "+installed+" → "+latest+"]", "[update available: "+installed+" → "+latest+"]")
}

func isInstalledStatus(status string) bool {
	return strings.HasPrefix(status, "[已安装") || strings.HasPrefix(status, "[installed")
}

func isUpdateStatus(status string) bool {
	return strings.HasPrefix(status, "[可更新") || strings.HasPrefix(status, "[update")
}
