# OS Init TUI 演示
# 使用 VHS 录制: https://github.com/charmbracelet/vhs

Output demo.gif

Set Shell "bash"
Set FontSize 14
Set Width 1100
Set Height 500
Set Padding 20
Set Theme "Catppuccin Mocha"
Set TypingSpeed 50ms
Set Framerate 24

Type "./kickstart"
Sleep 400ms
Enter

# 等待菜单和更新检查
Sleep 4s

# 浏览菜单
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms
Down
Sleep 250ms

Sleep 1s

# 回到菜单顶部
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms
Up
Sleep 150ms

Sleep 500ms

# 选择第一个系统优化项
Space
Sleep 300ms

# 移动到 Shell 分组
Down
Sleep 200ms
Down
Sleep 200ms
Down
Sleep 200ms
Down
Sleep 200ms
Down
Sleep 200ms
Down
Sleep 200ms
Down
Sleep 200ms
Down
Sleep 200ms

# 选择 fzf
Space
Sleep 300ms

Sleep 500ms

# 演示过滤搜索
Type "/"
Sleep 300ms
Type "docker"
Sleep 1s
Escape
Sleep 500ms

# 使用 ctrl+a 全选
Ctrl+a
Sleep 1s

# 确认
Enter
Sleep 1s

# 选择安装模式
Enter
Sleep 1s

# 在确认页取消
Escape

Sleep 1s

# 退出
Type "q"
Sleep 500ms
