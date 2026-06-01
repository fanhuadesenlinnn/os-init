#!/bin/bash
set -euo pipefail

# OpenSSH server hardening (kickstart-managed sshd_config)
# Safe to re-run -- idempotent
# Requires: sudo
#
# Usage:
#   sudo ./setup.sh
#   sudo ./setup.sh --uninstall

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$REPO_DIR/lib.sh"
parse_update_flag "$@"

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
SSHD_DROPIN="${SSHD_DROPIN_DIR}/99-os-init.conf"

sshd_service_name() {
    if systemctl list-unit-files sshd.service >/dev/null 2>&1; then
        echo "sshd"
    else
        echo "ssh"
    fi
}

sshd_supports_dropin() {
    [[ -d "$SSHD_DROPIN_DIR" ]] && grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$SSHD_CONFIG"
}

validate_and_reload_sshd() {
    local service
    sudo sshd -t || die "sshd 配置校验失败，已停止应用"
    service="$(sshd_service_name)"
    sudo systemctl reload "$service" 2>/dev/null || sudo systemctl restart "$service" 2>/dev/null || true
}

if [[ "$UNINSTALL" == true ]]; then
    echo "=== SSH server -- Revert ==="
    echo ""
    if [[ -f "$SSHD_DROPIN" ]]; then
        sudo rm -f "$SSHD_DROPIN"
        validate_and_reload_sshd
        remove "sshd drop-in removed"
    elif compgen -G "/etc/ssh/sshd_config.bak-os-init.*" >/dev/null || [[ -f /etc/ssh/sshd_config.bak-kickstart ]]; then
        backup="$(ls -1t /etc/ssh/sshd_config.bak-os-init.* /etc/ssh/sshd_config.bak-kickstart 2>/dev/null | head -1)"
        sudo cp "$backup" "$SSHD_CONFIG"
        validate_and_reload_sshd
        remove "sshd_config restored from $backup"
    else
        skip "no sshd backup found -- cannot revert"
    fi
    echo ""
    echo "=== SSH revert complete ==="
    exit 0
fi

echo "=== SSH server hardening ==="
echo ""

if [[ ! -f "$SSHD_CONFIG" ]]; then
    skip "openssh-server not installed (/etc/ssh/sshd_config missing)"
    exit 0
fi

echo "[1/1] Applying hardened sshd config..."
if sshd_supports_dropin; then
    backup_file "$SSHD_DROPIN" >/dev/null || true
    sudo install -m 0755 -d "$SSHD_DROPIN_DIR"
    sudo tee "$SSHD_DROPIN" >/dev/null <<'EOF'
# os-init -- hardened SSH defaults
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
GSSAPIAuthentication no
UsePAM yes
UseDNS no
PermitRootLogin prohibit-password
ClientAliveInterval 120
ClientAliveCountMax 40
EOF
    validate_and_reload_sshd
    echo "  done: $SSHD_DROPIN (password auth DISABLED)"
else
    warn "当前 sshd_config 未启用 /etc/ssh/sshd_config.d/*.conf Include，回退为备份后覆盖主配置"
    backup_file "$SSHD_CONFIG" >/dev/null || true
    sudo install -m 0644 "$SCRIPT_DIR/sshd_config" "$SSHD_CONFIG"
    validate_and_reload_sshd
    echo "  done: $SSHD_CONFIG (password auth DISABLED)"
fi

echo ""
echo "=== SSH hardening complete ==="
