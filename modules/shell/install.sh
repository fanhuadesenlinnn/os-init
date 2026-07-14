#!/bin/bash
set -euo pipefail

# Install shell tooling: zsh, oh-my-zsh, bundled zsh plugins, direnv, byobu, git
# Author: Dusan Panic <dpanic@gmail.com>
# Replicates a full zsh dev environment from scratch
# Safe to re-run -- idempotent (skips already-installed components)
#
# Usage:
#   ./install-shell-tools.sh              # install everything
#   ./install-shell-tools.sh zsh byobu    # install only listed components

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$REPO_DIR/lib.sh"

SUPPORTED_COMPONENTS=(zsh direnv git byobu)
ALL_COMPONENTS=(zsh direnv git)
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

validate_components() {
    local c
    for c in "${COMPONENTS[@]}"; do
        local supported=false supported_component
        for supported_component in "${SUPPORTED_COMPONENTS[@]}"; do
            [[ "$c" == "$supported_component" ]] && supported=true && break
        done
        [[ "$supported" == true ]] || die "$(os_init_text "未知 Shell 组件: $c" "unknown shell component: $c")"
    done
}
validate_components

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
	os_init_mark_ownership "zsh-etc-shells-entry"
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
	if ! os_init_user_owned "original-login-shell"; then
		mkdir -p "$(os_init_user_state_dir)/values"
		printf '%s\n' "$current_shell" > "$(os_init_user_state_dir)/values/original-login-shell"
		os_init_mark_user_ownership "original-login-shell"
	fi
    install "setting zsh as default shell for $user"
    if ! sudo chsh -s "$shell_path" "$user"; then
        die "无法非交互式切换默认 shell，请确认 sudo 验证成功且 $shell_path 已写入 /etc/shells"
    fi
}

ensure_macos_oh_my_zsh_commands() {
    is_macos || return 0

    local command_name package ownership_key
    for command_name in git fzf kubectl; do
        command -v "$command_name" &>/dev/null && continue
        package="$command_name"
        ownership_key="shell-dependency-${command_name}"
        [[ "$command_name" == "fzf" ]] && ownership_key="macos-formula-fzf"
        install "$(os_init_text "通过 Homebrew 安装 Oh My Zsh 依赖: $package" "installing Oh My Zsh dependency with Homebrew: $package")"
        brew_install "$package"
        os_init_mark_user_ownership "$ownership_key"
    done

    if ! command -v docker &>/dev/null; then
		if brew_list --cask orbstack &>/dev/null || [[ -d "/Applications/OrbStack.app" ]]; then
			skip "OrbStack 已安装"
		else
			install "$(os_init_text "未检测到 docker，安装 OrbStack" "docker was not found; installing OrbStack")"
			brew_install orbstack
			os_init_mark_user_ownership "macos-cask-orbstack"
		fi
        warn "$(os_init_text "请打开 OrbStack 完成首次初始化，随后 docker 命令才会可用" "open OrbStack to finish first-time initialization before using the docker command")"
    fi
}

ensure_zsh_package() {
    if command -v zsh &>/dev/null; then
        skip "zsh $(zsh --version | head -1) already installed"
    else
        install "installing zsh"
        pkg_install zsh
    fi
}

ensure_oh_my_zsh() {
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        if [[ "$UPDATE" == true ]]; then
            update "updating oh-my-zsh"
            git_update_shallow "$HOME/.oh-my-zsh"
        else
            skip "oh-my-zsh already installed at ~/.oh-my-zsh"
        fi
	else
		install "$(os_init_text "通过官方安装脚本安装 Oh My Zsh" "installing Oh My Zsh with the official installer")"
		RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
		touch "$HOME/.oh-my-zsh/.os-init-owned"
	fi
}

ensure_powerlevel10k() {
    local theme_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    mkdir -p "$(dirname "$theme_dir")"
    if [[ -d "$theme_dir/.git" ]]; then
        if [[ "$UPDATE" == true ]]; then
            update "updating Powerlevel10k"
            git_update_shallow "$theme_dir"
        else
            skip "Powerlevel10k already installed"
        fi
    elif [[ -e "$theme_dir" ]]; then
        warn "保留现有非 Git Powerlevel10k 目录: $theme_dir"
    else
        install "cloning Powerlevel10k"
        git_clone_depth 1 "https://github.com/romkatv/powerlevel10k.git" "$theme_dir"
        touch "$theme_dir/.os-init-owned"
    fi
}

has_oh_my_zsh_source_outside_os_init_block() {
    local file
    file="$(os_init_zshrc)" || return 1
    [[ -f "$file" ]] || return 1
    awk '
        $0 == "# >>> os-init oh-my-zsh >>>" { in_block = 1; next }
        $0 == "# <<< os-init oh-my-zsh <<<" { in_block = 0; next }
        !in_block && $0 ~ /oh-my-zsh\.sh/ { found = 1 }
        END { exit(found ? 0 : 1) }
    ' "$file"
}

configure_oh_my_zsh() {
    local content before_regex source_line="" theme="powerlevel10k/powerlevel10k"

    before_regex='^[[:space:]]*(source|\.)[[:space:]].*oh-my-zsh\.sh'
    if ! has_oh_my_zsh_source_outside_os_init_block; then
        before_regex=""
        source_line=$'\nsource "$ZSH/oh-my-zsh.sh"'
    fi

    content="$(cat <<EOF
export ZSH="\$HOME/.oh-my-zsh"
ZSH_THEME="$theme"
export UPDATE_ZSH_DAYS=1
zstyle ':omz:update' mode auto
DISABLE_MAGIC_FUNCTIONS=true
DISABLE_AUTO_TITLE="true"
plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
    fzf
    docker
    kubectl
)$source_line
EOF
)"
    os_init_upsert_zsh_block "oh-my-zsh" "$content" "$before_regex"
}

cleanup_legacy_starship() {
    local config_dir starship_path
    os_init_remove_interactive_shell_block "terminal-style"
    os_init_remove_zsh_block "starship"
    os_init_remove_bash_block "starship"

    config_dir="$(real_home)/.config/os-init/terminal"
    os_init_restore_owned_user_path "terminal-starship-rich.toml" "$config_dir/starship-rich.toml" || true
    os_init_restore_owned_user_path "terminal-starship-simple.toml" "$config_dir/starship-simple.toml" || true
    os_init_restore_owned_user_path "terminal-starship-plain.toml" "$config_dir/starship-plain.toml" || true

    if os_init_package_owned "starship-package"; then
        remove "legacy OS Init Starship package"
        pkg_remove starship 2>/dev/null || true
        os_init_forget_package_ownership "starship-package"
    elif starship_path="$(command -v starship 2>/dev/null)" && os_init_owned_path "starship-bin"; then
        remove "legacy OS Init Starship binary"
        os_init_restore_owned_path "starship-bin" "$starship_path" || true
    fi
}

configure_direnv_zsh() {
    local content
    content="$(cat <<'EOF'
if command -v direnv >/dev/null 2>&1; then
    eval "$(direnv hook zsh)"
fi
EOF
)"
    os_init_upsert_zsh_block "direnv" "$content"
}

STEP=0
count_steps() {
    local total=0
	want "zsh" && total=$((total + 1))
	want "direnv" && total=$((total + 1))
	want "zsh" && total=$((total + 1))
	want "git" && total=$((total + 1))
	want "byobu" && total=$((total + 1))
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

    if want "zsh"; then
        cleanup_legacy_starship
        echo "[REMOVE] zsh plugins..."
        if [[ -f "$ZSH_CUSTOM/plugins/zsh-autosuggestions/.os-init-owned" ]]; then
			remove "zsh-autosuggestions"
			rm -rf "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
		elif [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
			warn "保留非 OS Init 创建的 zsh-autosuggestions"
        else
            skip "zsh-autosuggestions not found"
        fi
        if [[ -f "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting/.os-init-owned" ]]; then
            remove "zsh-syntax-highlighting"
			rm -rf "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
		elif [[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
			warn "保留非 OS Init 创建的 zsh-syntax-highlighting"
        else
            skip "zsh-syntax-highlighting not found"
        fi
    fi

    if want "direnv"; then
        echo "[REMOVE] direnv..."
		if command -v direnv &>/dev/null && os_init_package_owned "direnv-package"; then
            remove "removing direnv"
			pkg_remove "${DIRENV_PACKAGE:-direnv}" 2>/dev/null || true
			os_init_forget_package_ownership "direnv-package"
		elif command -v direnv &>/dev/null; then
			warn "保留非 OS Init 安装的 direnv"
        else
            skip "direnv not installed"
        fi
        os_init_remove_zsh_block "direnv"
    fi

    if want "git"; then
        echo "[REMOVE] git-lfs..."
		if command -v git-lfs &>/dev/null && os_init_package_owned "git-lfs-package"; then
            remove "removing git-lfs"
			pkg_remove git-lfs 2>/dev/null || true
			os_init_forget_package_ownership "git-lfs-package"
		elif command -v git-lfs &>/dev/null; then
			warn "保留非 OS Init 安装的 git-lfs"
        else
            skip "git-lfs not installed"
        fi
    fi

    if want "byobu"; then
        echo "[REMOVE] byobu..."
		if os_init_package_owned "byobu-package"; then
			pkg_remove byobu 2>/dev/null || true
			os_init_forget_package_ownership "byobu-package"
		fi
		if os_init_package_owned "tmux-package"; then
			pkg_remove tmux 2>/dev/null || true
			os_init_forget_package_ownership "tmux-package"
		fi
		if command -v byobu &>/dev/null; then
			warn "保留非 OS Init 安装的 byobu 和用户配置"
		elif ! os_init_package_owned "byobu-package"; then
			skip "byobu not installed"
        fi
    fi

    if want "zsh"; then
        echo "[REMOVE] oh-my-zsh..."
		p10k_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
		if [[ -f "$p10k_dir/.os-init-owned" ]]; then
			remove "Powerlevel10k"
			rm -rf "$p10k_dir"
		fi
		if [[ -f "$HOME/.oh-my-zsh/.os-init-owned" ]]; then
            remove "removing ~/.oh-my-zsh"
			rm -rf "$HOME/.oh-my-zsh"
		elif [[ -d "$HOME/.oh-my-zsh" ]]; then
			warn "保留非 OS Init 创建的 ~/.oh-my-zsh"
        else
            skip "oh-my-zsh not installed"
        fi
		os_init_remove_zsh_block "oh-my-zsh"
		if os_init_user_owned "original-login-shell"; then
			original_shell="$(cat "$(os_init_user_state_dir)/values/original-login-shell" 2>/dev/null || true)"
			if [[ -n "$original_shell" ]]; then
				sudo chsh -s "$original_shell" "$(real_user)" || warn "无法恢复原默认 shell: $original_shell"
			fi
			os_init_forget_user_ownership "original-login-shell"
			rm -f "$(os_init_user_state_dir)/values/original-login-shell"
		fi
		if os_init_owned_path "zsh-etc-shells-entry"; then
			shell_path="$(command -v zsh 2>/dev/null || true)"
			if [[ -n "$shell_path" ]]; then
				sudo awk -v shell="$shell_path" '$0 != shell { print }' /etc/shells | sudo tee /etc/shells.tmp-os-init >/dev/null
				sudo install -m 0644 /etc/shells.tmp-os-init /etc/shells
				sudo rm -f /etc/shells.tmp-os-init
			fi
			os_init_forget_ownership "zsh-etc-shells-entry"
		fi
		echo "  note: zsh package left intact"
    fi

    echo ""
    echo "=== $(os_init_text "Shell 工具卸载完成" "Shell tools uninstall complete") ==="
    exit 0
fi

# ── zsh + oh-my-zsh ──────────────────────────────────────────────────────────
if want "zsh"; then
    next "zsh + oh-my-zsh"

	cleanup_legacy_starship
    ensure_zsh_package
	ensure_macos_oh_my_zsh_commands
    set_default_zsh
    ensure_oh_my_zsh
	ensure_powerlevel10k
fi

# ── direnv ────────────────────────────────────────────────────────────────────
if want "direnv"; then
    next "direnv"

    if command -v direnv &>/dev/null; then
        skip "direnv $(direnv version) already installed"
    else
        install "installing direnv"
		pkg_install "${DIRENV_PACKAGE:-direnv}"
		os_init_mark_package_ownership "direnv-package"
    fi
fi

# ── zsh plugins ───────────────────────────────────────────────────────────────
if want "zsh"; then
    next "zsh plugins"

    ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    mkdir -p "$ZSH_CUSTOM/plugins"

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
		touch "$ZSH_CUSTOM/plugins/zsh-autosuggestions/.os-init-owned"
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
		touch "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting/.os-init-owned"
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
		for package in "${PKGS[@]}"; do
			os_init_mark_package_ownership "${package}-package"
		done
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
        skip "$HOME/.gitconfig already exists (not overwriting)"
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
		os_init_mark_package_ownership "git-lfs-package"
        git lfs install
    fi
fi

# ── shell integrations ───────────────────────────────────────────────────────
if want "zsh"; then
    configure_oh_my_zsh
fi
if want "direnv"; then
    configure_direnv_zsh
fi

echo ""
echo "=== $(os_init_text "Shell 工具安装完成" "Shell tools setup complete") ==="
echo "  $(os_init_text "已处理" "Processed"): ${COMPONENTS[*]}"
echo ""
want "byobu" && echo "  byobu  -- $(os_init_text "启动终端复用器" "launch terminal multiplexer")"
os_init_text "打开新终端或执行: exec zsh" "Start a new terminal or run: exec zsh"
