#!/usr/bin/env bash
set -euo pipefail

# OS-INIT -- dynamic kernel tuning based on RAM.
# Tunes: nf_conntrack_max, tcp_max_tw_buckets, fs.file-max, TCP socket buffers.

if [ "$EUID" -ne 0 ]; then
    echo "Error: must be run as root" >&2
    exit 1
fi

MIN_CONNTRACK=65536
PER_GB=65536

set_sysctl_if_exists() {
    local key="$1" value="$2" path current
    path="/proc/sys/${key//./\/}"
    [ -e "$path" ] || return 0

    current=$(sysctl -n "$key" 2>/dev/null || echo "")
    if [ "$current" != "$value" ]; then
        echo "Setting $key=$value (was=$current)"
        sysctl -w "$key=$value" >/dev/null 2>&1 || true
    fi
}

MEM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
RAM_GB=$(awk "BEGIN {ram_gb = $MEM_KB / 1024 / 1024; print (ram_gb == int(ram_gb)) ? int(ram_gb) : int(ram_gb) + 1}")
[ "$RAM_GB" -lt 1 ] && RAM_GB=1

TARGET_MAX=$((RAM_GB * PER_GB))
[ "$TARGET_MAX" -lt "$MIN_CONNTRACK" ] && TARGET_MAX=$MIN_CONNTRACK

# conntrack_max
if ! lsmod | grep -q "^nf_conntrack "; then
    if modprobe nf_conntrack 2>/dev/null; then
        sleep 1
    fi
fi
if [ -f "/proc/sys/net/netfilter/nf_conntrack_max" ]; then
    CURRENT=$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo 0)
    if [ "$CURRENT" -ne "$TARGET_MAX" ]; then
        echo "Setting nf_conntrack_max=$TARGET_MAX (RAM=${RAM_GB}G, was=$CURRENT)"
        sysctl -w net.netfilter.nf_conntrack_max="$TARGET_MAX" >/dev/null
    fi
fi

# tcp_max_tw_buckets
TW_CURRENT=$(sysctl -n net.ipv4.tcp_max_tw_buckets 2>/dev/null || echo 0)
if [ "$TW_CURRENT" -ne "$TARGET_MAX" ]; then
    echo "Setting tcp_max_tw_buckets=$TARGET_MAX (RAM=${RAM_GB}G, was=$TW_CURRENT)"
    sysctl -w net.ipv4.tcp_max_tw_buckets="$TARGET_MAX" >/dev/null
fi

# fs.file-max
FILE_MAX_PER_GB=262144
FILE_MAX_TARGET=$((RAM_GB * FILE_MAX_PER_GB))
[ "$FILE_MAX_TARGET" -lt 1048576 ] && FILE_MAX_TARGET=1048576

FM_CURRENT=$(sysctl -n fs.file-max 2>/dev/null || echo 0)
if [ "$FM_CURRENT" -ne "$FILE_MAX_TARGET" ]; then
    echo "Setting fs.file-max=$FILE_MAX_TARGET (RAM=${RAM_GB}G, was=$FM_CURRENT)"
    sysctl -w fs.file-max="$FILE_MAX_TARGET" >/dev/null
fi

# TCP/UDP buffer sizing. Use 5% of RAM with a 16 MiB floor.
BUFFER_TARGET=$((MEM_KB * 1024 * 5 / 100))
[ "$BUFFER_TARGET" -lt 16777216 ] && BUFFER_TARGET=16777216

set_sysctl_if_exists net.core.rmem_max "$BUFFER_TARGET"
set_sysctl_if_exists net.core.wmem_max "$BUFFER_TARGET"
set_sysctl_if_exists net.ipv4.tcp_rmem "4096 87380 $BUFFER_TARGET"
set_sysctl_if_exists net.ipv4.tcp_wmem "4096 65536 $BUFFER_TARGET"
set_sysctl_if_exists net.ipv4.tcp_congestion_control_version 3

# NIC ring buffers - set to hardware max for each active interface when ethtool exists.
if command -v ethtool >/dev/null 2>&1 && command -v ip >/dev/null 2>&1; then
    for IFACE in $(ip -o link show up | awk -F': ' '{print $2}' | grep -vE '^(lo|docker|br-|veth|tap|virbr)'); do
        RX_MAX=$(ethtool -g "$IFACE" 2>/dev/null | awk '/Pre-set/,/Current/' | awk '/^RX:/{print $2}' | head -1)
        RX_CUR=$(ethtool -g "$IFACE" 2>/dev/null | awk '/Current/,0' | awk '/^RX:/{print $2}' | head -1)
        TX_MAX=$(ethtool -g "$IFACE" 2>/dev/null | awk '/Pre-set/,/Current/' | awk '/^TX:/{print $2}' | head -1)

        if [ -n "$RX_MAX" ] && [ -n "$RX_CUR" ] && [ "$RX_CUR" -lt "$RX_MAX" ] 2>/dev/null; then
            echo "Setting $IFACE ring buffer RX=$RX_MAX TX=$TX_MAX (was RX=$RX_CUR)"
            ethtool -G "$IFACE" rx "$RX_MAX" tx "${TX_MAX:-$RX_MAX}" 2>/dev/null || true
        else
            echo "$IFACE ring buffer already at max (${RX_CUR:-unknown}), nothing to do."
        fi
    done
else
    echo "Skipping NIC ring buffer tuning because ethtool or ip is unavailable."
fi
