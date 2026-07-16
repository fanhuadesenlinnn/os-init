package modules

type macOSCaskCatalogItem struct {
	subsection, token, label, description, path string
}

type macOSFormulaCatalogItem struct {
	formula, label, description, command string
}

var macOSCaskCatalog = []macOSCaskCatalogItem{
	{"macOS 开发应用", "google-chrome", "Google Chrome", "浏览器", "/Applications/Google Chrome.app"},
	{"macOS 开发应用", "codex", "Codex", "OpenAI Codex 桌面端", "/Applications/Codex.app"},
	{"macOS 开发应用", "orbstack", "OrbStack", "Docker Desktop 替代、容器和 Linux 机器", "/Applications/OrbStack.app"},
	{"macOS 开发应用", "visual-studio-code", "Visual Studio Code", "代码编辑器", "/Applications/Visual Studio Code.app"},
	{"macOS 开发应用", "iterm2", "iTerm2", "macOS 终端模拟器", "/Applications/iTerm.app"},
	{"macOS 开发应用", "ghostty", "Ghostty", "GPU 加速终端模拟器", "/Applications/Ghostty.app"},
	{"macOS 开发应用", "sublime-text", "Sublime Text", "轻量代码编辑器", "/Applications/Sublime Text.app"},
	{"macOS 代理网络", "clash-party", "Clash Party", "Mihomo/Clash 代理 GUI", "/Applications/Clash Party.app"},
	{"macOS 代理网络", "royal-tsx", "Royal TSX", "远程连接管理器", "/Applications/Royal TSX.app"},
	{"macOS 代理网络", "seafile-client", "Seafile Client", "文件同步客户端", "/Applications/Seafile Client.app"},
	{"macOS 效率工具", "pixpin", "PixPin", "截图和标注工具", "/Applications/PixPin.app"},
	{"macOS 效率工具", "bob", "Bob", "翻译和 OCR 工具", "/Applications/Bob.app"},
	{"macOS 效率工具", "loop", "Loop", "窗口管理工具", "/Applications/Loop.app"},
	{"macOS 效率工具", "jordanbaird-ice", "Ice", "菜单栏管理工具", "/Applications/Ice.app"},
	{"macOS 效率工具", "stats", "Stats", "菜单栏系统监控", "/Applications/Stats.app"},
	{"macOS 效率工具", "monitorcontrol", "MonitorControl", "外接显示器亮度和音量控制", "/Applications/MonitorControl.app"},
	{"macOS 效率工具", "mos", "Mos", "鼠标滚动优化", "/Applications/Mos.app"},
	{"macOS 效率工具", "input-source-pro", "Input Source Pro", "输入法自动切换", "/Applications/Input Source Pro.app"},
	{"macOS 效率工具", "menubarx", "MenubarX", "菜单栏浏览器", "/Applications/MenubarX.app"},
	{"macOS 输入增强", "karabiner-elements", "Karabiner-Elements", "键盘映射工具，自动部署 Caps Lock/Control 和 Shift 输入法切换配置", "/Applications/Karabiner-Elements.app"},
	{"macOS 输入增强", "squirrel-app", "Squirrel", "Rime 中文输入法", "/Library/Input Methods/Squirrel.app"},
	{"macOS 输入增强", "aldente", "AlDente", "电池充电管理", "/Applications/AlDente.app"},
	{"macOS 输入增强", "keka", "Keka", "压缩解压工具", "/Applications/Keka.app"},
	{"macOS 媒体下载", "iina", "IINA", "视频播放器", "/Applications/IINA.app"},
	{"macOS 媒体下载", "downie", "Downie 4", "视频下载工具", "/Applications/Downie 4.app"},
	{"macOS 媒体下载", "motrix-next", "Motrix Next", "现代化下载管理器", "/Applications/MotrixNext.app"},
	{"macOS 媒体下载", "spotify", "Spotify", "音乐客户端", "/Applications/Spotify.app"},
	{"macOS 媒体下载", "steam", "Steam", "游戏平台", "/Applications/Steam.app"},
	{"macOS 媒体下载", "qqlive", "腾讯视频", "视频客户端", "/Applications/QQLive.app"},
	{"macOS AI 笔记", "chatgpt", "ChatGPT", "ChatGPT 桌面端", "/Applications/ChatGPT.app"},
	{"macOS AI 笔记", "lm-studio", "LM Studio", "本地大语言模型运行与管理", "/Applications/LM Studio.app"},
	{"macOS AI 笔记", "cherry-studio", "Cherry Studio", "AI 客户端", "/Applications/Cherry Studio.app"},
	{"macOS AI 笔记", "siyuan", "SiYuan", "本地优先笔记工具", "/Applications/SiYuan.app"},
	{"macOS 通讯办公", "wechat", "微信", "即时通讯", "/Applications/WeChat.app"},
	{"macOS 通讯办公", "telegram", "Telegram", "即时通讯", "/Applications/Telegram.app"},
	{"macOS 通讯办公", "tencent-meeting", "腾讯会议", "会议客户端", "/Applications/TencentMeeting.app"},
	{"macOS 通讯办公", "wpsoffice", "WPS Office", "办公套件", "/Applications/wpsoffice.app"},
	{"macOS 通讯办公", "bitwarden", "Bitwarden", "密码管理器", "/Applications/Bitwarden.app"},
	{"macOS 通讯办公", "cleanmymac", "CleanMyMac X", "系统清理工具", "/Applications/CleanMyMac-X.app"},
	{"macOS 通讯办公", "cc-switch", "CC Switch", "菜单栏开关工具", "/Applications/CC Switch.app"},
	{"macOS 字体", "font-hack-nerd-font", "Hack Nerd Font", "Nerd Font 字体", ""},
	{"macOS 字体", "font-jetbrains-mono-nerd-font", "JetBrains Mono Nerd Font", "Nerd Font 字体", ""},
	{"macOS 字体", "font-maple-mono-nf", "Maple Mono NF", "Nerd Font 字体", ""},
}

var macOSFormulaCatalog = []macOSFormulaCatalogItem{
	{"bat", "bat", "cat 替代工具", "bat"}, {"eza", "eza", "ls 替代工具", "eza"},
	{"ripgrep", "ripgrep", "高速文本搜索", "rg"}, {"fd", "fd", "find 替代工具", "fd"},
	{"fzf", "fzf", "命令行模糊查找", "fzf"}, {"gh", "GitHub CLI", "GitHub 命令行工具", "gh"},
	{"htop", "htop", "进程监控", "htop"}, {"iftop", "iftop", "网络流量监控", "iftop"},
	{"jq", "jq", "JSON 处理工具", "jq"}, {"nmap", "nmap", "网络扫描工具", "nmap"},
	{"nushell", "Nushell", "结构化 shell", "nu"}, {"rsync", "rsync", "文件同步工具", ""},
	{"shellcheck", "ShellCheck", "Shell 静态检查", "shellcheck"}, {"tmux", "tmux", "终端复用器", "tmux"},
	{"uv", "uv", "Python 包和项目管理", "uv"}, {"wget", "wget", "命令行下载工具", "wget"},
	{"zoxide", "zoxide", "智能目录跳转", "zoxide"}, {"ffmpeg", "FFmpeg", "音视频处理", "ffmpeg"},
	{"imagemagick", "ImageMagick", "图片处理", "magick"}, {"gallery-dl", "gallery-dl", "图库下载工具", "gallery-dl"},
	{"yt-dlp", "yt-dlp", "视频下载工具", "yt-dlp"}, {"stylua", "StyLua", "Lua 格式化工具", "stylua"},
	{"tree-sitter-cli", "tree-sitter CLI", "tree-sitter 命令行工具", "tree-sitter"}, {"nload", "nload", "网络流量监控", "nload"},
	{"bind", "BIND DNS tools", "DNS 工具集", ""}, {"herdr", "herdr", "命令行工具", "herdr"},
	{"llmfit", "llmfit", "命令行工具", "llmfit"},
}

func macOSCatalogModules() []Module {
	modules := make([]Module, 0, len(macOSCaskCatalog)+len(macOSFormulaCatalog))
	for _, item := range macOSCaskCatalog {
		modules = append(modules, macOSCask(item.subsection, item.token, item.label, item.description, item.path))
	}
	for _, item := range macOSFormulaCatalog {
		modules = append(modules, macOSFormula(item.formula, item.label, item.description, item.command))
	}
	return modules
}
