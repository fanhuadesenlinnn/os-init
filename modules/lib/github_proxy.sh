#!/usr/bin/env bash
# Shared GitHub URL proxy semantics for portable and Arch providers.

url_encode() {
    local value="$1" encoded="" char hex i LC_ALL=C
    i=0
    while (( i < ${#value} )); do
        char="${value:i:1}"
        case "$char" in
            [a-zA-Z0-9.~_-]) encoded+="$char" ;;
            *)
                printf -v hex '%02X' "'$char"
                encoded+="%${hex}"
                ;;
        esac
        i=$((i + 1))
    done
    printf '%s' "$encoded"
}

render_url_proxy() {
    local proxy="$1" url="$2" encoded
    if [[ "$proxy" == *"{url_encoded}"* ]]; then
        encoded="$(url_encode "$url")"
        printf '%s' "${proxy//\{url_encoded\}/$encoded}"
    elif [[ "$proxy" == *"{url}"* ]]; then
        printf '%s' "${proxy//\{url\}/$url}"
    else
        while [[ "$proxy" == */ ]]; do
            proxy="${proxy%/}"
        done
        printf '%s' "${proxy}/$url"
    fi
}

is_github_url() {
    case "$1" in
        https://github.com/*|https://raw.githubusercontent.com/*|\
        https://objects.githubusercontent.com/*|https://github-releases.githubusercontent.com/*|\
        https://release-assets.githubusercontent.com/*|https://codeload.github.com/*|\
        https://api.github.com/*)
            return 0
            ;;
        *) return 1 ;;
    esac
}

rewrite_github_url() {
    local url="$1"
    if [[ -n "${GITHUB_PROXY:-}" ]] && is_github_url "$url"; then
        render_url_proxy "$GITHUB_PROXY" "$url"
    else
        printf '%s' "$url"
    fi
}

# Prefix and raw-{url} proxies can be applied to arbitrary child Git commands
# without changing the repository's persisted origin. URL-encoded templates
# are handled by the explicit clone/fetch helpers, where the full URL is known.
run_with_github_git_proxy() {
    local base count key_name value_name
    if [[ -z "${GITHUB_PROXY:-}" ]]; then
        "$@"
        return
    fi
    if [[ "$GITHUB_PROXY" == *"{url_encoded}"* ]]; then
        "$@"
        return
    fi
    base="$(render_url_proxy "$GITHUB_PROXY" "https://github.com/")"
    count="${GIT_CONFIG_COUNT:-0}"
    key_name="GIT_CONFIG_KEY_${count}"
    value_name="GIT_CONFIG_VALUE_${count}"
    (
        export GIT_CONFIG_COUNT=$((count + 1))
        export "${key_name}=url.${base}.insteadOf"
        export "${value_name}=https://github.com/"
        "$@"
    )
}
