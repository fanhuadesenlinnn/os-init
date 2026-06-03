#!/bin/bash
set -euo pipefail

# Install macOS GUI applications and fonts via Homebrew cask.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_DIR/lib.sh"

ALL_COMPONENTS=(
    google-chrome codex wechat royal-tsx
    orbstack visual-studio-code iterm2 ghostty sublime-text neovide-app
    clash-verge-rev clash-party seafile-client
    pixpin bob loop jordanbaird-ice stats monitorcontrol mos input-source-pro menubarx
    karabiner-elements aldente keka
    iina downie motrix spotify steam qqlive
    chatgpt cherry-studio siyuan
    telegram tencent-meeting wpsoffice bitwarden cleanmymac cc-switch
    font-hack-nerd-font font-jetbrains-mono-nerd-font font-maple-mono-nf
)
parse_update_flag "$@"
COMPONENTS=("${_CLEAN_ARGS[@]}")
if [[ ${#COMPONENTS[@]} -eq 0 ]]; then
    COMPONENTS=("${ALL_COMPONENTS[@]}")
fi

want() {
    local c
    for c in "${COMPONENTS[@]}"; do [[ "$c" == "$1" ]] && return 0; done
    return 1
}

known_component() {
    local c
    for c in "${ALL_COMPONENTS[@]}"; do [[ "$c" == "$1" ]] && return 0; done
    return 1
}

cask_label() {
    case "$1" in
        google-chrome) echo "Google Chrome" ;;
        codex) echo "Codex" ;;
        wechat) echo "微信" ;;
        royal-tsx) echo "Royal TSX" ;;
        orbstack) echo "OrbStack" ;;
        clash-verge-rev) echo "Clash Verge Rev" ;;
        clash-party) echo "Clash Party" ;;
        iterm2) echo "iTerm2" ;;
        visual-studio-code) echo "Visual Studio Code" ;;
        ghostty) echo "Ghostty" ;;
        sublime-text) echo "Sublime Text" ;;
        neovide-app) echo "Neovide" ;;
        seafile-client) echo "Seafile Client" ;;
        pixpin) echo "PixPin" ;;
        bob) echo "Bob" ;;
        loop) echo "Loop" ;;
        jordanbaird-ice) echo "Ice" ;;
        stats) echo "Stats" ;;
        monitorcontrol) echo "MonitorControl" ;;
        mos) echo "Mos" ;;
        input-source-pro) echo "Input Source Pro" ;;
        menubarx) echo "MenubarX" ;;
        karabiner-elements) echo "Karabiner-Elements" ;;
        aldente) echo "AlDente" ;;
        keka) echo "Keka" ;;
        iina) echo "IINA" ;;
        downie) echo "Downie 4" ;;
        motrix) echo "Motrix" ;;
        spotify) echo "Spotify" ;;
        steam) echo "Steam" ;;
        qqlive) echo "腾讯视频" ;;
        chatgpt) echo "ChatGPT" ;;
        cherry-studio) echo "Cherry Studio" ;;
        siyuan) echo "SiYuan" ;;
        telegram) echo "Telegram" ;;
        tencent-meeting) echo "腾讯会议" ;;
        wpsoffice) echo "WPS Office" ;;
        bitwarden) echo "Bitwarden" ;;
        cleanmymac) echo "CleanMyMac X" ;;
        cc-switch) echo "CC Switch" ;;
        font-hack-nerd-font) echo "Hack Nerd Font" ;;
        font-jetbrains-mono-nerd-font) echo "JetBrains Mono Nerd Font" ;;
        font-maple-mono-nf) echo "Maple Mono NF" ;;
        *) echo "$1" ;;
    esac
}

cask_app_path() {
    case "$1" in
        google-chrome) echo "/Applications/Google Chrome.app" ;;
        codex) echo "/Applications/Codex.app" ;;
        wechat) echo "/Applications/WeChat.app" ;;
        royal-tsx) echo "/Applications/Royal TSX.app" ;;
        orbstack) echo "/Applications/OrbStack.app" ;;
        clash-verge-rev) echo "/Applications/Clash Verge.app" ;;
        clash-party) echo "/Applications/Clash Party.app" ;;
        iterm2) echo "/Applications/iTerm.app" ;;
        visual-studio-code) echo "/Applications/Visual Studio Code.app" ;;
        ghostty) echo "/Applications/Ghostty.app" ;;
        sublime-text) echo "/Applications/Sublime Text.app" ;;
        neovide-app) echo "/Applications/Neovide.app" ;;
        seafile-client) echo "/Applications/Seafile Client.app" ;;
        pixpin) echo "/Applications/PixPin.app" ;;
        bob) echo "/Applications/Bob.app" ;;
        loop) echo "/Applications/Loop.app" ;;
        jordanbaird-ice) echo "/Applications/Ice.app" ;;
        stats) echo "/Applications/Stats.app" ;;
        monitorcontrol) echo "/Applications/MonitorControl.app" ;;
        mos) echo "/Applications/Mos.app" ;;
        input-source-pro) echo "/Applications/Input Source Pro.app" ;;
        menubarx) echo "/Applications/MenubarX.app" ;;
        karabiner-elements) echo "/Applications/Karabiner-Elements.app" ;;
        aldente) echo "/Applications/AlDente.app" ;;
        keka) echo "/Applications/Keka.app" ;;
        iina) echo "/Applications/IINA.app" ;;
        downie) echo "/Applications/Downie 4.app" ;;
        motrix) echo "/Applications/Motrix.app" ;;
        spotify) echo "/Applications/Spotify.app" ;;
        steam) echo "/Applications/Steam.app" ;;
        qqlive) echo "/Applications/QQLive.app" ;;
        chatgpt) echo "/Applications/ChatGPT.app" ;;
        cherry-studio) echo "/Applications/Cherry Studio.app" ;;
        siyuan) echo "/Applications/SiYuan.app" ;;
        telegram) echo "/Applications/Telegram.app" ;;
        tencent-meeting) echo "/Applications/TencentMeeting.app" ;;
        wpsoffice) echo "/Applications/wpsoffice.app" ;;
        bitwarden) echo "/Applications/Bitwarden.app" ;;
        cleanmymac) echo "/Applications/CleanMyMac-X.app" ;;
        cc-switch) echo "/Applications/CC Switch.app" ;;
        *) echo "" ;;
    esac
}

cask_installed() {
    local cask="$1" app_path
    brew list --cask "$cask" &>/dev/null && return 0
    app_path="$(cask_app_path "$cask")"
    [[ -n "$app_path" && -d "$app_path" ]]
}

install_cask() {
    local cask="$1" label
    label="$(cask_label "$cask")"
    if cask_installed "$cask"; then
        if [[ "$UPDATE" == true ]]; then
            update "更新 $label"
            brew upgrade --cask "$cask" 2>/dev/null || skip "$label 已是最新或由应用内更新器管理"
        else
            skip "$label 已安装"
        fi
    else
        install "安装 $label"
        brew install --cask "$cask"
    fi
}

uninstall_cask() {
    local cask="$1" label
    label="$(cask_label "$cask")"
    if cask_installed "$cask"; then
        remove "卸载 $label"
        brew uninstall --cask "$cask" 2>/dev/null || true
    else
        skip "$label 未安装"
    fi
}

require_macos
ensure_brew

for c in "${COMPONENTS[@]}"; do
    known_component "$c" || die "未知 macOS 应用组件: $c"
done

TITLE="安装"
[[ "$UPDATE" == true ]] && TITLE="更新"
[[ "$UNINSTALL" == true ]] && TITLE="卸载"
echo "=== macOS 应用 $TITLE ==="
echo "  Components: ${COMPONENTS[*]}"
echo ""

STEP=0
TOTAL=0
for c in "${ALL_COMPONENTS[@]}"; do
    want "$c" && TOTAL=$((TOTAL + 1))
done
next() { STEP=$((STEP + 1)); echo "[$STEP/$TOTAL] $1..."; }

for cask in "${ALL_COMPONENTS[@]}"; do
    want "$cask" || continue
    next "$(cask_label "$cask")"
    if [[ "$UNINSTALL" == true ]]; then
        uninstall_cask "$cask"
    else
        install_cask "$cask"
    fi
done

if want "orbstack" && [[ "$UNINSTALL" != true ]]; then
    echo ""
    echo "  提示: OrbStack 安装后需要打开应用完成首次初始化。"
fi

echo ""
echo "=== macOS 应用 $TITLE 完成 ==="
