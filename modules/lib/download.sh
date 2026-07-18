#!/usr/bin/env bash
# Sourced by modules/lib.sh.

resource_url() {
    local key="$1" fallback="$2" value
    value="${!key:-}"
    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$fallback"
    fi
}

repo_url() {
    resource_url "$@"
}

rewrite_download_url() {
    rewrite_github_url "$1"
}

git_with_proxy() {
	GIT_TERMINAL_PROMPT=0 run_with_github_git_proxy command git "$@"
}

github_latest_version() {
    local repo="$1" prefix="${2:-v}"
    local url latest="" location="" effective="" body=""
    url="$(rewrite_download_url "https://github.com/${repo}/releases/latest")"
    if command -v curl &>/dev/null; then
        location="$(curl -fsSI \
            --connect-timeout "${DOWNLOAD_TIMEOUT:-30}" \
            --max-time "${DOWNLOAD_TIMEOUT:-30}" \
            "$url" 2>/dev/null | sed -n 's/^[Ll]ocation:[[:space:]]*//p' | tail -n 1 | tr -d '\r\n')"
        effective="$(curl -fsSL -o /dev/null -w '%{url_effective}' \
            --connect-timeout "${DOWNLOAD_TIMEOUT:-30}" \
            --max-time "${DOWNLOAD_TIMEOUT:-30}" "$url" 2>/dev/null || true)"
        latest="$(printf '%s\n%s\n' "$location" "$effective" | sed -n 's#.*\/releases\/tag\/\([^/?]*\).*#\1#p' | head -n 1)"
        if [[ -z "$latest" ]]; then
            body="$(curl -fsSL --connect-timeout "${DOWNLOAD_TIMEOUT:-30}" --max-time "${DOWNLOAD_TIMEOUT:-30}" "$url" 2>/dev/null || true)"
            latest="$(printf '%s' "$body" | grep -Eo "/${repo}/releases/tag/[^\"?]+" | head -n 1 | sed 's#.*/##')"
        fi
    elif command -v wget &>/dev/null; then
        location="$(wget --server-response --spider \
            --timeout="${DOWNLOAD_TIMEOUT:-30}" \
            "$url" 2>&1 | grep -i 'Location:' | tail -1 | sed 's/.*Location:[[:space:]]*//' | tr -d '\r\n')"
        latest="$(printf '%s' "$location" | sed -n 's#.*\/releases\/tag\/\([^/?]*\).*#\1#p')"
    else
        die "需要 curl 或 wget 才能查询 GitHub 最新版本"
    fi
    latest="${latest#"${prefix}"}"
    [[ -n "$latest" ]] || die "无法获取 ${repo} 最新版本"
    printf '%s\n' "$latest"
}

git_clone_depth() {
	local depth="$1" url="$2" dest="$3" final_url
	final_url="$(rewrite_download_url "$url")"
	GIT_TERMINAL_PROMPT=0 command git clone --depth="$depth" "$final_url" "$dest"
	[[ "$final_url" == "$url" ]] || command git -C "$dest" remote set-url origin "$url"
}

git_clone_depth_branch() {
	local depth="$1" branch="$2" url="$3" dest="$4" final_url
	final_url="$(rewrite_download_url "$url")"
	GIT_TERMINAL_PROMPT=0 command git clone --depth="$depth" -b "$branch" "$final_url" "$dest"
	[[ "$final_url" == "$url" ]] || command git -C "$dest" remote set-url origin "$url"
}

download_file() {
    local url="$1" dest="$2"

    local final_url
    final_url="$(rewrite_download_url "$url")"
    mkdir -p "$(dirname "$dest")"
    if command -v curl &>/dev/null; then
        curl -fL --retry "${DOWNLOAD_RETRY:-3}" \
            --connect-timeout "${DOWNLOAD_TIMEOUT:-30}" \
            --max-time "${DOWNLOAD_TIMEOUT:-30}" \
            -o "$dest" "$final_url"
    elif command -v wget &>/dev/null; then
        wget --tries="${DOWNLOAD_RETRY:-3}" \
            --timeout="${DOWNLOAD_TIMEOUT:-30}" \
            -O "$dest" "$final_url"
    else
        die "需要 curl 或 wget 才能下载文件"
    fi
}

sha256_file() {
	local file="$1"
	if command -v sha256sum &>/dev/null; then
		sha256sum "$file" | awk '{print $1}'
	elif command -v shasum &>/dev/null; then
		shasum -a 256 "$file" | awk '{print $1}'
	else
		die "校验下载需要 sha256sum 或 shasum"
	fi
}

# Download content and verify it when the caller supplied an expected digest.
# A configured GitHub proxy is already an explicit user choice and does not
# require a second permission switch.
download_file_verified() {
	local url="$1" dest="$2" expected="${3:-}" actual
	download_file "$url" "$dest"
	if [[ -z "$expected" ]]; then
		return 0
	fi
	expected="$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')"
	[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || die "无效的 SHA-256: $expected"
	actual="$(sha256_file "$dest")"
	if [[ "$actual" != "$expected" ]]; then
		rm -f "$dest"
		die "下载内容 SHA-256 不匹配，已拒绝使用: $url"
	fi
}

# Executables must never use the optional-checksum behavior above. Callers may
# use a local file source, but network-delivered code must provide a digest.
download_executable_verified() {
	local url="$1" dest="$2" expected="${3:-}"
	[[ -n "$expected" ]] || die "拒绝下载未提供 SHA-256 的可执行文件: $url"
	download_file_verified "$url" "$dest" "$expected"
}

# Reliable update for shallow git clones (git pull often fails with divergent branches)
git_update_shallow() {
	local dir="$1" official_remote="${2:-}"
	local branch remote final_remote
    branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null) || branch="master"
	remote="${official_remote:-$(git -C "$dir" remote get-url origin)}"
	final_remote="$(rewrite_github_url "$remote")"
	GIT_TERMINAL_PROMPT=0 command git -C "$dir" -c "remote.origin.url=${final_remote}" fetch origin --depth=1 -q
	[[ -z "$official_remote" ]] || command git -C "$dir" remote set-url origin "$official_remote"
    git_with_proxy -C "$dir" reset --hard "origin/$branch"
}
