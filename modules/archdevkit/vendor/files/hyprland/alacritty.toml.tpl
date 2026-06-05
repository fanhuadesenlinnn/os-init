# ArchDevKit 精简环境的 Alacritty 终端配置模板。
# 会安装到 ~/.config/alacritty/alacritty.toml。
[env]
TERM = "xterm-256color"

# 窗口外观：padding 是内容边距，decorations=None 交给 Hyprland 管理边框。
[window]
padding = { x = 8, y = 8 }
decorations = "None"
opacity = 1.0

# 默认使用 Monaco，与系统 UI 字体保持一致；中文和 Emoji 由 fontconfig 回退到 Noto。
[font]
size = 12.5

[font.normal]
family = "Monaco"
style = "Regular"

[font.bold]
family = "Monaco"
style = "Regular"

[font.italic]
family = "Monaco"
style = "Regular"

[colors.primary]
background = "#242424"
foreground = "#F2F2F2"

[colors.cursor]
text = "#242424"
cursor = "#D9E0EE"

[colors.selection]
text = "#F2F2F2"
background = "#4B5263"

[colors.normal]
black = "#2E3440"
red = "#FF6B6B"
green = "#7DDB79"
yellow = "#FFD166"
blue = "#80BFFF"
magenta = "#C792EA"
cyan = "#5FD7D7"
white = "#D9E0EE"

[colors.bright]
black = "#5C6370"
red = "#FF8585"
green = "#95E88F"
yellow = "#FFE08A"
blue = "#9CCBFF"
magenta = "#DDB6FF"
cyan = "#7CEAEA"
white = "#FFFFFF"
