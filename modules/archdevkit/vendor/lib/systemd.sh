#!/usr/bin/env bash
# systemd 公共操作：服务探测、启用系统服务和启用用户服务。

systemd_system_unit_exists() {
  local unit="$1"
  [[ -n "${unit}" ]] || die "systemd unit 名为空"

  [[ -e "/etc/systemd/system/${unit}" ]] && return 0
  [[ -e "/usr/lib/systemd/system/${unit}" ]] && return 0
  [[ -e "/lib/systemd/system/${unit}" ]] && return 0

  systemctl list-unit-files "${unit}" --no-legend 2>/dev/null | awk '{print $1}' | grep -Fxq "${unit}"
}

reload_systemd_system() {
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ sudo systemctl daemon-reload"
    return 0
  fi

  run_sudo systemctl daemon-reload || \
    log_warn "systemd 服务刷新失败，请稍后手动执行：sudo systemctl daemon-reload"
}

enable_user_service() {
  local service="$1"
  [[ -n "${service}" ]] || die "systemd 用户服务名为空"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ systemctl --user daemon-reload"
    echo "+ systemctl --user enable --now ${service}"
    return 0
  fi

  systemctl --user daemon-reload || {
    log_warn "systemd 用户服务刷新失败，请登录图形会话后手动执行：systemctl --user daemon-reload"
    return 0
  }
  systemctl --user enable --now "${service}" || \
    log_warn "用户服务启用失败，可稍后手动执行：systemctl --user enable --now ${service}"
}

enable_system_service() {
  local service="$1"
  [[ -n "${service}" ]] || die "systemd 系统服务名为空"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ sudo systemctl daemon-reload"
    echo "+ sudo systemctl enable --now ${service}"
    echo "+ sudo systemctl is-active --quiet ${service}"
    return 0
  fi

  reload_systemd_system
  run_sudo systemctl enable --now "${service}" || {
    log_warn "系统服务启用失败，可稍后手动执行：sudo systemctl enable --now ${service}"
    return 1
  }

  sleep 2
  if run_sudo systemctl is-active --quiet "${service}"; then
    log_info "系统服务已启动：${service}"
    return 0
  fi

  log_warn "系统服务未保持 active：${service}"
  run_sudo journalctl -u "${service}" -n 50 --no-pager || true
  return 1
}

enable_system_service_on_boot() {
  local service="$1"
  [[ -n "${service}" ]] || die "systemd 系统服务名为空"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ sudo systemctl daemon-reload"
    echo "+ sudo systemctl enable ${service}"
    return 0
  fi

  reload_systemd_system
  run_sudo systemctl enable "${service}" || {
    log_warn "系统服务开机启用失败，可稍后手动执行：sudo systemctl enable ${service}"
    return 1
  }
}
