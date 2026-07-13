// Waybar 状态栏配置。Waybar 支持 JSONC 注释，安装时会复制到 ~/.config/waybar/config。
// modules-left/center/right 控制模块在状态栏左中右的位置。
{
  "layer": "top",
  "position": "top",
  "height": 34,
  "modules-left": ["hyprland/workspaces", "hyprland/window"],
  "modules-center": ["clock"],
  "modules-right": ["network", "pulseaudio", "cpu", "memory", "tray"],
  // Hyprland 工作区模块：点击编号切换工作区。
  "hyprland/workspaces": { "format": "{id}", "on-click": "activate" },
  // 常用状态模块：时间、网络、音量、CPU、内存和系统托盘。
  "clock": { "format": "{:%Y-%m-%d %H:%M}" },
  "network": { "format-wifi": "  {essid}", "format-ethernet": "󰈀 有线", "format-disconnected": "󰖪 断开" },
  "pulseaudio": { "format": "  {volume}%", "format-muted": "󰖁 静音", "on-click": "pavucontrol" },
  "cpu": { "format": "CPU {usage}%" },
  "memory": { "format": "MEM {}%" },
  "tray": { "spacing": 10 }
}
