#!/bin/bash
set -euo pipefail

# Install shell tooling: zsh, oh-my-zsh, starship, direnv, plugins, nvm, fnm, byobu, git
# Author: Dusan Panic <dpanic@gmail.com>
# Replicates a full zsh dev environment from scratch
# Safe to re-run -- idempotent (skips already-installed components)
#
# Usage:
#   ./install-shell-tools.sh              # install everything
#   ./install-shell-tools.sh zsh byobu    # install only listed components

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$REPO_DIR/lib.sh"

ALL_COMPONENTS=(zsh starship direnv plugins nvm fnm git)
is_linux && ALL_COMPONENTS+=(byobu)
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

login_shell_for_user() {
    local user="$1" shell=""
    if is_macos && command -v dscl &>/dev/null; then
        shell="$(dscl . -read "/Users/$user" UserShell 2>/dev/null | awk '{print $2}' || true)"
    elif command -v getent &>/dev/null; then
        shell="$(getent passwd "$user" | cut -d: -f7)"
    elif [[ -r /etc/passwd ]]; then
        shell="$(awk -F: -v user="$user" '$1 == user {print $7}' /etc/passwd)"
    fi
    echo "${shell:-${SHELL:-}}"
}

ensure_login_shell_allowed() {
    local shell_path="$1"
    [[ -f /etc/shells ]] || return 0
    if grep -qxF "$shell_path" /etc/shells; then
        return 0
    fi
    install "adding $shell_path to /etc/shells"
    printf '%s\n' "$shell_path" | sudo tee -a /etc/shells >/dev/null
}

set_default_zsh() {
    local shell_path user current_shell
    shell_path="$(command -v zsh)"
    user="$(real_user)"
    current_shell="$(login_shell_for_user "$user")"

    if [[ "$(basename "${current_shell:-}")" == "zsh" ]]; then
        skip "zsh is already the default shell"
        return
    fi

    ensure_login_shell_allowed "$shell_path"
    install "setting zsh as default shell for $user"
    if ! sudo chsh -s "$shell_path" "$user"; then
        die "无法非交互式切换默认 shell，请确认 sudo 验证成功且 $shell_path 已写入 /etc/shells"
    fi
}

nvm_version() {
    local version="${NVM_VERSION:-}"
    [[ -n "$version" ]] || version="$(github_latest_version "nvm-sh/nvm" "")"
    echo "$version"
}

nvm_install_url() {
    local version="$1"
    resource_url NVM_INSTALL_URL "${NVM_INSTALL_BASE%/}/${version}/install.sh"
}

STEP=0
count_steps() {
    local total=0
    for c in "${ALL_COMPONENTS[@]}"; do want "$c" && total=$((total + 1)); done
    echo "$total"
}
TOTAL=$(count_steps)
next() { STEP=$((STEP + 1)); echo "[$STEP/$TOTAL] $1..."; }

TITLE="$(os_init_text "安装" "setup")"
[[ "$UNINSTALL" == true ]] && TITLE="$(os_init_text "卸载" "uninstall")"
echo "=== $(os_init_text "Shell 工具" "Shell Tools") $TITLE ==="
echo "  $(os_init_text "组件" "Components"): ${COMPONENTS[*]}"
echo ""

# ── Uninstall mode ────────────────────────────────────────────────────────────
if [[ "$UNINSTALL" == true ]]; then
    ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

    if want "plugins"; then
        echo "[REMOVE] zsh plugins..."
        [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] && \
            { remove "zsh-autosuggestions"; rm -rf "$ZSH_CUSTOM/plugins/zsh-autosuggestions"; } || skip "zsh-autosuggestions not found"
        [[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] && \
            { remove "zsh-syntax-highlighting"; rm -rf "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"; } || skip "zsh-syntax-highlighting not found"
    fi

    if want "nvm"; then
        echo "[REMOVE] nvm..."
        if [[ -d "$HOME/.nvm" ]]; then
            remove "removing ~/.nvm"
            rm -rf "$HOME/.nvm"
        else
            skip "nvm not installed"
        fi
    fi

    if want "fnm"; then
        echo "[REMOVE] fnm..."
        if command -v fnm &>/dev/null; then
            remove "removing fnm"
            rm -f "$(command -v fnm)"
            rm -rf "$HOME/.local/share/fnm" "$HOME/.fnm"
        else
            skip "fnm not installed"
        fi
    fi

    if want "starship"; then
        echo "$(os_init_text "[删除]" "[REMOVE]") starship..."
        if command -v starship &>/dev/null; then
            if is_macos; then
                remove "通过 Homebrew 卸载 starship"
                pkg_remove starship
            else
                remove "removing starship binary"
                sudo rm -f "$(command -v starship)"
            fi
        else
            skip "starship not installed"
        fi
    fi

    if want "direnv"; then
        echo "[REMOVE] direnv..."
        if command -v direnv &>/dev/null; then
            remove "removing direnv"
            pkg_remove "${DIRENV_PACKAGE:-direnv}" 2>/dev/null || true
        else
            skip "direnv not installed"
        fi
    fi

    if want "git"; then
        echo "[REMOVE] git-lfs..."
        if command -v git-lfs &>/dev/null; then
            remove "removing git-lfs"
            pkg_remove git-lfs 2>/dev/null || true
        else
            skip "git-lfs not installed"
        fi
    fi

    if want "byobu"; then
        echo "[REMOVE] byobu..."
        if command -v byobu &>/dev/null; then
            remove "removing byobu"
            pkg_remove byobu 2>/dev/null || true
            [[ -d "$HOME/.byobu" ]] && { remove "removing ~/.byobu"; rm -rf "$HOME/.byobu"; }
        else
            skip "byobu not installed"
        fi
    fi

    if want "zsh"; then
        echo "[REMOVE] oh-my-zsh..."
        if [[ -d "$HOME/.oh-my-zsh" ]]; then
            remove "removing ~/.oh-my-zsh"
            rm -rf "$HOME/.oh-my-zsh"
        else
            skip "oh-my-zsh not installed"
        fi
        echo "  note: zsh package and default shell left intact"
    fi

    echo ""
    echo "=== $(os_init_text "Shell 工具卸载完成" "Shell tools uninstall complete") ==="
    exit 0
fi

# ── zsh + oh-my-zsh ──────────────────────────────────────────────────────────
if want "zsh"; then
    next "zsh + oh-my-zsh"

    if command -v zsh &>/dev/null; then
        skip "zsh $(zsh --version | head -1) already installed"
    else
        install "installing zsh"
        pkg_install zsh
    fi

    set_default_zsh

    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        if [[ "$UPDATE" == true ]]; then
            update "updating oh-my-zsh"
            git_update_shallow "$HOME/.oh-my-zsh"
        else
            skip "oh-my-zsh already installed at ~/.oh-my-zsh"
        fi
    else
        install "cloning oh-my-zsh"
        git_clone_depth 1 "$(repo_url OH_MY_ZSH_REPO "https://github.com/ohmyzsh/ohmyzsh.git")" "$HOME/.oh-my-zsh"
    fi
fi

# ── starship ──────────────────────────────────────────────────────────────────
if want "starship"; then
    next "starship"

    if is_macos; then
        ensure_brew
        if command -v starship &>/dev/null; then
            if [[ "$UPDATE" == true ]]; then
                update "通过 Homebrew 更新 starship"
                brew upgrade starship || true
            else
                skip "starship $(starship --version | head -1) already installed"
            fi
        else
            install "通过 Homebrew 安装 starship"
            brew install starship
        fi
    elif command -v starship &>/dev/null; then
        if [[ "$UPDATE" == true ]]; then
            update "updating starship"
            STARSHIP_INSTALLER="$(mktemp "${TMPDIR:-/tmp}/starship-install.XXXXXX")"
            download_file "$(resource_url STARSHIP_INSTALL_URL "https://starship.rs/install.sh")" "$STARSHIP_INSTALLER"
            sh "$STARSHIP_INSTALLER" -y
            rm -f "$STARSHIP_INSTALLER"
        else
            skip "starship $(starship --version | head -1) already installed"
        fi
    else
        install "installing starship"
        STARSHIP_INSTALLER="$(mktemp "${TMPDIR:-/tmp}/starship-install.XXXXXX")"
        download_file "$(resource_url STARSHIP_INSTALL_URL "https://starship.rs/install.sh")" "$STARSHIP_INSTALLER"
        sh "$STARSHIP_INSTALLER" -y
        rm -f "$STARSHIP_INSTALLER"
    fi

    mkdir -p "$HOME/.config"
    if [[ -f "$HOME/.config/starship.toml" ]]; then
        skip "~/.config/starship.toml already exists (not overwriting)"
    else
        install "$(os_init_text "复制 starship.toml" "copying starship.toml")"
        cp "$SCRIPT_DIR/starship.toml" "$HOME/.config/starship.toml"
    fi
fi

# ── direnv ────────────────────────────────────────────────────────────────────
if want "direnv"; then
    next "direnv"

    if command -v direnv &>/dev/null; then
        skip "direnv $(direnv version) already installed"
    else
        install "installing direnv"
        pkg_install "${DIRENV_PACKAGE:-direnv}"
    fi
fi

# ── zsh plugins ───────────────────────────────────────────────────────────────
if want "plugins"; then
    next "zsh plugins"

    ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

    if [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
        if [[ "$UPDATE" == true ]]; then
            update "updating zsh-autosuggestions"
            git_update_shallow "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
        else
            skip "zsh-autosuggestions already installed"
        fi
    else
        install "cloning zsh-autosuggestions"
        git_clone_depth 1 "$(repo_url ZSH_AUTOSUGGESTIONS_REPO "https://github.com/zsh-users/zsh-autosuggestions.git")" \
            "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    fi

    if [[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
        if [[ "$UPDATE" == true ]]; then
            update "updating zsh-syntax-highlighting"
            git_update_shallow "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
        else
            skip "zsh-syntax-highlighting already installed"
        fi
    else
        install "cloning zsh-syntax-highlighting"
        git_clone_depth 1 "$(repo_url ZSH_SYNTAX_HIGHLIGHTING_REPO "https://github.com/zsh-users/zsh-syntax-highlighting.git")" \
            "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    fi
fi

# ── nvm ───────────────────────────────────────────────────────────────────────
if want "nvm"; then
    next "nvm"

    if [[ -d "$HOME/.nvm" ]]; then
        if [[ "$UPDATE" == true ]]; then
            update "updating nvm to latest"
            LATEST_NVM="$(nvm_version)"
            git_with_proxy -C "$HOME/.nvm" fetch origin --depth=1 --tags -q
            git_with_proxy -C "$HOME/.nvm" checkout "$LATEST_NVM" 2>/dev/null
        else
            skip "nvm already installed at ~/.nvm"
        fi
    else
        install "installing nvm"
        LATEST_NVM="$(nvm_version)"
        NVM_INSTALLER="$(mktemp "${TMPDIR:-/tmp}/nvm-install.XXXXXX")"
        download_file "$(nvm_install_url "$LATEST_NVM")" "$NVM_INSTALLER"
        if want "zsh"; then
            PROFILE=/dev/null bash "$NVM_INSTALLER"
        else
            bash "$NVM_INSTALLER"
        fi
        rm -f "$NVM_INSTALLER"
    fi
fi

# ── fnm ──────────────────────────────────────────────────────────────────────
if want "fnm"; then
    next "fnm"

    FNM_SKIP=(); want "zsh" && FNM_SKIP=(--skip-shell)

    if command -v fnm &>/dev/null; then
        if [[ "$UPDATE" == true ]]; then
            update "updating fnm"
            FNM_INSTALLER="$(mktemp "${TMPDIR:-/tmp}/fnm-install.XXXXXX")"
            download_file "$(resource_url FNM_INSTALL_URL "https://fnm.vercel.app/install")" "$FNM_INSTALLER"
            bash "$FNM_INSTALLER" "${FNM_SKIP[@]}"
            rm -f "$FNM_INSTALLER"
        else
            skip "fnm $(fnm --version 2>/dev/null) already installed"
        fi
    else
        install "installing fnm"
        if ! command -v unzip &>/dev/null; then
            pkg_install unzip
        fi
        FNM_INSTALLER="$(mktemp "${TMPDIR:-/tmp}/fnm-install.XXXXXX")"
        download_file "$(resource_url FNM_INSTALL_URL "https://fnm.vercel.app/install")" "$FNM_INSTALLER"
        bash "$FNM_INSTALLER" "${FNM_SKIP[@]}"
        rm -f "$FNM_INSTALLER"
    fi
fi

# ── byobu + tmux ──────────────────────────────────────────────────────────────
if want "byobu"; then
    next "byobu + tmux"
    require_linux

    PKGS=()
    if command -v byobu &>/dev/null; then
        skip "byobu already installed"
    else
        PKGS+=(byobu)
    fi

    if command -v tmux &>/dev/null; then
        skip "tmux $(tmux -V) already installed"
    else
        PKGS+=(tmux)
    fi

    if [[ ${#PKGS[@]} -gt 0 ]]; then
        install "installing ${PKGS[*]}"
        pkg_install "${PKGS[@]}"
    fi

    BYOBU_DIR="$HOME/.byobu"
    BYOBU_CONFIGS=(".tmux.conf" ".ctrl-a-workaround" "backend" "color.tmux" "datetime.tmux" "keybindings" "keybindings.tmux" "status")

    if [[ -d "$BYOBU_DIR" ]]; then
        local_changed=0
        for cfg in "${BYOBU_CONFIGS[@]}"; do
            src="$SCRIPT_DIR/byobu/$cfg"
            dst="$BYOBU_DIR/$cfg"
            if [[ ! -f "$src" ]]; then
                continue
            fi
            if [[ -f "$dst" ]] && diff -q "$src" "$dst" &>/dev/null; then
                continue
            fi
            if [[ -f "$dst" ]]; then
                install "updating $cfg (old backed up to ${cfg}.bak)"
                cp "$dst" "${dst}.bak"
            else
                install "copying $cfg"
            fi
            cp "$src" "$dst"
            local_changed=$((local_changed + 1))
        done
        if [[ $local_changed -eq 0 ]]; then
            skip "byobu config already up to date"
        fi
    else
        install "creating ~/.byobu/ with configs"
        mkdir -p "$BYOBU_DIR"
        for cfg in "${BYOBU_CONFIGS[@]}"; do
            src="$SCRIPT_DIR/byobu/$cfg"
            [[ -f "$src" ]] && cp "$src" "$BYOBU_DIR/$cfg"
        done
    fi

    if [[ -f "$BYOBU_DIR/backend" ]] && grep -q "tmux" "$BYOBU_DIR/backend"; then
        skip "byobu backend already set to tmux"
    else
        install "setting byobu backend to tmux"
        echo "BYOBU_BACKEND=tmux" > "$BYOBU_DIR/backend"
    fi
fi

# ── git config ────────────────────────────────────────────────────────────────
if want "git"; then
    next "git config"

    if [[ -f "$HOME/.gitconfig" ]]; then
        skip "~/.gitconfig already exists (not overwriting)"
        echo "  Review template: $SCRIPT_DIR/gitconfig.template"
    else
        install "copying gitconfig.template -> ~/.gitconfig"
        cp "$SCRIPT_DIR/gitconfig.template" "$HOME/.gitconfig"
    fi

    if [[ -n "${KICKSTART_USER_NAME:-}" ]]; then
        git config --global user.name "$KICKSTART_USER_NAME"
        echo "  git user.name = $KICKSTART_USER_NAME"
    fi
    if [[ -n "${KICKSTART_USER_EMAIL:-}" ]]; then
        git config --global user.email "$KICKSTART_USER_EMAIL"
        echo "  git user.email = $KICKSTART_USER_EMAIL"
    fi
    if [[ -z "${KICKSTART_USER_NAME:-}" && -z "${KICKSTART_USER_EMAIL:-}" ]]; then
        current_name=$(git config --global user.name 2>/dev/null || true)
        if [[ "$current_name" == "CHANGEME" || -z "$current_name" ]]; then
            echo ""
            echo "  IMPORTANT: set your git identity:"
            echo '    git config --global user.name "Your Name"'
            echo '    git config --global user.email "your@email.com"'
        fi
    fi

    if command -v git-lfs &>/dev/null; then
        skip "git-lfs already installed"
    else
        install "installing git-lfs"
        pkg_install git-lfs
        git lfs install
    fi
fi

# ── .zshrc template ──────────────────────────────────────────────────────────
if want "zsh"; then
    if [[ -f "$HOME/.zshrc" ]]; then
        skip "~/.zshrc already exists (not overwriting)"
        echo ""
        echo "  To see what the template includes, run:"
        echo "    diff ~/.zshrc $SCRIPT_DIR/zshrc.template"
        echo ""
        echo "  Key lines to ensure are in your .zshrc:"
        echo "    plugins=(git zsh-autosuggestions zsh-syntax-highlighting)"
        echo '    eval "$(starship init zsh)"'
        echo '    eval "$(direnv hook zsh)"'
    else
        install "copying zshrc.template -> ~/.zshrc"
        cp "$SCRIPT_DIR/zshrc.template" "$HOME/.zshrc"
    fi
fi

echo ""
echo "=== $(os_init_text "Shell 工具安装完成" "Shell tools setup complete") ==="
echo "  $(os_init_text "已处理" "Processed"): ${COMPONENTS[*]}"
echo ""
want "byobu" && echo "  byobu  -- $(os_init_text "启动终端复用器" "launch terminal multiplexer")"
want "fnm" && echo "  fnm   -- fnm install --lts && fnm use lts-latest"
echo "$(os_init_text "打开新终端或执行: exec zsh" "Start a new terminal or run: exec zsh")"
