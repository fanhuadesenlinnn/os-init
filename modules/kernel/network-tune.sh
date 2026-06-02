#!/usr/bin/env bash
set -euo pipefail

# OS-INIT -- runtime network queue and MSS tuning.

if [[ "$EUID" -ne 0 ]]; then
    echo "Error: must be run as root" >&2
    exit 1
fi

mode="${1:-apply}"

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

reset_rps() {
    local iface rps_file flow_file

    for iface in $(interfaces); do
        for rps_file in /sys/class/net/"$iface"/queues/rx-*/rps_cpus; do
            [[ -f "$rps_file" ]] && echo "0" > "$rps_file"
        done
        for flow_file in /sys/class/net/"$iface"/queues/rx-*/rps_flow_cnt; do
            [[ -f "$flow_file" ]] && echo "0" > "$flow_file"
        done
    done

    sysctl -w net.core.rps_sock_flow_entries=0 >/dev/null 2>&1 || true
}

apply_mss_clamp() {
    command -v iptables >/dev/null 2>&1 || return 0

    iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
}

reset_mss_clamp() {
    command -v iptables >/dev/null 2>&1 || return 0

    iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
}

case "$mode" in
    apply)
        apply_rps
        apply_mss_clamp
        ;;
    --revert|revert)
        reset_mss_clamp
        reset_rps
        ;;
    *)
        echo "Usage: $0 [apply|--revert]" >&2
        exit 2
        ;;
esac
