#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_DIR}"

echo "==> bash syntax"
bash -n install.sh lib/*.sh modules/*.sh modules/desktop/*.sh modules/proxy/*.sh

echo "==> plan json"
bash install.sh plan workstation --json | ruby -rjson -e '
  data = JSON.parse(STDIN.read)
  raise "schema mismatch" unless data.fetch("schemaVersion") == "1"
  raise "command mismatch" unless data.fetch("command") == "plan"
  raise "target mismatch" unless data.fetch("target") == "workstation"
  keys = data.fetch("modules").map { |m| m.fetch("key") }
  %w[base dns proxy desktop_hyprland].each do |key|
    raise "missing module #{key}" unless keys.include?(key)
  end
'

echo "==> module registry"
bash install.sh status --json | ruby -rjson -e '
  data = JSON.parse(STDIN.read)
  keys = data.fetch("modules").map { |m| m.fetch("key") }
  expected = %w[base dns archlinuxcn git ops_toolkit runtime nvim docker fonts shell_zsh proxy desktop_hyprland]
  raise "registry mismatch" unless keys == expected
'
bash install.sh plan base --json | ruby -rjson -e '
  data = JSON.parse(STDIN.read)
  mod = data.fetch("modules").fetch(0)
  raise "base key mismatch" unless mod.fetch("key") == "base"
  raise "base description missing" if mod.fetch("description").empty?
'
base_plan_output="$(bash install.sh plan base)"
for package in dust bottom procs bandwhich sd hyperfine just; do
  [[ "${base_plan_output}" == *"${package}"* ]] || { echo "base plan missing ${package}"; exit 1; }
done
bash install.sh plan dev --json | ruby -rjson -e '
  data = JSON.parse(STDIN.read)
  keys = data.fetch("modules").map { |m| m.fetch("key") }
  raise "dev missing ops_toolkit" unless keys.include?("ops_toolkit")
  raise "dev missing docker" unless keys.include?("docker")
  raise "ops order mismatch" unless keys.index("git") < keys.index("ops_toolkit") && keys.index("ops_toolkit") < keys.index("runtime")
  raise "docker order mismatch" unless keys.index("nvim") < keys.index("docker") && keys.index("docker") < keys.index("fonts")
'

echo "==> user config file"
tmp_home="$(mktemp -d)"
mkdir -p "${tmp_home}/.config/archdevkit"
cat > "${tmp_home}/.config/archdevkit/config.env" <<'EOF'
ARCHDEVKIT_DEFAULT_PROFILE=dev
ENABLE_PROXY=0
ENABLE_OPS_TOOLKIT=0
DNS_SERVERS=223.5.5.5,119.29.29.29
DOCKER_MIRRORS=https://mirror.example.com,https://mirror2.example.com
EOF
HOME="${tmp_home}" bash install.sh plan --json | ruby -rjson -e '
  data = JSON.parse(STDIN.read)
  raise "target mismatch" unless data.fetch("target") == "dev"
  keys = data.fetch("modules").map { |m| m.fetch("key") }
  raise "ops_toolkit should be skipped" if keys.include?("ops_toolkit")
  raise "proxy should be skipped" if keys.include?("proxy")
  raise "missing dns" unless keys.include?("dns")
'
rm -rf "${tmp_home}"

echo "==> config commands"
tmp_home="$(mktemp -d)"
config_file="${tmp_home}/.config/archdevkit/config.env"
HOME="${tmp_home}" bash install.sh config init --config-file "${config_file}"
[[ -f "${config_file}" ]] || { echo "missing generated config"; exit 1; }
grep -q '^ARCHDEVKIT_DEFAULT_PROFILE=' "${config_file}" || { echo "missing default profile config"; exit 1; }
grep -q '^DNS_SERVERS=' "${config_file}" || { echo "missing dns list config"; exit 1; }
grep -q '^OPS_TOOLKIT_REPO=' "${config_file}" || { echo "missing ops toolkit config"; exit 1; }
config_validate_output="$(HOME="${tmp_home}" bash install.sh config validate --config-file "${config_file}")"
[[ "${config_validate_output}" == *"配置校验通过"* ]] || { echo "missing config validate"; exit 1; }
config_show_output="$(HOME="${tmp_home}" bash install.sh config show --config-file "${config_file}")"
[[ "${config_show_output}" == *"[当前安装配置]"* ]] || { echo "missing config show"; exit 1; }
rm -rf "${tmp_home}"

echo "==> status json"
bash install.sh status --json | ruby -rjson -e '
  data = JSON.parse(STDIN.read)
  raise "schema mismatch" unless data.fetch("schemaVersion") == "1"
  raise "command mismatch" unless data.fetch("command") == "status"
  raise "missing modules" unless data.fetch("modules").is_a?(Array)
'
bash install.sh status base --verbose --json | ruby -rjson -e '
  data = JSON.parse(STDIN.read)
  mod = data.fetch("modules").fetch(0)
  raise "missing verbose reason" unless mod.key?("reason")
  raise "missing verbose suggestion" unless mod.key?("suggestion")
'
status_verbose_output="$(bash install.sh status base --verbose)"
[[ "${status_verbose_output}" == *"[状态详情]"* ]] || { echo "missing status details"; exit 1; }
[[ "${status_verbose_output}" == *"建议动作"* ]] || { echo "missing status suggestion"; exit 1; }

echo "==> systemd helpers"
systemd_output="$(
  DRY_RUN=1 bash -c '
    set -Eeuo pipefail
    source lib/common.sh
    source lib/systemd.sh
    enable_system_service mihomo.service
    enable_system_service_on_boot sddm.service
    enable_user_service archdevkit-sing-box.service
  '
)"
[[ "${systemd_output}" == *"sudo systemctl daemon-reload"* ]] || { echo "missing system daemon-reload"; exit 1; }
[[ "${systemd_output}" == *"sudo systemctl enable --now mihomo.service"* ]] || { echo "missing system enable"; exit 1; }
[[ "${systemd_output}" == *"sudo systemctl enable sddm.service"* ]] || { echo "missing boot enable"; exit 1; }
[[ "${systemd_output}" == *"systemctl --user daemon-reload"* ]] || { echo "missing user daemon-reload"; exit 1; }
[[ "${systemd_output}" == *"systemctl --user enable --now archdevkit-sing-box.service"* ]] || { echo "missing user enable"; exit 1; }

echo "==> file helpers"
file_output="$(
  DRY_RUN=1 bash -c '
    set -Eeuo pipefail
    source lib/common.sh
    source lib/files.sh
    write_file_from_stdin /tmp/archdevkit-user.conf 0644 <<<"user"
    write_root_file_from_stdin /etc/archdevkit-root.conf 0600 <<<"root"
    render_template_file files/sing-box/config.json.tpl /tmp/sing-box.json 0600 -e "s/__SING_BOX_MIXED_PORT__/7890/g"
    render_template_root_file files/sing-box/config.json.tpl /etc/sing-box/config.json 0600 -e "s/__SING_BOX_MIXED_PORT__/7890/g"
  '
)"
[[ "${file_output}" == *"write /tmp/archdevkit-user.conf"* ]] || { echo "missing user write"; exit 1; }
[[ "${file_output}" == *"sudo write /etc/archdevkit-root.conf"* ]] || { echo "missing root write"; exit 1; }
[[ "${file_output}" == *"render files/sing-box/config.json.tpl -> /tmp/sing-box.json"* ]] || { echo "missing user render"; exit 1; }
[[ "${file_output}" == *"sudo render files/sing-box/config.json.tpl -> /etc/sing-box/config.json"* ]] || { echo "missing root render"; exit 1; }

echo "==> managed block helpers"
managed_dry_output="$(
  DRY_RUN=1 bash -c '
    set -Eeuo pipefail
    source lib/common.sh
    source lib/files.sh
    printf "value\n" | write_managed_block_from_stdin /tmp/archdevkit-rc proxy-env
    remove_managed_block /tmp/archdevkit-rc proxy-env
  '
)"
[[ "${managed_dry_output}" == *"write managed block proxy-env -> /tmp/archdevkit-rc"* ]] || { echo "missing managed block dry-run write"; exit 1; }
[[ "${managed_dry_output}" == *"remove managed block proxy-env from /tmp/archdevkit-rc"* ]] || { echo "missing managed block dry-run remove"; exit 1; }

managed_dir="$(mktemp -d)"
MANAGED_DIR="${managed_dir}" bash -c '
  set -Eeuo pipefail
  source lib/common.sh
  source lib/files.sh
  file="${MANAGED_DIR}/rc"
  printf "before\n" > "${file}"
  printf "one\n" | write_managed_block_from_stdin "${file}" sample
  printf "two\n" | write_managed_block_from_stdin "${file}" sample
  [[ "$(grep -c "^# >>> ArchDevKit: sample >>>$" "${file}")" -eq 1 ]]
  [[ "$(grep -c "^two$" "${file}")" -eq 1 ]]
  [[ "$(grep -c "^one$" "${file}")" -eq 0 ]]
  remove_managed_block "${file}" sample
  ! grep -q "ArchDevKit: sample" "${file}"
  grep -q "^before$" "${file}"
'
rm -rf "${managed_dir}"

echo "==> tmux config"
tmux_output="$(
  DRY_RUN=1 bash -c '
    set -Eeuo pipefail
    SCRIPT_DIR="$PWD"
    source lib/common.sh
    source lib/files.sh
    source modules/base.sh
    install_tmux_config
  '
)"
[[ "${tmux_output}" == *"render ${PWD}/files/tmux/tmux.conf -> ${HOME}/.tmux.conf"* ]] || { echo "missing tmux config render"; exit 1; }

echo "==> base tool status"
base_tool_output="$(
  bash -c '
    set -Eeuo pipefail
    source lib/common.sh
    source modules/base.sh
    show_base_tool_status_table
  '
)"
[[ "${base_tool_output}" == *"[基础工具状态]"* ]] || { echo "missing base tool table"; exit 1; }
[[ "${base_tool_output}" == *"git"* ]] || { echo "missing git in base tool table"; exit 1; }
[[ "${base_tool_output}" == *"bottom"* ]] || { echo "missing bottom in base tool table"; exit 1; }
[[ "${base_tool_output}" == *"hyperfine"* ]] || { echo "missing hyperfine in base tool table"; exit 1; }

echo "==> ops toolkit module"
ops_tmp="$(mktemp -d)"
OPS_TMP="${ops_tmp}" bash -c '
  set -Eeuo pipefail
  SCRIPT_DIR="$PWD"
  source install_vars
  source lib/common.sh
  source lib/files.sh
  source lib/packages.sh
  source modules/ops_toolkit.sh
  OPS_TOOLKIT_DIR="${OPS_TMP}/repo"
  OPS_TOOLKIT_BIN_DIR="${OPS_TMP}/bin"
  OPS_TOOLKIT_COMMAND=ops
  mkdir -p "${OPS_TOOLKIT_DIR}/.git" "${OPS_TOOLKIT_BIN_DIR}"
  cat > "${OPS_TOOLKIT_DIR}/sshm.sh" <<'\''EOF'\''
#!/usr/bin/env bash
printf "sshm:%s\n" "$*"
EOF
  cat > "${OPS_TOOLKIT_DIR}/linux-admin-toolkit.sh" <<'\''EOF'\''
#!/usr/bin/env bash
printf "linux-admin:%s\n" "$*"
EOF
  install_ops_toolkit_dispatcher
  install_ops_toolkit_script_commands
  list_output="$("${OPS_TOOLKIT_BIN_DIR}/ops" list)"
  [[ "${list_output}" == *"sshm"* ]]
  [[ "${list_output}" == *"linux-admin-toolkit"* ]]
  [[ "$("${OPS_TOOLKIT_BIN_DIR}/sshm" --list)" == "sshm:--list" ]]
  [[ "$("${OPS_TOOLKIT_BIN_DIR}/ops" linux-admin-toolkit --help)" == "linux-admin:--help" ]]
'
rm -rf "${ops_tmp}"

echo "==> package helpers"
package_output="$(
  bash -c '
    set -Eeuo pipefail
    source lib/common.sh
    source lib/packages.sh
    dedupe_list git curl git "" curl jq
  '
)"
[[ "${package_output}" == $'git\ncurl\njq' ]] || { echo "dedupe_list mismatch"; exit 1; }

echo "==> interactive menu ui"
menu_output="$(
  printf '\n2\nproxy\nbad\n1\n' | bash -c '
    set -Eeuo pipefail
    source lib/common.sh
    source lib/ui.sh
    one="$(ask_menu_default "安装目标" "workstation" "base|基础环境" "dev|开发环境" "workstation|完整工作站" "proxy|代理")"
    two="$(ask_menu_default "安装目标" "workstation" "base|基础环境" "dev|开发环境" "workstation|完整工作站" "proxy|代理")"
    three="$(ask_menu_default "安装目标" "workstation" "base|基础环境" "dev|开发环境" "workstation|完整工作站" "proxy|代理")"
    four="$(ask_menu_default "安装目标" "workstation" "base|基础环境" "dev|开发环境" "workstation|完整工作站" "proxy|代理")"
    printf "choices=%s,%s,%s,%s\n" "${one}" "${two}" "${three}" "${four}"
  ' 2>&1
)"
[[ "${menu_output}" == *"1. base"* ]] || { echo "missing numbered menu"; exit 1; }
[[ "${menu_output}" == *"默认：3. workstation"* ]] || { echo "missing menu default"; exit 1; }
[[ "${menu_output}" == *"请选择安装目标 [3]:"* ]] || { echo "missing short prompt"; exit 1; }
[[ "${menu_output}" == *"请输入编号或可选名称"* ]] || { echo "missing invalid choice warning"; exit 1; }
[[ "${menu_output}" == *"choices=workstation,dev,proxy,base"* ]] || { echo "menu choices mismatch"; exit 1; }

echo "==> desktop package split"
desktop_package_output="$(
  bash -c '
    set -Eeuo pipefail
    SCRIPT_DIR="$PWD"
    source install_vars
    DRY_RUN=1
    source lib/common.sh
    source lib/packages.sh
    source modules/desktop/packages.sh
    GPU_TYPE=vmware
    HYPRLAND_CONFIG_MODE=hyprdots
    ENABLE_BLUETOOTH=1
    ENABLE_SDDM=1
    desktop_hyprdots_packages | grep -E "^(hyprland|bluez|sddm)$"
    effective_gpu_type
  '
)"
[[ "${desktop_package_output}" == *"hyprland"* ]] || { echo "missing hyprland package"; exit 1; }
[[ "${desktop_package_output}" == *"bluez"* ]] || { echo "missing bluetooth package"; exit 1; }
[[ "${desktop_package_output}" == *"sddm"* ]] || { echo "missing sddm package"; exit 1; }
[[ "${desktop_package_output}" == *"vmware"* ]] || { echo "missing gpu override"; exit 1; }

echo "==> desktop service split"
desktop_service_output="$(
  DRY_RUN=1 bash -c '
    set -Eeuo pipefail
    SCRIPT_DIR="$PWD"
    source install_vars
    DRY_RUN=1
    source lib/common.sh
    source lib/files.sh
    source lib/packages.sh
    source lib/systemd.sh
    source modules/desktop/packages.sh
    source modules/desktop/services.sh
    GPU_TYPE=vmware
    ENABLE_BLUETOOTH=1
    HYPRLAND_CONFIG_MODE=hyprdots
    enable_desktop_services
    enable_desktop_audio_services
  '
)"
[[ "${desktop_service_output}" == *"sudo systemctl enable --now NetworkManager.service"* ]] || { echo "missing NetworkManager enable"; exit 1; }
[[ "${desktop_service_output}" == *"sudo systemctl enable --now bluetooth.service"* ]] || { echo "missing bluetooth enable"; exit 1; }
[[ "${desktop_service_output}" == *"modprobe uinput"* ]] || { echo "missing vmware uinput"; exit 1; }
[[ "${desktop_service_output}" == *"sudo write /etc/modules-load.d/archdevkit-vmware.conf"* ]] || { echo "missing vmware module config"; exit 1; }
[[ "${desktop_service_output}" == *"systemctl --global enable pipewire.service"* ]] || { echo "missing pipewire global enable"; exit 1; }

echo "==> desktop input method split"
desktop_input_output="$(
  DRY_RUN=1 bash -c '
    set -Eeuo pipefail
    SCRIPT_DIR="$PWD"
    source install_vars
    DRY_RUN=1
    source lib/common.sh
    source lib/files.sh
    source lib/packages.sh
    source modules/desktop/input_method.sh
    ENABLE_FCITX5=1
    INPUT_METHOD_ENGINE=rime
    configure_fcitx5_env
    configure_fcitx5_rime_profile
  '
)"
[[ "${desktop_input_output}" == *"write ${HOME}/.config/environment.d/fcitx5.conf"* ]] || { echo "missing fcitx env write"; exit 1; }
[[ "${desktop_input_output}" == *"write ${HOME}/.config/fcitx5/profile"* ]] || { echo "missing rime profile write"; exit 1; }

echo "==> desktop vm split"
desktop_vm_output="$(
  DRY_RUN=1 bash -c '
    set -Eeuo pipefail
    SCRIPT_DIR="$PWD"
    source install_vars
    DRY_RUN=1
    source lib/common.sh
    source lib/packages.sh
    source modules/desktop/packages.sh
    source modules/desktop/vm.sh
    tmp_home="$(mktemp -d)"
    trap "rm -rf \"${tmp_home}\"" EXIT
    HOME="${tmp_home}"
    mkdir -p "${HOME}/.config/hypr"
    printf "monitor=,preferred,auto,1\n" > "${HOME}/.config/hypr/hyprland.conf"
    GPU_TYPE=vmware
    VMWARE_FORCE_SOFTWARE_RENDERER=1
    VM_HYPRLAND_DYNAMIC_RESIZE=1
    configure_hyprland_gpu_env
    configure_hyprland_virtualization_env
  '
)"
[[ "${desktop_vm_output}" == *"enable Hyprland software renderer env for vmware"* ]] || { echo "missing vm software renderer"; exit 1; }
[[ "${desktop_vm_output}" == *"keep VM Hyprland monitor dynamic"* ]] || { echo "missing vm monitor dry-run"; exit 1; }
[[ "${desktop_vm_output}" == *"enable VM guest agent autostart for vmware"* ]] || { echo "missing vm autostart dry-run"; exit 1; }

echo "==> desktop hyprdots split"
desktop_hyprdots_output="$(
  DRY_RUN=1 bash -c '
    set -Eeuo pipefail
    SCRIPT_DIR="$PWD"
    source install_vars
    DRY_RUN=1
    source lib/common.sh
    source lib/files.sh
    source modules/desktop/hyprdots.sh
    tmp_home="$(mktemp -d)"
    trap "rm -rf \"${tmp_home}\"" EXIT
    HOME="${tmp_home}"
    HYPRLAND_CONFIG_MODE=template
    generate_hyprland_config
    HYPRLAND_CONFIG_MODE=hyprdots
    HYPRDOTS_CONFIG_MODULES=(hypr waybar)
    install_hyprdots_config
  '
)"
[[ "${desktop_hyprdots_output}" == *"files/hyprland/hyprland.conf.tpl"* ]] || { echo "missing template render"; exit 1; }
[[ "${desktop_hyprdots_output}" == *"files/hyprdots/hypr"* ]] || { echo "missing hyprdots module copy"; exit 1; }
[[ "${desktop_hyprdots_output}" == *"render ArchDevKit overrides"* ]] || { echo "missing hyprdots overrides"; exit 1; }
[[ "${desktop_hyprdots_output}" == *"link "*"waybar/config -> config_new.jsonc"* ]] || { echo "missing waybar runtime links"; exit 1; }

echo "==> desktop helper split"
desktop_helper_output="$(
  DRY_RUN=1 bash -c '
    set -Eeuo pipefail
    SCRIPT_DIR="$PWD"
    source install_vars
    DRY_RUN=1
    source lib/common.sh
    source modules/desktop/packages.sh
    source modules/desktop/helpers.sh
    tmp_home="$(mktemp -d)"
    trap "rm -rf \"${tmp_home}\"" EXIT
    HOME="${tmp_home}"
    GPU_TYPE=vmware
    install_desktop_runtime_helpers
  '
)"
[[ "${desktop_helper_output}" == *"write "*"archdevkit-terminal"* ]] || { echo "missing terminal helper"; exit 1; }
[[ "${desktop_helper_output}" == *"write "*"neovide"* ]] || { echo "missing neovide helper"; exit 1; }
[[ "${desktop_helper_output}" == *"write "*"archdevkit-vmware-user"* ]] || { echo "missing vmware helper"; exit 1; }

echo "==> desktop verify split"
desktop_verify_output="$(
  DRY_RUN=1 bash -c '
    set -Eeuo pipefail
    SCRIPT_DIR="$PWD"
    source install_vars
    DRY_RUN=1
    source lib/common.sh
    source modules/desktop/verify.sh
    ENABLE_FCITX5=1
    BROWSER_APP=google-chrome-stable
    verify_hyprland
  '
)"
[[ "${desktop_verify_output}" == *"Hyprland --version"* ]] || { echo "missing Hyprland verify"; exit 1; }
[[ "${desktop_verify_output}" == *"google-chrome-stable --version"* ]] || { echo "missing browser verify"; exit 1; }
[[ "${desktop_verify_output}" == *"fcitx5 --version"* ]] || { echo "missing fcitx verify"; exit 1; }

echo "==> doctor json"
bash install.sh doctor --json | ruby -rjson -e '
  data = JSON.parse(STDIN.read)
  raise "schema mismatch" unless data.fetch("schemaVersion") == "1"
  raise "command mismatch" unless data.fetch("command") == "doctor"
  raise "missing checks" unless data.fetch("checks").is_a?(Array)
  names = data.fetch("checks").map { |c| c.fetch("name") }
  %w[pacman-lock github-raw aur display-manager].each do |name|
    raise "missing doctor check #{name}" unless names.include?(name)
  end
  raise "missing tool status check" unless names.include?("tool:tmux")
'

echo "==> recovery hints"
recovery_output="$(
  TARGET=workstation ARCHDEVKIT_LOG_FILE=/tmp/archdevkit-test.log bash -c '
    set -Eeuo pipefail
    source lib/module_registry.sh
    source lib/recovery.sh
    enable_install_recovery
    set_current_module runtime 3 10
    false
  ' 2>&1 || true
)"
[[ "${recovery_output}" == *"[安装中断]"* ]] || { echo "missing recovery title"; exit 1; }
[[ "${recovery_output}" == *"失败模块: runtime"* ]] || { echo "missing failed module"; exit 1; }
[[ "${recovery_output}" == *"bash install.sh install workstation --yes"* ]] || { echo "missing target retry"; exit 1; }
[[ "${recovery_output}" == *"bash install.sh install runtime --force --yes"* ]] || { echo "missing module retry"; exit 1; }
[[ "${recovery_output}" == *"bash install.sh reset-state runtime"* ]] || { echo "missing reset hint"; exit 1; }

echo "==> proxy module split"
proxy_split_output="$(
  DRY_RUN=1 bash -c '
    set -Eeuo pipefail
    SCRIPT_DIR="$PWD"
    source install_vars
    DRY_RUN=1
    source lib/common.sh
    source lib/files.sh
    source lib/packages.sh
    source lib/systemd.sh
    source modules/proxy.sh
    tmp_home="$(mktemp -d)"
    trap "rm -rf \"${tmp_home}\"" EXIT
    HOME="${tmp_home}"
    PROXY_CORE=mihomo
    ENABLE_METACUBEXD=1
    render_default_mihomo_config /etc/mihomo/config.yaml
    verify_proxy_env
    PROXY_CORE=sing-box
    configure_sing_box
  '
)"
[[ "${proxy_split_output}" == *"sudo render "*"files/mihomo/config.yaml.tpl -> /etc/mihomo/config.yaml"* ]] || { echo "missing mihomo render through split"; exit 1; }
[[ "${proxy_split_output}" == *"Mihomo 规则源：原始 URL"* ]] || { echo "missing mihomo verify through split"; exit 1; }
[[ "${proxy_split_output}" == *"render "*"files/sing-box/config.json.tpl"* ]] || { echo "missing sing-box render through split"; exit 1; }
[[ "${proxy_split_output}" == *"write "*"archdevkit-sing-box.service"* ]] || { echo "missing sing-box service through split"; exit 1; }

echo "==> mihomo yaml render"
tmp_mihomo="$(mktemp)"
sed \
  -e 's/__MIHOMO_MIXED_PORT__/7890/g' \
  -e 's/__MIHOMO_ALLOW_LAN__/false/g' \
  -e 's/__MIHOMO_BIND_ADDRESS__/0.0.0.0/g' \
  -e 's/__MIHOMO_CONTROLLER_HOST__/0.0.0.0/g' \
  -e 's/__MIHOMO_CONTROLLER_PORT__/9090/g' \
  -e 's#__MIHOMO_DNS_LISTEN__#0.0.0.0:1053#g' \
  -e 's/__MIHOMO_SECRET_YAML__/""/g' \
  -e 's#__METACUBEXD_EXTERNAL_UI_LINE__#external-ui: /var/lib/mihomo/ui#g' \
  files/mihomo/config.yaml.tpl > "${tmp_mihomo}"
ruby -ryaml -e '
  data = YAML.load_file(ARGV.fetch(0))
  raise "missing direct-nameserver" unless data.dig("dns", "direct-nameserver")
  raise "airport not direct" unless data.dig("proxy-providers", "airport", "proxy") == "DIRECT"
' "${tmp_mihomo}"
rm -f "${tmp_mihomo}"

echo "==> sing-box json render"
tmp_sing_box="$(mktemp)"
sed -e 's/__SING_BOX_MIXED_PORT__/7890/g' files/sing-box/config.json.tpl > "${tmp_sing_box}"
ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' "${tmp_sing_box}"
rm -f "${tmp_sing_box}"

echo "All checks passed."
