# ArchDevKit 生成的 Hyprland 主配置
# 没有壁纸时不会启动 hyprpaper。

$mod = SUPER
# ArchDevKit 会把下面这些占位符替换为 install_vars 中选择的软件。
# 常改项：$terminal 终端、$fileManager 文件管理器、$menu 应用启动器。
$terminal = __TERMINAL_APP__
$fileManager = __FILE_MANAGER__
$menu = __APP_LAUNCHER__ --show drun

# 显示器使用自动模式：优先采用屏幕推荐分辨率、自动排列、1 倍缩放。
monitor = ,preferred,auto,1

# Wayland/XWayland/输入法环境变量。fcitx5 相关变量用于中文输入法。
env = XCURSOR_SIZE,24
env = QT_QPA_PLATFORM,wayland;xcb
env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1
env = GDK_BACKEND,wayland,x11
env = MOZ_ENABLE_WAYLAND,1
env = GTK_IM_MODULE,fcitx
env = QT_IM_MODULE,fcitx
env = XMODIFIERS,@im=fcitx
env = INPUT_METHOD,fcitx
env = SDL_IM_MODULE,fcitx
env = GLFW_IM_MODULE,ibus

# 桌面启动项：状态栏、通知、输入法、网络/蓝牙托盘和提权认证代理。
exec-once = waybar
exec-once = mako
exec-once = fcitx5
exec-once = nm-applet --indicator
exec-once = blueman-applet
exec-once = /usr/lib/polkit-kde-authentication-agent-1

# 键盘、鼠标和触控板行为。
input {
    kb_layout = us
    follow_mouse = 1
    sensitivity = 0

    touchpad {
        natural_scroll = true
        tap-to-click = true
        disable_while_typing = true
    }
}

# 窗口间距、边框和默认布局。
general {
    gaps_in = 4
    gaps_out = 6
    border_size = 3
    layout = dwindle
    col.active_border = rgba(6272a4ff)
    col.inactive_border = rgba(282a36ff)
}

# 清晰优先：少圆角、无模糊、无阴影，避免文字和边界发糊。
decoration {
    rounding = 0
    shadow {
        enabled = false
        range = 12
        render_power = 3
        color = rgba(00000055)
    }
    blur {
        enabled = false
        size = 3
        passes = 1
        new_optimizations = true
    }
}

# 动画速度与曲线。
animations {
    enabled = true
    bezier = easeOut, 0.16, 1, 0.3, 1
    animation = windows, 1, 4, easeOut
    animation = windowsOut, 1, 4, easeOut
    animation = border, 1, 6, easeOut
    animation = fade, 1, 4, easeOut
    animation = workspaces, 1, 4, easeOut
}

dwindle {
    preserve_split = true
}

misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
}

debug {
    vfr = true
}

# 基础快捷键：SUPER+Return/T 打开终端，SUPER+Space 打开启动器。
bind = $mod, Return, exec, $terminal
bind = $mod, T, exec, $terminal
bind = $mod, Space, exec, $menu
bind = $mod, E, exec, $fileManager
bind = $mod, B, exec, __BROWSER_APP__
bind = $mod, Q, killactive
bind = $mod SHIFT, Q, exit
bind = $mod, F, fullscreen
bind = $mod, V, togglefloating

bind = $mod, Left, movefocus, l
bind = $mod, Right, movefocus, r
bind = $mod, Up, movefocus, u
bind = $mod, Down, movefocus, d

bind = $mod SHIFT, Left, movewindow, l
bind = $mod SHIFT, Right, movewindow, r
bind = $mod SHIFT, Up, movewindow, u
bind = $mod SHIFT, Down, movewindow, d

bind = $mod, 1, workspace, 1
bind = $mod, 2, workspace, 2
bind = $mod, 3, workspace, 3
bind = $mod, 4, workspace, 4
bind = $mod, 5, workspace, 5
bind = $mod, 6, workspace, 6
bind = $mod, 7, workspace, 7
bind = $mod, 8, workspace, 8
bind = $mod, 9, workspace, 9

bind = $mod SHIFT, 1, movetoworkspace, 1
bind = $mod SHIFT, 2, movetoworkspace, 2
bind = $mod SHIFT, 3, movetoworkspace, 3
bind = $mod SHIFT, 4, movetoworkspace, 4
bind = $mod SHIFT, 5, movetoworkspace, 5
bind = $mod SHIFT, 6, movetoworkspace, 6
bind = $mod SHIFT, 7, movetoworkspace, 7
bind = $mod SHIFT, 8, movetoworkspace, 8
bind = $mod SHIFT, 9, movetoworkspace, 9

bindm = $mod, mouse:272, movewindow
bindm = $mod, mouse:273, resizewindow

bind = , Print, exec, mkdir -p ~/Pictures && grim -g "$(slurp)" ~/Pictures/screenshot-$(date +%F-%H%M%S).png
bind = SHIFT, Print, exec, grim -g "$(slurp)" - | wl-copy

bind = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bind = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bind = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bind = , XF86MonBrightnessUp, exec, brightnessctl set +5%
bind = , XF86MonBrightnessDown, exec, brightnessctl set 5%-

windowrulev2 = float,class:^(pavucontrol)$
windowrulev2 = float,class:^(blueman-manager)$
windowrulev2 = float,class:^(nm-connection-editor)$
windowrulev2 = float,class:^(fcitx5-config-qt)$
