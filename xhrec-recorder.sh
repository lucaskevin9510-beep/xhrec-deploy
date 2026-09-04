#!/usr/bin/env bash
# XhRec 服务控制与健康检查
set -Eeuo pipefail

SERVICE_NAME="${XHREC_SERVICE_NAME:-xhrec}"
INSTALL_ROOT="${XHREC_INSTALL_ROOT:-/opt/xhrec}"
OUT_DIR="${XHREC_OUT_DIR:-$INSTALL_ROOT/recordings}"

usage() {
  cat <<'EOF'
用法：xhrec-recorder.sh {start|stop|restart|status|logs|files|health}
环境变量：XHREC_SERVICE_NAME、XHREC_INSTALL_ROOT、XHREC_OUT_DIR
EOF
}

case "${1:-}" in
  start)   exec systemctl start "$SERVICE_NAME" ;;
  stop)    exec systemctl stop "$SERVICE_NAME" ;;
  restart) exec systemctl restart "$SERVICE_NAME" ;;
  status)  systemctl status "$SERVICE_NAME" --no-pager; systemctl is-active --quiet "$SERVICE_NAME" ;;
  logs)    exec journalctl -u "$SERVICE_NAME" -f -n 100 ;;
  files)   exec find "$OUT_DIR" -maxdepth 1 -type f -printf '%TY-%Tm-%Td %TH:%TM %s %p\n' | sort ;;
  health)
    [[ -d "$OUT_DIR" ]] || { printf '录制目录不存在：%s\n' "$OUT_DIR" >&2; exit 1; }
    printf 'service=%s\n' "$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || true)"
    printf 'disk=\n'; df -hT "$OUT_DIR"
    printf 'recent_files=\n'; find "$OUT_DIR" -maxdepth 1 -type f -mmin -180 -printf '%TY-%Tm-%Td %TH:%TM %s %p\n' | sort || true
    ;;
  *) usage; exit 2 ;;
esac
