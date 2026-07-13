#!/usr/bin/env bash
set -euo pipefail

# Arch presets are dependency-only modules. The Go planner expands their
# dependencies into normal OS Init modules before this acknowledgement runs.

case "${1:-}" in
  arch-dev)
    echo "=== Arch 开发环境组合已完成 ==="
    ;;
  arch-workstation)
    echo "=== Arch 完整工作站组合已完成 ==="
    ;;
  *)
    echo "未知 Arch 组合预设：${1:-}" >&2
    exit 2
    ;;
esac
