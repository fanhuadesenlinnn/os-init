#!/bin/bash
set -euo pipefail

# Kernel & network optimization: sysctl, limits, scheduler, autotune, IPv4 priority, RPS/MSS
# Safe to re-run -- idempotent
#
# Usage:
#   ./optimize.sh                           # apply all optimizations
#   ./optimize.sh sysctl limits scheduler   # apply only listed components
#
# Requires: sudo (all files are system-level)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$REPO_DIR/lib.sh"

ALL_COMPONENTS=(sysctl limits scheduler autotune ipv4 network)
parse_update_flag "$@"
COMPONENTS=("${_CLEAN_ARGS[@]}")
if [[ ${#COMPONENTS[@]} -eq 0 ]]; then
    COMPONENTS=("${ALL_COMPONENTS[@]}")
fi

want() {
    local c
    for c in "${COMPONENTS[@]}"; do [[ "$c" == "$1" ]] && return 0; done
    return 1
}

STEP=0
count_steps() {
    local total=0
    for c in "${ALL_COMPONENTS[@]}"; do want "$c" && total=$((total + 1)); done
    echo "$total"
}
TOTAL=$(count_steps)
next() { STEP=$((STEP + 1)); echo "[$STEP/$TOTAL] $1..."; }

append_if_missing() {
    local target="$1"
    local marker="$2"
    local content="$3"
    if grep -qF "$marker" "$target" 2>/dev/null; then
        skip "already present in $target"
    else
        backup_file "$target"
        echo "$content" | sudo tee -a "$target" >/dev/null
        echo "  appended to $target"
    fi
}

install_ipv4_priority() {
    local target="/etc/gai.conf"

    if ! sudo test -f "$target"; then
        sudo install -m 0644 /dev/null "$target"
    fi

    if sudo grep -qF "# os-init -- prefer IPv4 addresses when both A and AAAA exist" "$target"; then
        skip "IPv4 priority already managed in $target"
        return
    fi

    if sudo grep -Eq '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100' "$target"; then
        skip "IPv4 priority already present in $target"
        return
    fi

    backup_file "$target" >/dev/null || true
    sudo tee -a "$target" >/dev/null <<'EOF'
# os-init -- prefer IPv4 addresses when both A and AAAA exist
precedence ::ffff:0:0/96  100
EOF
    echo "  done: $target (IPv4 preferred)"
}

remove_ipv4_priority() {
    local target="/etc/gai.conf"
    [[ -f "$target" ]] || return
    sudo sed -i '/^# os-init -- prefer IPv4 addresses when both A and AAAA exist$/,+1d' "$target" 2>/dev/null || true
    remove "os-init IPv4 priority entry removed from $target"
}

TITLE="Optimization"
[[ "$UNINSTALL" == true ]] && TITLE="Revert"
echo "=== Kernel & Network $TITLE ==="
echo "  Components: ${COMPONENTS[*]}"
echo ""

if [[ "$UNINSTALL" == true ]]; then
    if want "network"; then
        echo "[REVERT] network queue and MSS tuning..."
        if [[ -x /usr/local/sbin/os-init-network-tune.sh ]]; then
            sudo /usr/local/sbin/os-init-network-tune.sh --revert 2>/dev/null || true
        fi
        sudo systemctl stop os-init-network-tune.service 2>/dev/null || true
        sudo systemctl disable os-init-network-tune.service 2>/dev/null || true
        sudo rm -f /etc/systemd/system/os-init-network-tune.service /usr/local/sbin/os-init-network-tune.sh
        sudo systemctl daemon-reload 2>/dev/null || true
        remove "network tune service and script removed"
    fi

    if want "ipv4"; then
        echo "[REVERT] IPv4 priority..."
        remove_ipv4_priority
    fi

    if want "autotune"; then
        echo "[REVERT] autotune service..."
        sudo systemctl stop autotune.service 2>/dev/null || true
        sudo systemctl disable autotune.service 2>/dev/null || true
        sudo rm -f /etc/systemd/system/autotune.service /usr/local/sbin/autotune.sh /usr/bin/autotune.sh
        sudo systemctl daemon-reload
        remove "autotune service and script removed"
    fi

    if want "scheduler"; then
        echo "[REVERT] I/O scheduler..."
        sudo rm -f /etc/udev/rules.d/60-scheduler.rules
        sudo udevadm control --reload 2>/dev/null || true
        remove "scheduler udev rule removed"
    fi

	if want "limits"; then
		echo "[REVERT] limits..."
		sudo rm -f /etc/security/limits.d/99-os-init.conf
		sudo rm -f /etc/systemd/system.conf.d/99-os-init.conf /etc/systemd/user.conf.d/99-os-init.conf
		for pam_file in \
			/etc/pam.d/common-session \
			/etc/pam.d/common-session-noninteractive \
			/etc/pam.d/system-auth \
			/etc/pam.d/password-auth \
			/etc/pam.d/system-login; do
			[[ -f "$pam_file" ]] || continue
			sudo sed -i '/^# os-init -- enable pam_limits$/ {N;/\nsession required pam_limits\.so$/d;}' "$pam_file"
		done
		sudo systemctl daemon-reexec 2>/dev/null || true
        remove "os-init limits drop-ins removed"
    fi

    if want "sysctl"; then
        echo "[REVERT] sysctl..."
        sudo rm -f /etc/sysctl.d/99-os-init.conf
        sudo sysctl --system >/dev/null 2>&1 || true
        remove "os-init sysctl drop-in removed"
    fi

    echo ""
    echo "=== Kernel optimization revert complete ==="
    echo "  A reboot is recommended to fully apply reverted settings."
    exit 0
fi

# ── sysctl.conf ───────────────────────────────────────────────────────────────
if want "sysctl"; then
    next "sysctl drop-in"

    SYSCTL_TARGET="/etc/sysctl.d/99-os-init.conf"
    backup_file "$SYSCTL_TARGET" >/dev/null || true
    sudo install -m 0644 -D "$SCRIPT_DIR/sysctl.conf" "$SYSCTL_TARGET"
    sudo sysctl --system >/dev/null 2>&1 || echo "  warning: some sysctl params may require autotune/reboot"
    echo "  done: $SYSCTL_TARGET (from modules/kernel/sysctl.conf)"
fi

# ── limits ────────────────────────────────────────────────────────────────────
if want "limits"; then
    next "file descriptor & process limits"

    LIMITS_TARGET="/etc/security/limits.d/99-os-init.conf"
    backup_file "$LIMITS_TARGET" >/dev/null || true
    sudo install -m 0644 -D "$SCRIPT_DIR/limits.conf" "$LIMITS_TARGET"
    echo "  done: $LIMITS_TARGET (from modules/kernel/limits.conf)"

    # PAM session modules -- append if missing
    for pam_file in \
        /etc/pam.d/common-session \
        /etc/pam.d/common-session-noninteractive \
        /etc/pam.d/system-auth \
        /etc/pam.d/password-auth \
        /etc/pam.d/system-login; do
        [[ -f "$pam_file" ]] || continue
        append_if_missing "$pam_file" \
            "pam_limits.so" \
            "# os-init -- enable pam_limits
session required pam_limits.so"
    done

    sudo install -m 0755 -d /etc/systemd/system.conf.d /etc/systemd/user.conf.d
    printf '%s\n' '[Manager]' 'DefaultLimitNOFILE=1048576' 'DefaultLimitNPROC=65535' \
        | sudo tee /etc/systemd/system.conf.d/99-os-init.conf >/dev/null
    printf '%s\n' '[Manager]' 'DefaultLimitNOFILE=1048576' 'DefaultLimitNPROC=65535' \
        | sudo tee /etc/systemd/user.conf.d/99-os-init.conf >/dev/null
    sudo systemctl daemon-reexec 2>/dev/null || true

    echo "  done: limits + PAM + systemd"
fi

# ── scheduler ─────────────────────────────────────────────────────────────────
if want "scheduler"; then
    next "I/O scheduler (none -- best for SSD/NVMe)"

    sudo install -m 0644 -D "$SCRIPT_DIR/60-scheduler.rules" /etc/udev/rules.d/60-scheduler.rules
    sudo udevadm control --reload 2>/dev/null || true
    sudo udevadm trigger 2>/dev/null || true
    echo "  done: /etc/udev/rules.d/60-scheduler.rules (from modules/kernel/60-scheduler.rules)"
fi

# ── autotune ──────────────────────────────────────────────────────────────────
if want "autotune"; then
    next "RAM-based autotune (conntrack, tw_buckets, file-max)"

    sudo install -m 0755 -D "$SCRIPT_DIR/autotune.sh" /usr/local/sbin/autotune.sh

    sudo install -m 0644 -D "$SCRIPT_DIR/autotune.service" /etc/systemd/system/autotune.service
    sudo systemctl daemon-reload
    sudo systemctl enable autotune.service 2>/dev/null || true
    echo "  done: /usr/local/sbin/autotune.sh + autotune.service (from modules/kernel/)"
fi

# ── IPv4 address selection priority ───────────────────────────────────────────
if want "ipv4"; then
    next "IPv4 priority in gai.conf"

    install_ipv4_priority
fi

# ── network queue and MSS tune service ────────────────────────────────────────
if want "network"; then
    next "RPS/RSS network queues and TCP MSS clamp"

    require_systemd
    sudo install -m 0755 -D "$SCRIPT_DIR/network-tune.sh" /usr/local/sbin/os-init-network-tune.sh
    sudo install -m 0644 -D "$SCRIPT_DIR/os-init-network-tune.service" /etc/systemd/system/os-init-network-tune.service
    sudo systemctl daemon-reload
    sudo systemctl enable os-init-network-tune.service 2>/dev/null || true
    sudo systemctl start os-init-network-tune.service 2>/dev/null || sudo /usr/local/sbin/os-init-network-tune.sh
    echo "  done: /etc/systemd/system/os-init-network-tune.service"
fi

echo ""
echo "=== Kernel optimization complete ==="
echo "  Applied: ${COMPONENTS[*]}"
echo ""
echo "  A reboot is recommended to fully apply all changes."
