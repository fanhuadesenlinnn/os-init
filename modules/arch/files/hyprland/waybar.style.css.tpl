/* Waybar 外观样式：i3 Clear 风格，黑底、清晰文字、蓝色焦点。 */
* { font-family: "Noto Sans CJK SC", "JetBrainsMono Nerd Font", sans-serif; font-size: 14px; font-weight: 600; border: none; min-height: 0; }
window#waybar { background: #1c1c1c; color: #f8f8f2; }
/* 工作区按钮：active 表示当前工作区。 */
#workspaces button { padding: 0 10px; color: #969896; background: transparent; }
#workspaces button.active { color: #f8f8f2; border-bottom: 3px solid #81a2be; background: transparent; }
/* 这些模块共享水平内边距，避免状态栏过于拥挤。 */
#clock, #network, #pulseaudio, #cpu, #memory, #tray, #window { padding: 0 10px; }
#network { color: #57c7ff; }
#cpu { color: #50fa7b; }
#memory { color: #ff8247; }
