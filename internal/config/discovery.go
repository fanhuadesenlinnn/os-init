package config

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/fanhuadesenlinnn/os-init/internal/platform"
)

var summaryKeys = []string{
	"OS_INIT_LANG",
	"GITHUB_PROXY",
	"OS_INIT_SCRIPT_TIMEOUT",
}

type Discovery struct {
	UserPath   string
	UserExists bool
	UserHome   string
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
		UserPath:   userPath,
		UserExists: userPath != "" && fileExists(userPath),
		UserHome:   home,
	}
}

func (d Discovery) HasConfig() bool {
	return d.UserExists
}

func CreateUserConfig(files fs.FS, target platform.Target, lang string) (string, error) {
	return createUserConfig(files, target, lang)
}

func createUserConfig(files fs.FS, target platform.Target, lang string) (string, error) {
	_ = files
	info := Discover()
	if info.UserPath == "" {
		return "", fmt.Errorf("无法确定当前用户配置目录")
	}
	if info.UserExists {
		return info.UserPath, nil
	}
	data := renderUserConfig(target, lang)

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
