#!/usr/bin/env bash
set -euo pipefail

# OS-INIT -- runtime network queue and MSS tuning.

if [[ "$EUID" -ne 0 ]]; then
    echo "Error: must be run as root" >&2
    exit 1
fi

mode="${1:-apply}"
STATE_DIR="${OS_INIT_SYSTEM_STATE_DIR:-/var/lib/os-init}"
STATE_FILE="${STATE_DIR}/network-tune.state"

should_skip_iface() {
    case "$1" in
        lo|docker*|veth*|br-*|any|tung3|sit0|tun*|wg*|tap*|virbr*)
            return 0
            ;;
    esac
    return 1
}

cpu_mask() {
    local cpus="${1:-1}" groups rem segment i
    local -a parts=()

    [[ "$cpus" =~ ^[0-9]+$ ]] || cpus=1
    (( cpus < 1 )) && cpus=1

    groups=$(((cpus + 31) / 32))
    rem="$cpus"
    for ((i = 0; i < groups; i++)); do
        if (( rem >= 32 )); then
            segment="ffffffff"
            rem=$((rem - 32))
        else
            printf -v segment '%x' "$(((1 << rem) - 1))"
            rem=0
        fi
        parts=("$segment" "${parts[@]}")
    done

    local IFS=,
    echo "${parts[*]}"
}

interfaces() {
    local path iface
    for path in /sys/class/net/*; do
        [[ -e "$path" ]] || continue
        iface="$(basename "$path")"
        should_skip_iface "$iface" && continue
        echo "$iface"
    done
}

tune_ring_buffer() {
    local iface="$1" rx_max tx_max

    command -v ethtool >/dev/null 2>&1 || return 0
    rx_max="$(ethtool -g "$iface" 2>/dev/null | awk '/Pre-set maximums/{preset=1; next} preset && /^RX:/{print $2; exit}')"
    tx_max="$(ethtool -g "$iface" 2>/dev/null | awk '/Pre-set maximums/{preset=1; next} preset && /^TX:/{print $2; exit}')"

    [[ "$rx_max" =~ ^[0-9]+$ ]] || return 0
    [[ "$tx_max" =~ ^[0-9]+$ ]] || tx_max="$rx_max"
    ethtool -G "$iface" rx "$rx_max" tx "$tx_max" >/dev/null 2>&1 || true
}

snapshot_state() {
    local tmp iface path value rx tx mss_present=0 initial=0
    install -d -m 0700 "$STATE_DIR"
    tmp="$(mktemp "${TMPDIR:-/tmp}/os-init-network-state.XXXXXX")"
    if [[ -f "$STATE_FILE" ]]; then
        cp -a "$STATE_FILE" "$tmp"
    else
        initial=1
    fi

    for iface in $(interfaces); do
        for path in /sys/class/net/"$iface"/queues/rx-*/rps_cpus; do
            [[ -f "$path" ]] || continue
            grep -Fq "rps|${path}|" "$tmp" 2>/dev/null && continue
            value="$(cat "$path")"
            printf 'rps|%s|%s\n' "$path" "$value" >> "$tmp"
        done
        for path in /sys/class/net/"$iface"/queues/rx-*/rps_flow_cnt; do
            [[ -f "$path" ]] || continue
            grep -Fq "flow|${path}|" "$tmp" 2>/dev/null && continue
            value="$(cat "$path")"
            printf 'flow|%s|%s\n' "$path" "$value" >> "$tmp"
        done
        if command -v ethtool >/dev/null 2>&1; then
            rx="$(ethtool -g "$iface" 2>/dev/null | awk '/Current hardware settings/{current=1; next} current && /^RX:/{print $2; exit}')"
            tx="$(ethtool -g "$iface" 2>/dev/null | awk '/Current hardware settings/{current=1; next} current && /^TX:/{print $2; exit}')"
            if [[ "$rx" =~ ^[0-9]+$ && "$tx" =~ ^[0-9]+$ ]] && ! grep -Fq "ring|${iface}|" "$tmp" 2>/dev/null; then
                printf 'ring|%s|%s|%s\n' "$iface" "$rx" "$tx" >> "$tmp"
            fi
        fi
    done
    if [[ "$initial" == "1" ]]; then
        value="$(sysctl -n net.core.rps_sock_flow_entries 2>/dev/null || echo 0)"
        printf 'sysctl|net.core.rps_sock_flow_entries|%s\n' "$value" >> "$tmp"
        if command -v iptables >/dev/null 2>&1 && iptables -t mangle -C POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
            mss_present=1
        fi
        printf 'mss|%s\n' "$mss_present" >> "$tmp"
    fi
    install -m 0600 "$tmp" "$STATE_FILE"
    rm -f "$tmp"
}

apply_rps() {
    local cpus mask iface rps_file flow_file

    cpus="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
    mask="$(cpu_mask "$cpus")"

    for iface in $(interfaces); do
        tune_ring_buffer "$iface"
        for rps_file in /sys/class/net/"$iface"/queues/rx-*/rps_cpus; do
            [[ -f "$rps_file" ]] && echo "$mask" > "$rps_file"
        done
        for flow_file in /sys/class/net/"$iface"/queues/rx-*/rps_flow_cnt; do
            [[ -f "$flow_file" ]] && echo "4096" > "$flow_file"
        done
    done

    sysctl -w net.core.rps_sock_flow_entries=32768 >/dev/null 2>&1 || true
}

apply_mss_clamp() {
    command -v iptables >/dev/null 2>&1 || return 0

    iptables -t mangle -C POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
        iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
}

restore_state() {
    local kind first second third original_mss=""
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "Warning: no OS Init network snapshot; preserving current runtime tuning" >&2
        return 0
    fi
    while IFS='|' read -r kind first second third; do
        case "$kind" in
            rps|flow)
                [[ "$first" == /sys/class/net/*/queues/rx-*/rps_* && "$second" =~ ^[0-9a-fA-F,]+$ ]] || continue
                [[ -f "$first" ]] && printf '%s\n' "$second" > "$first"
                ;;
            ring)
                [[ "$first" =~ ^[A-Za-z0-9_.:-]+$ && "$second" =~ ^[0-9]+$ && "$third" =~ ^[0-9]+$ ]] || continue
                command -v ethtool >/dev/null 2>&1 && ethtool -G "$first" rx "$second" tx "$third" >/dev/null 2>&1 || true
                ;;
            sysctl)
                [[ "$first" == "net.core.rps_sock_flow_entries" && "$second" =~ ^[0-9]+$ ]] || continue
                sysctl -w "${first}=${second}" >/dev/null 2>&1 || true
                ;;
            mss) original_mss="$first" ;;
        esac
    done < "$STATE_FILE"
    if [[ "$original_mss" == "0" ]] && command -v iptables >/dev/null 2>&1; then
        iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    fi
    rm -f "$STATE_FILE"
}

case "$mode" in
    apply)
        snapshot_state
        apply_rps
        apply_mss_clamp
        ;;
    --revert|revert)
        restore_state
        ;;
    *)
        echo "Usage: $0 [apply|--revert]" >&2
        exit 2
        ;;
esac
