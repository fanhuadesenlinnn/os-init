#!/usr/bin/env bash
# Sourced by modules/lib.sh.

backup_file() {
    local file="$1"
    if [[ -e "$file" ]]; then
        local backup
        backup="${file}.bak-os-init.$(date +%Y%m%d%H%M%S)"
        sudo cp -a "$file" "$backup"
        echo "$backup"
    fi
}

os_init_validate_ownership_key() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || die "无效的资源所有权键: $1"
}

os_init_system_state_dir() {
    echo "${OS_INIT_SYSTEM_STATE_DIR:-/var/lib/os-init}"
}

# Record the pre-existing value of a system path before OS Init first takes
# ownership. Repeated updates keep the original backup instead of replacing it.
os_init_prepare_owned_path() {
    local key="$1" target="$2" state_dir marker backup tmp
    os_init_validate_ownership_key "$key"
    state_dir="$(os_init_system_state_dir)"
    marker="${state_dir}/ownership/${key}"
    backup="${state_dir}/backups/${key}"
    if sudo test -f "$marker"; then
        return 0
    fi

    tmp="$(mktemp "${TMPDIR:-/tmp}/os-init-owned.XXXXXX")"
    if sudo test -e "$target" || sudo test -L "$target"; then
        # shellcheck disable=SC2033
        sudo install -d -m 0700 "${state_dir}/backups"
        sudo rm -rf "$backup"
        sudo cp -a "$target" "$backup"
        printf 'backup\n' > "$tmp"
    else
        printf 'created\n' > "$tmp"
    fi
    # shellcheck disable=SC2033
    sudo install -d -m 0700 "${state_dir}/ownership"
    # shellcheck disable=SC2033
    sudo install -m 0600 "$tmp" "$marker"
    rm -f "$tmp"
}

os_init_owned_path() {
    local key="$1"
    os_init_validate_ownership_key "$key"
    sudo test -f "$(os_init_system_state_dir)/ownership/${key}"
}

os_init_mark_ownership() {
    local key="$1" state_dir tmp
    os_init_validate_ownership_key "$key"
    state_dir="$(os_init_system_state_dir)"
    tmp="$(mktemp "${TMPDIR:-/tmp}/os-init-owned.XXXXXX")"
    printf 'created\n' > "$tmp"
    # shellcheck disable=SC2033
    sudo install -d -m 0700 "${state_dir}/ownership"
    # shellcheck disable=SC2033
    sudo install -m 0600 "$tmp" "${state_dir}/ownership/${key}"
    rm -f "$tmp"
}

os_init_forget_ownership() {
    local key="$1"
    os_init_validate_ownership_key "$key"
    sudo rm -f "$(os_init_system_state_dir)/ownership/${key}"
}

os_init_user_state_dir() {
    local home
    home="$(real_home)"
    echo "${OS_INIT_USER_STATE_DIR:-${home}/.local/state/os-init}"
}

os_init_mark_user_ownership() {
    local key="$1" dir
    os_init_validate_ownership_key "$key"
    dir="$(os_init_user_state_dir)/ownership"
    mkdir -p "$dir"
    chmod 700 "$(os_init_user_state_dir)" "$dir" 2>/dev/null || true
    printf 'created\n' > "${dir}/${key}"
    chmod 600 "${dir}/${key}" 2>/dev/null || true
}

os_init_user_owned() {
    local key="$1"
    os_init_validate_ownership_key "$key"
    [[ -f "$(os_init_user_state_dir)/ownership/${key}" ]]
}

os_init_forget_user_ownership() {
    local key="$1"
    os_init_validate_ownership_key "$key"
    rm -f "$(os_init_user_state_dir)/ownership/${key}"
}

os_init_mark_package_ownership() {
    if is_macos; then
        os_init_mark_user_ownership "$1"
    else
        os_init_mark_ownership "$1"
    fi
}

os_init_package_owned() {
    if is_macos; then
        os_init_user_owned "$1"
    else
        os_init_owned_path "$1"
    fi
}

os_init_forget_package_ownership() {
    if is_macos; then
        os_init_forget_user_ownership "$1"
    else
        os_init_forget_ownership "$1"
    fi
}

os_init_prepare_owned_user_path() {
    local key="$1" target="$2" state_dir marker backup
    os_init_validate_ownership_key "$key"
    state_dir="$(os_init_user_state_dir)"
    marker="${state_dir}/ownership/user-path-${key}"
    backup="${state_dir}/backups/${key}"
    [[ -f "$marker" ]] && return 0
    mkdir -p "${state_dir}/ownership" "${state_dir}/backups"
    chmod 700 "$state_dir" "${state_dir}/ownership" "${state_dir}/backups" 2>/dev/null || true
    if [[ -e "$target" || -L "$target" ]]; then
        rm -rf "$backup"
        cp -a "$target" "$backup"
        printf 'backup\n' > "$marker"
    else
        printf 'created\n' > "$marker"
    fi
    chmod 600 "$marker" 2>/dev/null || true
}

# Adopt a path that was created by an older OS Init provider before shared
# ownership markers existed. Callers must positively identify legacy content;
# this helper deliberately never guesses from the path alone.
os_init_adopt_created_user_path() {
	local key="$1" target="$2" state_dir marker
	os_init_validate_ownership_key "$key"
	[[ -e "$target" || -L "$target" ]] || return 1
	state_dir="$(os_init_user_state_dir)"
	marker="${state_dir}/ownership/user-path-${key}"
	[[ -f "$marker" ]] && return 0
	mkdir -p "${state_dir}/ownership"
	chmod 700 "$state_dir" "${state_dir}/ownership" 2>/dev/null || true
	printf 'created\n' > "$marker"
	chmod 600 "$marker" 2>/dev/null || true
}

os_init_restore_owned_user_path() {
    local key="$1" target="$2" state_dir marker backup state
    os_init_validate_ownership_key "$key"
    state_dir="$(os_init_user_state_dir)"
    marker="${state_dir}/ownership/user-path-${key}"
    backup="${state_dir}/backups/${key}"
    if [[ ! -f "$marker" ]]; then
        warn "保留未记录为 OS Init 所有的路径: $target"
        return 1
    fi
    state="$(cat "$marker")"
    rm -rf "$target"
    if [[ "$state" == "backup" && -e "$backup" ]]; then
        mkdir -p "$(dirname "$target")"
        cp -a "$backup" "$target"
        rm -rf "$backup"
        remove "恢复安装前路径: $target"
    else
        remove "删除 OS Init 创建的路径: $target"
    fi
    rm -f "$marker"
}

# Remove a path created by OS Init or restore the value that existed before OS
# Init first managed it. Unknown paths are deliberately preserved.
os_init_restore_owned_path() {
    local key="$1" target="$2" state_dir marker backup state
    os_init_validate_ownership_key "$key"
    state_dir="$(os_init_system_state_dir)"
    marker="${state_dir}/ownership/${key}"
    backup="${state_dir}/backups/${key}"
    if ! sudo test -f "$marker"; then
        warn "保留未记录为 OS Init 所有的路径: $target"
        return 1
    fi

    state="$(sudo cat "$marker")"
    sudo rm -rf "$target"
    if [[ "$state" == "backup" ]] && sudo test -e "$backup"; then
        sudo mkdir -p "$(dirname "$target")"
        sudo cp -a "$backup" "$target"
        sudo rm -rf "$backup"
        remove "恢复安装前路径: $target"
    else
        remove "删除 OS Init 创建的路径: $target"
    fi
    sudo rm -f "$marker"
}

os_init_reown_user_file() {
    local file="$1" user
    if [[ "$(id -u)" != "0" || -z "${SUDO_USER:-}" || "${SUDO_USER:-}" == "root" ]]; then
        return 0
    fi
    user="$(real_user)"
    chown "$user" "$file" 2>/dev/null || true
}

os_init_prepare_user_file() {
    local file="$1"
    mkdir -p "$(dirname "$file")"
    touch "$file"
    os_init_reown_user_file "$file"
}

os_init_upsert_block() {
    local file="$1" name="$2" content="$3" before_regex="${4:-}"
    local begin end tmp repl
    begin="# >>> os-init ${name} >>>"
    end="# <<< os-init ${name} <<<"

    os_init_prepare_user_file "$file"
    tmp="$(mktemp "${TMPDIR:-/tmp}/os-init-block.XXXXXX")"
    repl="$(mktemp "${TMPDIR:-/tmp}/os-init-block-repl.XXXXXX")"

    {
        printf '%s\n' "$begin"
        printf '%s\n' "$content"
        printf '%s\n' "$end"
    } > "$repl"

    if grep -Fq "$begin" "$file"; then
        awk -v begin="$begin" -v end="$end" -v repl="$repl" '
            function print_repl(  line) {
                while ((getline line < repl) > 0) print line
                close(repl)
            }
            $0 == begin {
                if (!printed) {
                    print_repl()
                    printed = 1
                }
                in_block = 1
                next
            }
            in_block && $0 == end {
                in_block = 0
                next
            }
            !in_block { print }
            END {
                if (!printed) print_repl()
            }
        ' "$file" > "$tmp"
    elif [[ -n "$before_regex" ]]; then
        awk -v pattern="$before_regex" -v repl="$repl" '
            function print_repl(  line) {
                while ((getline line < repl) > 0) print line
                close(repl)
            }
            $0 ~ pattern && !printed {
                print_repl()
                printed = 1
            }
            { print }
            END {
                if (!printed) {
                    if (NR > 0) print ""
                    print_repl()
                }
            }
        ' "$file" > "$tmp"
    else
        awk -v repl="$repl" '
            function print_repl(  line) {
                while ((getline line < repl) > 0) print line
                close(repl)
            }
            { print }
            END {
                if (NR > 0) print ""
                print_repl()
            }
        ' "$file" > "$tmp"
    fi

    if cmp -s "$file" "$tmp"; then
        skip "$(basename "$file") 已包含 ${name} 配置"
    else
        install "写入 $(basename "$file") 的 ${name} 配置"
        mv "$tmp" "$file"
        os_init_reown_user_file "$file"
    fi
    rm -f "$tmp" "$repl"
}

os_init_remove_block() {
    local file="$1" name="$2" begin end tmp
    [[ -f "$file" ]] || return 0
    begin="# >>> os-init ${name} >>>"
    end="# <<< os-init ${name} <<<"
    grep -Fq "$begin" "$file" || {
        skip "$(basename "$file") 未包含 ${name} 配置"
        return 0
    }

    tmp="$(mktemp "${TMPDIR:-/tmp}/os-init-block-remove.XXXXXX")"
    awk -v begin="$begin" -v end="$end" '
        $0 == begin { in_block = 1; next }
        in_block && $0 == end { in_block = 0; next }
        !in_block { print }
    ' "$file" > "$tmp"
    install "删除 $(basename "$file") 的 ${name} 配置"
    mv "$tmp" "$file"
    os_init_reown_user_file "$file"
}

os_init_zshrc() {
    local home
    home="$(real_home)"
    [[ -n "$home" ]] || return 1
    printf '%s\n' "$home/.zshrc"
}

os_init_bashrc() {
    local home
    home="$(real_home)"
    [[ -n "$home" ]] || return 1
    printf '%s\n' "$home/.bashrc"
}

os_init_interactive_shell_rc_files() {
    local home
    home="$(real_home)"
    [[ -n "$home" ]] || return 1
    printf '%s\n' "$home/.zshrc"
    printf '%s\n' "$home/.bashrc"
}

os_init_shell_rc_files() {
    local home file any=false
    home="$(real_home)"
    [[ -n "$home" ]] || return 1
    for file in "$home/.zshrc" "$home/.bashrc"; do
        if [[ -e "$file" ]]; then
            printf '%s\n' "$file"
            any=true
        fi
    done
    if [[ "$any" == false ]]; then
        printf '%s\n' "$home/.zshrc"
    fi
}

os_init_upsert_zsh_block() {
    local name="$1" content="$2" before_regex="${3:-}" file
    file="$(os_init_zshrc)" || return 0
    os_init_upsert_block "$file" "$name" "$content" "$before_regex"
}

os_init_upsert_bash_block() {
    local name="$1" content="$2" before_regex="${3:-}" file
    file="$(os_init_bashrc)" || return 0
    os_init_upsert_block "$file" "$name" "$content" "$before_regex"
}

os_init_upsert_shell_block() {
    local name="$1" content="$2" file
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        os_init_upsert_block "$file" "$name" "$content"
    done < <(os_init_shell_rc_files)
}

os_init_upsert_interactive_shell_block() {
    local name="$1" content="$2" file
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        os_init_upsert_block "$file" "$name" "$content"
    done < <(os_init_interactive_shell_rc_files)
}

os_init_remove_zsh_block() {
    local name="$1" file
    file="$(os_init_zshrc)" || return 0
    os_init_remove_block "$file" "$name"
}

os_init_remove_bash_block() {
    local name="$1" file
    file="$(os_init_bashrc)" || return 0
    os_init_remove_block "$file" "$name"
}

os_init_remove_shell_block() {
    local name="$1" file
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        os_init_remove_block "$file" "$name"
    done < <(os_init_shell_rc_files)
}

os_init_remove_interactive_shell_block() {
    local name="$1" file
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        os_init_remove_block "$file" "$name"
    done < <(os_init_interactive_shell_rc_files)
}
