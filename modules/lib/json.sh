#!/usr/bin/env bash
# Sourced by modules/lib.sh.

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    printf '%s' "$value"
}

json_array_from_csv() {
    local csv="${1:-}" item first=true
    local -a items=()
    printf '['
    IFS=',' read -r -a items <<< "$csv"
    for item in "${items[@]}"; do
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        [[ -z "$item" ]] && continue
        if [[ "$first" == true ]]; then
            first=false
        else
            printf ','
        fi
        printf '"%s"' "$(json_escape "$item")"
    done
    printf ']'
}
