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

render_url_proxy() {
    local proxy="$1" url="$2"
    if [[ "$proxy" == *"{url}"* ]]; then
        echo "${proxy//\{url\}/$url}"
    else
        echo "${proxy%/}/$url"
    fi
}

rewrite_github_url() {
    local url="$1"
    if [[ -z "${GITHUB_PROXY:-}" ]]; then
        echo "$url"
        return
    fi

    case "$url" in
        https://github.com/*|https://raw.githubusercontent.com/*|https://objects.githubusercontent.com/*|https://github-releases.githubusercontent.com/*)
            render_url_proxy "$GITHUB_PROXY" "$url"
            ;;
        *)
            echo "$url"
            ;;
    esac
}

rewrite_download_url() {
    rewrite_github_url "$1"
}

git_with_proxy() {
	GIT_TERMINAL_PROMPT=0 command git "$@"
}

assert_git_remote_secure() {
	local dir="$1" remote_url proxy_prefix
	remote_url="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
	proxy_prefix=""
	if [[ -n "${GITHUB_PROXY:-}" ]]; then
		proxy_prefix="$(render_url_proxy "$GITHUB_PROXY" "https://github.com/")"
	fi
	if [[ -n "$proxy_prefix" && "$remote_url" == "$proxy_prefix"/* && "${OS_INIT_ALLOW_UNVERIFIED_PROXY:-0}" != "1" ]]; then
		die "拒绝从未验证的 GitHub 代理更新可执行配置；如需承担风险继续，请设置 OS_INIT_ALLOW_UNVERIFIED_PROXY=1"
	fi
}

github_latest_version() {
    local repo="$1" prefix="${2:-v}"
    local url latest
    url="$(rewrite_download_url "https://github.com/${repo}/releases/latest")"
    if command -v curl &>/dev/null; then
        latest="$(curl -fsSI \
            --connect-timeout "${DOWNLOAD_TIMEOUT:-30}" \
            --max-time "${DOWNLOAD_TIMEOUT:-30}" \
            "$url" 2>/dev/null | grep -i '^location:' | sed "s|.*/${prefix}||" | tr -d '\r\n')"
    elif command -v wget &>/dev/null; then
        latest="$(wget --server-response --spider \
            --timeout="${DOWNLOAD_TIMEOUT:-30}" \
            "$url" 2>&1 | grep -i 'Location:' | tail -1 | sed "s|.*/${prefix}||" | tr -d '\r\n')"
    else
        die "需要 curl 或 wget 才能查询 GitHub 最新版本"
    fi
    [[ -n "$latest" ]] || die "无法获取 ${repo} 最新版本"
    echo "$latest"
}

git_clone_depth() {
	local depth="$1" url="$2" dest="$3" final_url
	final_url="$(rewrite_download_url "$url")"
	if [[ "$final_url" != "$url" && "${OS_INIT_ALLOW_UNVERIFIED_PROXY:-0}" != "1" ]]; then
		die "经 GitHub 代理克隆可执行配置缺少可验证完整性，已拒绝；如需承担风险继续，请设置 OS_INIT_ALLOW_UNVERIFIED_PROXY=1"
	fi
	git_with_proxy clone --depth="$depth" "$final_url" "$dest"
}

git_clone_depth_branch() {
	local depth="$1" branch="$2" url="$3" dest="$4" final_url
	final_url="$(rewrite_download_url "$url")"
	if [[ "$final_url" != "$url" && "${OS_INIT_ALLOW_UNVERIFIED_PROXY:-0}" != "1" ]]; then
		die "经 GitHub 代理克隆可执行配置缺少可验证完整性，已拒绝；如需承担风险继续，请设置 OS_INIT_ALLOW_UNVERIFIED_PROXY=1"
	fi
	git_with_proxy clone --depth="$depth" -b "$branch" "$final_url" "$dest"
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

# Download content that will be executed or installed as a binary. Direct
# official HTTPS remains supported. If a GitHub proxy rewrites the transport,
# an out-of-band expected SHA-256 is required unless the user explicitly opts
# into the legacy insecure behavior.
download_file_verified() {
	local url="$1" dest="$2" expected="${3:-}" final_url actual
	final_url="$(rewrite_download_url "$url")"
	if [[ -z "$expected" && "$final_url" != "$url" && "${OS_INIT_ALLOW_UNVERIFIED_PROXY:-0}" != "1" ]]; then
		die "经 GitHub 代理下载可执行内容时必须配置对应的 SHA-256；如需承担风险继续，请设置 OS_INIT_ALLOW_UNVERIFIED_PROXY=1"
	fi
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

# Reliable update for shallow git clones (git pull often fails with divergent branches)
git_update_shallow() {
	local dir="$1"
	local branch
	assert_git_remote_secure "$dir"
    branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null) || branch="master"
    git_with_proxy -C "$dir" fetch origin --depth=1 -q
    git_with_proxy -C "$dir" reset --hard "origin/$branch"
}
