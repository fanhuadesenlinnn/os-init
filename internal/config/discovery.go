package config

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

const (
	systemConfigPath = "/etc/os-init/config.env"
	embeddedExample  = "modules/config/config.env.example"
)

var summaryKeys = []string{
	"OS_INIT_LANG",
	"OS_INIT_PROXY",
	"HTTP_PROXY",
	"HTTPS_PROXY",
	"ALL_PROXY",
	"GITHUB_PROXY",
	"DOWNLOAD_URL_PROXY",
	"OS_INIT_OFFLINE",
	"OS_INIT_FILES_DIR",
}

type Discovery struct {
	SystemPath   string
	UserPath     string
	SystemExists bool
	UserExists   bool
	UserHome     string
}

type SummaryItem struct {
	Key   string
	Value string
}

func Discover() Discovery {
	home, _ := os.UserHomeDir()
	userPath := ""
	if home != "" {
		userPath = filepath.Join(home, ".config", "os-init", "config.env")
	}

	return Discovery{
		SystemPath:   systemConfigPath,
		UserPath:     userPath,
		SystemExists: fileExists(systemConfigPath),
		UserExists:   userPath != "" && fileExists(userPath),
		UserHome:     home,
	}
}

func (d Discovery) HasConfig() bool {
	return d.SystemExists || d.UserExists
}

func (d Discovery) ExistingPaths() []string {
	paths := make([]string, 0, 2)
	if d.SystemExists {
		paths = append(paths, d.SystemPath)
	}
	if d.UserExists {
		paths = append(paths, d.UserPath)
	}
	return paths
}

func CreateUserConfig(files fs.FS) (string, error) {
	info := Discover()
	if info.UserPath == "" {
		return "", fmt.Errorf("无法确定当前用户配置目录")
	}
	if info.UserExists {
		return info.UserPath, nil
	}
	if files == nil {
		return "", fmt.Errorf("缺少内置配置模板")
	}

	data, err := fs.ReadFile(files, embeddedExample)
	if err != nil {
		return "", fmt.Errorf("读取内置配置模板失败: %w", err)
	}

	dir := filepath.Dir(info.UserPath)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", fmt.Errorf("创建配置目录失败: %w", err)
	}

	tmp, err := os.CreateTemp(dir, ".config.env.*")
	if err != nil {
		return "", fmt.Errorf("创建临时配置失败: %w", err)
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)

	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return "", fmt.Errorf("写入临时配置失败: %w", err)
	}
	if err := tmp.Chmod(0o600); err != nil {
		_ = tmp.Close()
		return "", fmt.Errorf("设置配置权限失败: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return "", fmt.Errorf("关闭临时配置失败: %w", err)
	}
	if err := os.Rename(tmpPath, info.UserPath); err != nil {
		return "", fmt.Errorf("保存配置文件失败: %w", err)
	}

	return info.UserPath, nil
}

func StartupSummary() []SummaryItem {
	items := make([]SummaryItem, 0, len(summaryKeys))
	for _, key := range summaryKeys {
		value := os.Getenv(key)
		if value == "" {
			value = "未设置"
		}
		items = append(items, SummaryItem{Key: key, Value: value})
	}
	return items
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}
