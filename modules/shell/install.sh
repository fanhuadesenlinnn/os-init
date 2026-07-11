#!/bin/bash
set -euo pipefail

# Install shell tooling: zsh, oh-my-zsh, starship, direnv, zsh plugins, nvm, fnm, byobu, git
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

ALL_COMPONENTS=(zsh starship direnv autosuggestions syntax-highlighting nvm fnm git)
is_linux && ALL_COMPONENTS+=(byobu)
parse_update_flag "$@"
COMPONENTS=("${_CLEAN_ARGS[@]}")
if [[ ${#COMPONENTS[@]} -eq 0 ]]; then
    COMPONENTS=("${ALL_COMPONENTS[@]}")
fi

append_component() {
    local next="$1" c
    if ((${#COMPONENTS_NORMALIZED[@]} > 0)); then
        for c in "${COMPONENTS_NORMALIZED[@]}"; do
            [[ "$c" == "$next" ]] && return 0
        done
    fi
    COMPONENTS_NORMALIZED+=("$next")
}

normalize_components() {
    local c
    COMPONENTS_NORMALIZED=()
    for c in "${COMPONENTS[@]}"; do
        case "$c" in
            plugins)
                append_component autosuggestions
                append_component syntax-highlighting
                ;;
            *)
                append_component "$c"
                ;;
        esac
    done
    COMPONENTS=("${COMPONENTS_NORMALIZED[@]}")
    unset COMPONENTS_NORMALIZED
}
normalize_components

want() {
    local c
    for c in "${COMPONENTS[@]}"; do [[ "$c" == "$1" ]] && return 0; done
    return 1
}

want_zsh_plugin() {
    want "zsh" || want "autosuggestions" || want "syntax-highlighting"
}

tool_prefers_package_manager() {
    is_macos || is_arch
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

nvm_version() {
    local version="${NVM_VERSION:-}"
    [[ -n "$version" ]] || version="$(github_latest_version "nvm-sh/nvm" "")"
    echo "$version"
}

nvm_install_url() {
    local version="$1"
    resource_url NVM_INSTALL_URL "${NVM_INSTALL_BASE%/}/${version}/install.sh"
}

starship_prompt_enabled() {
    local zshrc
    [[ "$UNINSTALL" != true ]] && want "starship" && return 0
    zshrc="$(os_init_zshrc 2>/dev/null || true)"
    [[ -n "$zshrc" && -f "$zshrc" ]] && grep -Fq "# >>> os-init starship >>>" "$zshrc"
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
    starship_prompt_enabled && theme=""

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

configure_starship_shells() {
    os_init_upsert_zsh_block "starship" "$(os_init_starship_block_content zsh)"
    os_init_upsert_bash_block "starship" "$(os_init_starship_block_content bash)"
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

configure_nvm_zsh() {
    local content
    content="$(cat <<'EOF'
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
NVM_HOMEBREW_PREFIX=""
if command -v brew >/dev/null 2>&1; then
    NVM_HOMEBREW_PREFIX="$(brew --prefix nvm 2>/dev/null)"
fi
if [ -n "$NVM_HOMEBREW_PREFIX" ] && [ -s "$NVM_HOMEBREW_PREFIX/nvm.sh" ]; then
    . "$NVM_HOMEBREW_PREFIX/nvm.sh"
    if [ -s "$NVM_HOMEBREW_PREFIX/etc/bash_completion.d/nvm" ]; then
        . "$NVM_HOMEBREW_PREFIX/etc/bash_completion.d/nvm"
    fi
elif [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
    if [ -s "$NVM_DIR/bash_completion" ]; then
        . "$NVM_DIR/bash_completion"
    fi
fi
EOF
)"
    os_init_upsert_zsh_block "nvm" "$content"
}

configure_fnm_zsh() {
    local content
    content="$(cat <<'EOF'
if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --use-on-cd --shell zsh)"
fi
EOF
)"
    os_init_upsert_zsh_block "fnm" "$content"
}

STEP=0
count_steps() {
    local total=0
	want "zsh" && total=$((total + 1))
	want "starship" && total=$((total + 1))
	want "direnv" && total=$((total + 1))
	want_zsh_plugin && total=$((total + 1))
	want "nvm" && total=$((total + 1))
	want "fnm" && total=$((total + 1))
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

    if want_zsh_plugin; then
        echo "[REMOVE] zsh plugins..."
        if want "zsh" || want "autosuggestions"; then
			if [[ -f "$ZSH_CUSTOM/plugins/zsh-autosuggestions/.os-init-owned" ]]; then
				remove "zsh-autosuggestions"
				rm -rf "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
			elif [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
				warn "保留非 OS Init 创建的 zsh-autosuggestions"
            else
                skip "zsh-autosuggestions not found"
            fi
        fi
        if want "zsh" || want "syntax-highlighting"; then
			if [[ -f "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting/.os-init-owned" ]]; then
                remove "zsh-syntax-highlighting"
				rm -rf "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
			elif [[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
				warn "保留非 OS Init 创建的 zsh-syntax-highlighting"
            else
                skip "zsh-syntax-highlighting not found"
            fi
        fi
        zshrc_file="$(os_init_zshrc || true)"
        if [[ -n "$zshrc_file" && -f "$zshrc_file" ]]; then
            configure_oh_my_zsh
        fi
    fi

    if want "nvm"; then
        echo "[REMOVE] nvm..."
		if is_macos && os_init_package_owned "nvm-package"; then
			remove "通过 Homebrew 卸载 nvm"
			brew_uninstall nvm 2>/dev/null || true
			os_init_forget_package_ownership "nvm-package"
		elif is_macos && brew_list --formula nvm &>/dev/null; then
			warn "保留非 OS Init 安装的 nvm Homebrew formula"
		elif [[ -f "$HOME/.nvm/.os-init-owned" ]]; then
            remove "removing ~/.nvm"
			rm -rf "$HOME/.nvm"
		elif [[ -d "$HOME/.nvm" ]]; then
			warn "保留非 OS Init 创建的 ~/.nvm"
        else
            skip "nvm not installed"
        fi
        os_init_remove_zsh_block "nvm"
    fi

    if want "fnm"; then
        echo "[REMOVE] fnm..."
		if command -v fnm &>/dev/null; then
			if tool_prefers_package_manager && os_init_package_owned "fnm-package"; then
				remove "卸载由 OS Init 安装的 fnm 软件包"
				pkg_remove fnm 2>/dev/null || true
				os_init_forget_package_ownership "fnm-package"
			elif ! tool_prefers_package_manager && os_init_user_owned "fnm-user-install"; then
				rm -rf "$HOME/.local/share/fnm" "$HOME/.fnm"
				os_init_forget_user_ownership "fnm-user-install"
			else
				warn "保留非 OS Init 安装的 fnm"
            fi
        else
            skip "fnm not installed"
        fi
        os_init_remove_zsh_block "fnm"
    fi

    if want "starship"; then
        echo "$(os_init_text "[删除]" "[REMOVE]") starship..."
		if command -v starship &>/dev/null; then
			if tool_prefers_package_manager && os_init_package_owned "starship-package"; then
                remove "通过包管理器卸载 starship"
				pkg_remove starship 2>/dev/null || true
				os_init_forget_package_ownership "starship-package"
			elif ! tool_prefers_package_manager; then
				os_init_restore_owned_path "starship-bin" "$(command -v starship)" || true
			else
				warn "保留非 OS Init 安装的 starship"
            fi
        else
            skip "starship not installed"
        fi
        os_init_remove_zsh_block "starship"
        os_init_remove_bash_block "starship"
		[[ -d "$HOME/.oh-my-zsh" ]] && configure_oh_my_zsh
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

    ensure_zsh_package
	ensure_macos_oh_my_zsh_commands
    set_default_zsh
    ensure_oh_my_zsh
	ensure_powerlevel10k
fi

# ── starship ──────────────────────────────────────────────────────────────────
if want "starship"; then
    next "starship"

    if tool_prefers_package_manager; then
        if command -v starship &>/dev/null; then
            if [[ "$UPDATE" == true ]]; then
                update "$(os_init_text "通过包管理器更新 starship" "updating starship via package manager")"
                if is_macos; then
                    brew_upgrade starship 2>/dev/null || skip "starship 已是最新"
                else
					pkg_install starship
                fi
            else
                skip "starship $(starship --version | head -1) already installed"
            fi
        else
			install "$(os_init_text "通过包管理器安装 starship" "installing starship via package manager")"
			pkg_install starship
			os_init_mark_package_ownership "starship-package"
        fi
    elif command -v starship &>/dev/null; then
        if [[ "$UPDATE" == true ]]; then
            update "updating starship"
		STARSHIP_INSTALLER="$(mktemp "${TMPDIR:-/tmp}/starship-install.XXXXXX")"
		os_init_prepare_owned_path "starship-bin" "$(command -v starship)"
			download_file_verified "$(resource_url STARSHIP_INSTALL_URL "https://starship.rs/install.sh")" "$STARSHIP_INSTALLER" "${STARSHIP_INSTALL_SHA256:-}"
            sh "$STARSHIP_INSTALLER" -y
            rm -f "$STARSHIP_INSTALLER"
        else
            skip "starship $(starship --version | head -1) already installed"
        fi
    else
        install "installing starship"
		STARSHIP_INSTALLER="$(mktemp "${TMPDIR:-/tmp}/starship-install.XXXXXX")"
		os_init_prepare_owned_path "starship-bin" /usr/local/bin/starship
		download_file_verified "$(resource_url STARSHIP_INSTALL_URL "https://starship.rs/install.sh")" "$STARSHIP_INSTALLER" "${STARSHIP_INSTALL_SHA256:-}"
        sh "$STARSHIP_INSTALLER" -y
        rm -f "$STARSHIP_INSTALLER"
    fi

    mkdir -p "$HOME/.config"
    if [[ -f "$HOME/.config/starship.toml" ]]; then
        skip "$HOME/.config/starship.toml already exists (not overwriting)"
    else
        install "$(os_init_text "复制 starship.toml" "copying starship.toml")"
        if [[ -f "$REPO_DIR/terminal/starship-rich.toml" ]]; then
            cp "$REPO_DIR/terminal/starship-rich.toml" "$HOME/.config/starship.toml"
        else
            cp "$SCRIPT_DIR/starship.toml" "$HOME/.config/starship.toml"
        fi
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
		os_init_mark_package_ownership "direnv-package"
    fi
fi

# ── zsh plugins ───────────────────────────────────────────────────────────────
if want_zsh_plugin; then
    next "zsh plugins"

    ensure_zsh_package
	want "zsh" || ensure_macos_oh_my_zsh_commands
    ensure_oh_my_zsh
    ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    mkdir -p "$ZSH_CUSTOM/plugins"

    if want "zsh" || want "autosuggestions"; then
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
    fi

    if want "zsh" || want "syntax-highlighting"; then
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
fi

# ── nvm ───────────────────────────────────────────────────────────────────────
if want "nvm"; then
    next "nvm"

	if is_macos; then
		mkdir -p "$HOME/.nvm"
		if brew_list --formula nvm &>/dev/null; then
			if [[ "$UPDATE" == true ]]; then
				update "updating nvm via Homebrew"
				brew_upgrade nvm 2>/dev/null || skip "nvm 已是最新"
			else
				skip "nvm Homebrew formula already installed"
			fi
		else
			install "installing nvm via Homebrew"
			brew_install nvm
			os_init_mark_package_ownership "nvm-package"
		fi
    elif [[ -d "$HOME/.nvm" ]]; then
		if [[ "$UPDATE" == true ]]; then
			update "updating nvm to latest"
			LATEST_NVM="$(nvm_version)"
			assert_git_remote_secure "$HOME/.nvm"
			git_with_proxy -C "$HOME/.nvm" fetch origin --depth=1 --tags -q
            git_with_proxy -C "$HOME/.nvm" checkout "$LATEST_NVM" 2>/dev/null
        else
            skip "nvm already installed at ~/.nvm"
        fi
    else
        install "installing nvm"
        LATEST_NVM="$(nvm_version)"
        NVM_INSTALLER="$(mktemp "${TMPDIR:-/tmp}/nvm-install.XXXXXX")"
		download_file_verified "$(nvm_install_url "$LATEST_NVM")" "$NVM_INSTALLER" "${NVM_INSTALL_SHA256:-}"
		PROFILE=/dev/null bash "$NVM_INSTALLER"
		touch "$HOME/.nvm/.os-init-owned"
        rm -f "$NVM_INSTALLER"
    fi
fi

# ── fnm ──────────────────────────────────────────────────────────────────────
if want "fnm"; then
    next "fnm"

    FNM_SKIP=(--skip-shell)

    if tool_prefers_package_manager; then
        if command -v fnm &>/dev/null; then
            if [[ "$UPDATE" == true ]]; then
                update "$(os_init_text "通过包管理器更新 fnm" "updating fnm via package manager")"
				pkg_install fnm
            else
                skip "fnm $(fnm --version 2>/dev/null) already installed"
            fi
        else
			install "$(os_init_text "通过包管理器安装 fnm" "installing fnm via package manager")"
			pkg_install fnm
			os_init_mark_package_ownership "fnm-package"
        fi
    elif command -v fnm &>/dev/null; then
        if [[ "$UPDATE" == true ]]; then
            update "updating fnm"
            FNM_INSTALLER="$(mktemp "${TMPDIR:-/tmp}/fnm-install.XXXXXX")"
			download_file_verified "$(resource_url FNM_INSTALL_URL "https://fnm.vercel.app/install")" "$FNM_INSTALLER" "${FNM_INSTALL_SHA256:-}"
		bash "$FNM_INSTALLER" "${FNM_SKIP[@]}"
		os_init_mark_user_ownership "fnm-user-install"
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
		download_file_verified "$(resource_url FNM_INSTALL_URL "https://fnm.vercel.app/install")" "$FNM_INSTALLER" "${FNM_INSTALL_SHA256:-}"
		bash "$FNM_INSTALLER" "${FNM_SKIP[@]}"
		os_init_mark_user_ownership "fnm-user-install"
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
if want "zsh" || want_zsh_plugin || { want "starship" && [[ -d "$HOME/.oh-my-zsh" ]]; }; then
    configure_oh_my_zsh
fi
if want "starship"; then
    configure_starship_shells
fi
if want "direnv"; then
    configure_direnv_zsh
fi
if want "nvm"; then
    configure_nvm_zsh
fi
if want "fnm"; then
    configure_fnm_zsh
fi

echo ""
echo "=== $(os_init_text "Shell 工具安装完成" "Shell tools setup complete") ==="
echo "  $(os_init_text "已处理" "Processed"): ${COMPONENTS[*]}"
echo ""
want "byobu" && echo "  byobu  -- $(os_init_text "启动终端复用器" "launch terminal multiplexer")"
want "fnm" && echo "  fnm   -- fnm install --lts && fnm use lts-latest"
os_init_text "打开新终端或执行: exec zsh" "Start a new terminal or run: exec zsh"
