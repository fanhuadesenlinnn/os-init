#!/bin/bash
set -euo pipefail

# Install only native build prerequisites needed by user-level development
# runtimes. Language runtimes themselves remain managed by mise.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_DIR/lib.sh"

parse_update_flag "$@"
[[ "$UNINSTALL" != true ]] || die "开发运行时编译依赖是共享系统能力，不支持自动卸载"

echo "=== $(os_init_text "开发运行时编译依赖" "Development runtime build prerequisites") ==="

if is_macos; then
    if xcode-select -p >/dev/null 2>&1; then
        skip "Xcode Command Line Tools 已安装"
    else
        install "请求安装 Xcode Command Line Tools"
        xcode-select --install
        warn "请在系统弹窗中完成安装，然后重新运行验证"
    fi
elif is_arch; then
    pkg_install base-devel pkgconf openssl zlib libffi bzip2 readline sqlite xz tk util-linux-libs
elif [[ "$OS_FAMILY" == "debian" ]]; then
    pkg_install build-essential pkg-config libssl-dev zlib1g-dev libffi-dev libbz2-dev libreadline-dev libsqlite3-dev liblzma-dev tk-dev uuid-dev
elif [[ "$OS_FAMILY" == "redhat" ]]; then
    pkg_install gcc gcc-c++ make pkgconf-pkg-config openssl-devel zlib-devel libffi-devel bzip2-devel readline-devel sqlite-devel xz-devel tk-devel libuuid-devel
else
    die "不支持的开发依赖平台: ${OS_FAMILY:-$OS}"
fi

echo "=== $(os_init_text "开发运行时编译依赖完成" "Development runtime build prerequisites complete") ==="
