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

os_init_normalize_absolute_path() {
    local input="$1" component index
    local -a parts=() normalized=()
    [[ -n "$input" && "$input" == /* && "$input" != *$'\n'* && "$input" != *$'\r'* ]] || \
        die "资源路径必须是不含换行的绝对路径: $input"
    IFS='/' read -r -a parts <<< "$input"
    for component in "${parts[@]}"; do
        case "$component" in
            ''|.) ;;
            ..)
                ((${#normalized[@]} > 0)) || die "资源路径不能越过根目录: $input"
                index=$((${#normalized[@]} - 1))
                unset 'normalized[index]'
                ;;
            *) normalized+=("$component") ;;
        esac
    done
    if ((${#normalized[@]} == 0)); then
        printf '/\n'
        return
    fi
    printf '/%s' "${normalized[0]}"
    for ((index = 1; index < ${#normalized[@]}; index++)); do
        printf '/%s' "${normalized[index]}"
    done
    printf '\n'
}

os_init_write_owned_marker() {
    local file="$1" state="$2" target="$3"
    {
        printf 'version=2\n'
        printf 'state=%s\n' "$state"
        printf 'target=%s\n' "$target"
    } > "$file"
}

os_init_read_owned_marker() {
    local marker="$1" prefix="$2" version state target content line
    if [[ -r "$marker" ]]; then
        content="$(cat "$marker")"
    else
        content="$(sudo cat "$marker")"
    fi
    while IFS= read -r line; do
        case "$line" in
            version=*) version="${line#version=}" ;;
            state=*) state="${line#state=}" ;;
            target=*) target="${line#target=}" ;;
        esac
    done <<< "$content"
    [[ "$version" == "2" && ("$state" == "created" || "$state" == "backup") && -n "$target" ]] || return 1
    printf -v "${prefix}_state" '%s' "$state"
    printf -v "${prefix}_target" '%s' "$target"
}

os_init_require_path_within() {
    local target="$1" allowed_root="$2" label="${3:-资源路径}" canonical_target canonical_root
    canonical_target="$(os_init_normalize_absolute_path "$target")" || return 1
    canonical_root="$(os_init_normalize_absolute_path "$allowed_root")" || return 1
    [[ "$canonical_root" != "/" ]] || die "拒绝使用根目录作为允许范围: $label"
    case "$canonical_target" in
        "$canonical_root"|"$canonical_root"/*) printf '%s\n' "$canonical_target" ;;
        *) die "$label 必须位于 $canonical_root 内: $target" ;;
    esac
}

os_init_assert_tree_has_no_mounts() {
    local target="$1" mount_targets mounted_target
    command -v findmnt >/dev/null 2>&1 || \
        die "无法检查递归删除目标的挂载边界，已拒绝删除: $target"
    if ! mount_targets="$(findmnt -rn -o TARGET 2>/dev/null)" || [[ -z "$mount_targets" ]]; then
        die "无法读取挂载表，已拒绝递归删除: $target"
    fi
    while IFS= read -r mounted_target; do
        [[ -n "$mounted_target" ]] || continue
        case "$mounted_target" in
            "$target") die "拒绝递归删除挂载点: $target" ;;
            "$target"/*) die "拒绝递归删除包含嵌套挂载的目录: target=$target mount=$mounted_target" ;;
        esac
    done <<< "$mount_targets"
}

os_init_safe_remove_tree() {
    local target="$1" allowed_root="$2" label="${3:-资源目录}" canonical_target
    canonical_target="$(os_init_require_path_within "$target" "$allowed_root" "$label")" || return 1
    os_init_assert_tree_has_no_mounts "$canonical_target"
    sudo rm -rf -- "$canonical_target"
}

os_init_validate_systemd_service_name() {
    local service="$1"
    [[ "$service" =~ ^[A-Za-z0-9][A-Za-z0-9_.@:-]*\.service$ ]] || \
        die "systemd 服务名必须是合法的 .service 单元名，不能包含路径、选项或换行: $service"
}

os_init_assert_safe_user_home() {
    local home mounted_target normalized_home normalized_mount
    is_container || return 0
    [[ "${OS_INIT_ALLOW_HOST_INTEGRATED_CONTAINER:-0}" != "1" ]] || return 0
    command -v findmnt >/dev/null 2>&1 || \
        die "容器内无法检查 HOME 挂载来源，已拒绝用户文件写入；核对边界后可设置 OS_INIT_ALLOW_HOST_INTEGRATED_CONTAINER=1"
    home="$(real_home)" || return 1
    normalized_home="$(os_init_normalize_absolute_path "$home")" || return 1
    mounted_target="$(findmnt -n -o TARGET -T "$normalized_home" 2>/dev/null | tail -n 1)"
    [[ -n "$mounted_target" ]] || die "容器内无法解析 HOME 挂载来源，已拒绝用户文件写入: $normalized_home"
    normalized_mount="$(os_init_normalize_absolute_path "$mounted_target")" || return 1
    if [[ "$normalized_mount" != "/" ]]; then
        case "$normalized_home" in
            "$normalized_mount"|"$normalized_mount"/*)
                die "检测到 HOME 位于容器独立挂载 $normalized_mount；为避免修改宿主 HOME，已拒绝写入"
                ;;
        esac
    fi
}

# Record the pre-existing value of a system path before OS Init first takes
# ownership. Repeated updates keep the original backup instead of replacing it.
os_init_prepare_owned_path() {
    local key="$1" target="$2" state_dir marker backup tmp canonical_target marker_state marker_target
    os_init_validate_ownership_key "$key"
    canonical_target="$(os_init_normalize_absolute_path "$target")" || return 1
    state_dir="$(os_init_system_state_dir)"
    marker="${state_dir}/ownership/${key}"
    backup="${state_dir}/backups/${key}"
    if sudo test -f "$marker"; then
        if ! os_init_read_owned_marker "$marker" marker; then
            die "检测到旧版或损坏的所有权标记，无法安全确认目标；请人工核对后删除: $marker"
        fi
        [[ "$marker_target" == "$canonical_target" ]] || \
            die "所有权标记目标不匹配，已拒绝重新绑定: key=$key recorded=$marker_target requested=$canonical_target"
        return 0
    fi

    tmp="$(mktemp "${TMPDIR:-/tmp}/os-init-owned.XXXXXX")"
    if sudo test -e "$target" || sudo test -L "$target"; then
        # shellcheck disable=SC2033
        sudo install -d -m 0700 "${state_dir}/backups"
        sudo rm -rf "$backup"
        sudo cp -a "$target" "$backup"
        os_init_write_owned_marker "$tmp" backup "$canonical_target"
    else
        os_init_write_owned_marker "$tmp" created "$canonical_target"
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
    os_init_assert_safe_user_home
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
    local key="$1" target="$2" state_dir marker backup canonical_target marker_state marker_target tmp
    os_init_validate_ownership_key "$key"
    os_init_assert_safe_user_home
    canonical_target="$(os_init_normalize_absolute_path "$target")" || return 1
    state_dir="$(os_init_user_state_dir)"
    marker="${state_dir}/ownership/user-path-${key}"
    backup="${state_dir}/backups/${key}"
    if [[ -f "$marker" ]]; then
        if ! os_init_read_owned_marker "$marker" marker; then
            die "检测到旧版或损坏的用户所有权标记，无法安全确认目标: $marker"
        fi
        [[ "$marker_target" == "$canonical_target" ]] || \
            die "用户所有权标记目标不匹配，已拒绝重新绑定: key=$key recorded=$marker_target requested=$canonical_target"
        return 0
    fi
    mkdir -p "${state_dir}/ownership" "${state_dir}/backups"
    chmod 700 "$state_dir" "${state_dir}/ownership" "${state_dir}/backups" 2>/dev/null || true
    if [[ -e "$target" || -L "$target" ]]; then
        rm -rf "$backup"
        cp -a "$target" "$backup"
        tmp="$(mktemp "${TMPDIR:-/tmp}/os-init-owned-user.XXXXXX")"
        os_init_write_owned_marker "$tmp" backup "$canonical_target"
        command install -m 0600 "$tmp" "$marker"
        rm -f "$tmp"
    else
        tmp="$(mktemp "${TMPDIR:-/tmp}/os-init-owned-user.XXXXXX")"
        os_init_write_owned_marker "$tmp" created "$canonical_target"
        command install -m 0600 "$tmp" "$marker"
        rm -f "$tmp"
    fi
    chmod 600 "$marker" 2>/dev/null || true
}

# Adopt a path that was created by an older OS Init provider before shared
# ownership markers existed. Callers must positively identify legacy content;
# this helper deliberately never guesses from the path alone.
os_init_adopt_created_user_path() {
	local key="$1" target="$2" state_dir marker canonical_target tmp
	os_init_validate_ownership_key "$key"
	[[ -e "$target" || -L "$target" ]] || return 1
	canonical_target="$(os_init_normalize_absolute_path "$target")" || return 1
	state_dir="$(os_init_user_state_dir)"
	marker="${state_dir}/ownership/user-path-${key}"
	[[ -f "$marker" ]] && return 0
	mkdir -p "${state_dir}/ownership"
	chmod 700 "$state_dir" "${state_dir}/ownership" 2>/dev/null || true
	tmp="$(mktemp "${TMPDIR:-/tmp}/os-init-owned-user.XXXXXX")"
	os_init_write_owned_marker "$tmp" created "$canonical_target"
	command install -m 0600 "$tmp" "$marker"
	rm -f "$tmp"
	chmod 600 "$marker" 2>/dev/null || true
}

os_init_restore_owned_user_path() {
    local key="$1" target="$2" state_dir marker backup state canonical_target marker_state marker_target
    os_init_validate_ownership_key "$key"
    state_dir="$(os_init_user_state_dir)"
    marker="${state_dir}/ownership/user-path-${key}"
    backup="${state_dir}/backups/${key}"
    if [[ ! -f "$marker" ]]; then
        warn "保留未记录为 OS Init 所有的路径: $target"
        return 1
    fi
    canonical_target="$(os_init_normalize_absolute_path "$target")" || return 1
    if ! os_init_read_owned_marker "$marker" marker; then
        warn "保留目标，因为所有权标记是旧版或已损坏: $target"
        return 1
    fi
    if [[ "$marker_target" != "$canonical_target" ]]; then
        warn "保留目标，因为所有权标记绑定到其他路径: recorded=$marker_target requested=$canonical_target"
        return 1
    fi
    state="$marker_state"
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
    local key="$1" target="$2" state_dir marker backup state canonical_target marker_state marker_target
    os_init_validate_ownership_key "$key"
    state_dir="$(os_init_system_state_dir)"
    marker="${state_dir}/ownership/${key}"
    backup="${state_dir}/backups/${key}"
    if ! sudo test -f "$marker"; then
        warn "保留未记录为 OS Init 所有的路径: $target"
        return 1
    fi

    canonical_target="$(os_init_normalize_absolute_path "$target")" || return 1
    if ! os_init_read_owned_marker "$marker" marker; then
        warn "保留目标，因为所有权标记是旧版或已损坏: $target"
        return 1
    fi
    if [[ "$marker_target" != "$canonical_target" ]]; then
        warn "保留目标，因为所有权标记绑定到其他路径: recorded=$marker_target requested=$canonical_target"
        return 1
    fi
    state="$marker_state"
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
    os_init_assert_safe_user_home
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
