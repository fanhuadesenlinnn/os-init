# Hyprdots Vendor Notes

- Source: https://github.com/fanhuadesenlinnn/hyprdots.git
- Commit: 0158219
- Imported for the OS Init Arch Hyprland desktop module.

This directory keeps only the desktop-related config modules used by
`modules/desktop_hyprland.sh`. Shell, Neovim, Git, screenshots, and other
unrelated dotfile areas stay out of the desktop module boundary.

Local adjustments:

- The upstream Hyprland config used an optional `scrolling` layout. OS Init Arch
  defaults it to `dwindle` so a stock Hyprland install can start without extra
  layout plugins.
- Terminal integration is normalized to Alacritty with foot as the fallback;
  Kitty-specific config from upstream is intentionally not vendored.
- `waybar/scripts/toggle-brightness.sh` stores state under
  `${XDG_STATE_HOME:-$HOME/.local/state}` instead of `/etc/xdg`.
- The upstream Waybar GitHub contribution widget is removed because OS Init Arch
  should not require GitHub tokens for a default desktop status bar.
- Personal web-app launchers, Steam/YouTube helpers, old Waybar variants,
  unused Rofi menus, Cava, and Fastfetch are trimmed to keep only useful
  desktop configuration in the default install.
- The unused Hyprland Lua entrypoint/modules and Hyprvim sample settings are
  removed; OS Init Arch installs and renders `hyprland.conf` only.
