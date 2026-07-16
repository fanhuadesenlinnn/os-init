package main

import (
	"embed"
	"fmt"
	"os"
	"os/signal"
	"os/user"
	"strings"
	"syscall"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/fanhuadesenlinnn/os-init/internal/platform"
	"github.com/fanhuadesenlinnn/os-init/internal/state"
	"github.com/fanhuadesenlinnn/os-init/internal/tui"
)

//go:embed all:modules
var assets embed.FS

var (
	version = "1.3.2"
	commit  = "none"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, text("错误: %v\n", "Error: %v\n"), err)
		tui.RunCleanup()
		os.Exit(1)
	}
}

func run(args []string) error {
	normalizeRootHome(os.Geteuid(), user.LookupId)
	if len(args) > 0 {
		switch args[0] {
		case "-h", "--help", "help":
			fmt.Print(usageText())
			return nil
		case "-v", "--version", "version":
			fmt.Printf("os-init %s (%s)\n", version, commit)
			return nil
		case "--system-info":
			fmt.Print(systemInfoText(platform.Detect()))
			return nil
		case "module", "modules":
			return runModuleCommand(args[1:])
		default:
			return fmt.Errorf("%s\n\n%s", text("未知参数: ", "unknown argument: ")+args[0], usageText())
		}
	}

	m := tui.New(tui.Config{
		Assets:   assets,
		Version:  version,
		Commit:   commit,
		Recorder: state.Default(),
	})

	p := tea.NewProgram(m, tea.WithAltScreen())
	tui.SetProgram(p)

	// Handle SIGTERM for tmpdir cleanup
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM)
	go func() {
		<-sigCh
		// Route termination through the model so an active installer context is
		// canceled and its process group exits before temporary files are removed.
		p.Send(tea.KeyMsg{Type: tea.KeyCtrlC})
	}()

	if _, err := p.Run(); err != nil {
		return err
	}
	return nil
}

func normalizeRootHome(effectiveUID int, lookup func(string) (*user.User, error)) {
	if effectiveUID != 0 {
		return
	}
	root, err := lookup("0")
	if err != nil || root.HomeDir == "" {
		return
	}
	_ = os.Setenv("HOME", root.HomeDir)
}

func usageText() string {
	return text(`OS Init - macOS / Linux 交互式系统初始化工具

用法:
  os-init [选项]

不带选项时启动交互式界面。程序会根据当前系统显示可用模块，
并可在确认后执行安装、更新或卸载。

选项:
  -h, --help          显示帮助
  -v, --version       显示版本和提交信息
      --system-info   显示系统、发行版家族、虚拟环境和 init 检测结果

非交互命令:
  os-init module help
                      列出、规划、安装、验证或执行模块生命周期测试

常用示例:
  os-init                         启动中文交互界面
  OS_INIT_LANG=en_US os-init      启动英文交互界面
  os-init --system-info           查看平台检测结果
  os-init module list --format ids
                                  列出当前系统可用的稳定模块 ID

配置:
  ~/.config/os-init/config.env    用户配置

配置优先级:
  环境变量 > 用户配置 > 内置默认值

常用环境变量:
  OS_INIT_LANG                    zh_CN 或 en_US
  OS_INIT_CONFIG_PROMPT           设为 0 可关闭启动配置提示
  OS_INIT_SCRIPT_TIMEOUT          单个模块执行超时，例如 45m；0 表示不限制
  GITHUB_PROXY                    GitHub URL 代理（前缀或模板）

运行信息:
  日志保存在当前工作目录的 logs/ 下。需要系统权限的操作会在确认后请求 sudo。
`, `OS Init - interactive macOS / Linux system initialization

Usage:
  os-init [options]

With no options, OS Init starts its interactive interface. Available modules
are filtered for the current system and can be installed, updated, or removed
after confirmation.

Options:
  -h, --help          Show help
  -v, --version       Show version and commit information
      --system-info   Show detected OS, distribution family, virtual environment, and init system

Non-interactive:
  os-init module help
                      List, plan, install, verify, or lifecycle-test modules

Examples:
  os-init                         Start the interactive interface
  OS_INIT_LANG=en_US os-init      Start with English text
  os-init --system-info           Inspect platform detection
  os-init module list --format ids
                                  List stable module IDs for this system

Configuration:
  ~/.config/os-init/config.env    User configuration

Configuration precedence:
  environment > user configuration > built-in defaults

Common environment variables:
  OS_INIT_LANG                    zh_CN or en_US
  OS_INIT_CONFIG_PROMPT           Set to 0 to hide the startup config prompt
  OS_INIT_SCRIPT_TIMEOUT          Per-module timeout, for example 45m; 0 disables it
  GITHUB_PROXY                    GitHub URL proxy prefix or template

Runtime information:
  Logs are written under logs/ in the current working directory. Operations
  requiring system access request sudo after confirmation.
`)
}

func systemInfoText(target platform.Target) string {
	return fmt.Sprintf("goos=%s\nid=%s\nfamily=%s\nversion_id=%s\ninit=%s\nenvironment=%s\nwsl_version=%d\nwslg=%t\n",
		target.GOOS, target.ID, target.Family, target.VersionID, target.Init, target.Environment, target.WSLVersion, target.WSLg)
}

func text(zh, en string) string {
	if strings.HasPrefix(strings.ToLower(os.Getenv("OS_INIT_LANG")), "en") {
		return en
	}
	return zh
}
