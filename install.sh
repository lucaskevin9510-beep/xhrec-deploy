#!/usr/bin/env bash
# XhRec 交互式部署器（Debian / Ubuntu）
# 仅用于录制你拥有保存权限的公开直播。
set -Eeuo pipefail

VERSION="v1.2.0"
PORT="8090"
QUALITY="highest"
LIMIT=""
INSTALL_ROOT=""
SERVICE_NAME="xhrec"
APP_USER="xhrec"
DRY_RUN=0
ASSUME_YES=0
INTERACTIVE=1
ROOMS=()

ORIGINAL_ARGC=$#

log()  { printf '\n\033[1;36m[XhRec]\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m[提醒]\033[0m %s\n' "$*" >&2; }
fail() { printf '\n\033[1;31m[错误]\033[0m %s\n' "$*" >&2; exit 1; }
run() {
    if (( DRY_RUN )); then
        printf '[模拟执行]'; printf ' %q' "$@"; printf '\n'
    else
        "$@"
    fi
}

usage() {
    cat <<'EOF'
XhRec 交互式部署器

直接运行（推荐，新手模式）：
  sudo bash xhrec-install.sh

参数模式（适合批量部署）：
  sudo bash xhrec-install.sh \
    --room https://stripchat.com/主播名 \
    --install-root /mnt/录制盘/xhrec \
    --quality 1080p \
    --port 8090 \
    --yes

选项：
  --room NAME|URL      主播名或房间地址；可重复填写以监控多个主播
  --install-root DIR   安装根目录；程序、配置、录制和日志都放在这里
  --quality VALUE      240p、480p、720p、720p60、1080p、1080p60、highest
  --port PORT          XhRec 控制台端口，默认 8090
  --limit SECONDS      每段录制时长；留空表示不限制（正式监控推荐留空）
  --version VERSION    XhRec 版本，默认 v1.2.0
  --service-name NAME  systemd 服务名，默认 xhrec
  --yes                非交互确认
  --dry-run            只显示计划，不安装
  --help               显示帮助
EOF
}

need_arg() { [[ $# -ge 2 ]] || fail "$1 缺少参数"; }

normalize_room() {
    local value="$1"
    value="${value#https://stripchat.com/}"
    value="${value%%/*}"
    value="${value%%\?*}"
    [[ "$value" =~ ^[A-Za-z0-9_.-]+$ ]] || fail "主播名格式错误：$1"
    printf 'https://stripchat.com/%s' "$value"
}

# XhRec v1.2.0 某些构建会把 highest 错误地按数字解析；兼容为 1080p。
normalize_quality() {
    [[ "$1" == "highest" ]] && printf '1080p' || printf '%s' "$1"
}

while (($#)); do
    case "$1" in
        --room) need_arg "$@"; ROOMS+=("$(normalize_room "$2")"); shift 2 ;;
        --install-root) need_arg "$@"; INSTALL_ROOT="$2"; shift 2 ;;
        --quality) need_arg "$@"; QUALITY="$2"; shift 2 ;;
        --port) need_arg "$@"; PORT="$2"; shift 2 ;;
        --limit) need_arg "$@"; LIMIT="$2"; shift 2 ;;
        --version) need_arg "$@"; VERSION="$2"; shift 2 ;;
        --service-name) need_arg "$@"; SERVICE_NAME="$2"; shift 2 ;;
        --yes|-y) ASSUME_YES=1; INTERACTIVE=0; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) fail "未知参数：$1" ;;
    esac
done

# 只要带了参数，就采用非交互参数模式；完全不带参数才进入向导。
if (( ORIGINAL_ARGC > 0 )); then
    INTERACTIVE=0
fi

[[ $EUID -eq 0 ]] || fail "请使用 root 或 sudo 运行。"
command -v apt-get >/dev/null 2>&1 || fail "目前只支持使用 apt 的 Debian/Ubuntu。"

show_disks() {
    log "当前磁盘与挂载点"
    if command -v lsblk >/dev/null 2>&1; then
        lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,FSAVAIL -e 7 || true
    fi
    printf '\n'
    df -hT -x tmpfs -x devtmpfs 2>/dev/null || true
}

ask_text() {
    local prompt="$1" default="$2" value=""
    read -r -p "$prompt [$default]: " value </dev/tty
    printf '%s' "${value:-$default}"
}

ask_quality() {
    local choice=""
    cat >/dev/tty <<'EOF'
请选择录制画质：
  1) highest  自动选择最高画质（推荐）
  2) 1080p
  3) 1080p60
  4) 720p
  5) 720p60
  6) 480p
  7) 240p
EOF
    read -r -p '请输入序号 [1]: ' choice </dev/tty
    case "${choice:-1}" in
        1) printf highest ;; 2) printf 1080p ;; 3) printf 1080p60 ;;
        4) printf 720p ;; 5) printf 720p60 ;; 6) printf 480p ;; 7) printf 240p ;;
        *) fail "无效画质序号：$choice" ;;
    esac
}

if (( INTERACTIVE )); then
    [[ -r /dev/tty && -t 1 ]] || fail "交互模式需要终端；非交互环境请提供 --room、--install-root、--quality 和 --port。"
    show_disks
    INSTALL_ROOT="$(ask_text '请输入安装根目录（建议选空间充足的已挂载磁盘）' '/opt/xhrec')"
    PORT="$(ask_text '请输入控制台端口' '8090')"
    QUALITY="$(ask_quality)"

    room="$(ask_text '请输入主播名' '主播名')"
    room="$(normalize_room "$room")"
    ROOMS+=("$room")
    while true; do
        read -r -p '还要添加其他主播吗？[y/N]: ' answer </dev/tty
        [[ "$answer" =~ ^[Yy]$ ]] || break
        read -r -p '请输入另一个主播名: ' room </dev/tty
        ROOMS+=("$(normalize_room "$room")")
    done

    read -r -p '是否设置每段录制时长（秒）？正式长期监控建议直接回车: ' LIMIT </dev/tty
fi

QUALITY="$(normalize_quality "$QUALITY")"

[[ -n "$INSTALL_ROOT" ]] || fail "必须选择 --install-root。"
INSTALL_ROOT="$(realpath -m -- "$INSTALL_ROOT")"
[[ "$INSTALL_ROOT" == /* ]] || fail "安装目录必须是绝对路径。"
[[ "$INSTALL_ROOT" != "/" ]] || fail "不能把系统根目录作为安装目录。"
[[ "$INSTALL_ROOT" != *$'\n'* ]] || fail "安装路径不能包含换行。"
[[ "$SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]] || fail "服务名包含不支持的字符。"
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "版本号应类似 v1.2.0。"
[[ "$QUALITY" =~ ^(240p|480p|720p|720p60|1080p|1080p60|highest)$ ]] || fail "不支持的画质：$QUALITY。"
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1024 && PORT <= 65535 )) || fail "端口必须是 1024–65535。"
if [[ -n "$LIMIT" ]]; then
    [[ "$LIMIT" =~ ^[0-9]+$ ]] && (( LIMIT > 0 )) || fail "录制时长必须是正整数秒数。"
fi
((${#ROOMS[@]} > 0)) || fail "至少需要一个 --room。"
for room in "${ROOMS[@]}"; do
    [[ "$room" =~ ^https://stripchat\.com/[A-Za-z0-9_.-]+$ ]] || fail "房间地址格式错误：$room"
done

APP_DIR="$INSTALL_ROOT/app"
CONFIG_DIR="$INSTALL_ROOT/config"
DATA_DIR="$INSTALL_ROOT/data"
OUT_DIR="$INSTALL_ROOT/recordings"
TMP_DIR="$INSTALL_ROOT/tmp"
LOG_DIR="$INSTALL_ROOT/logs"
JAR_PATH="$APP_DIR/XhRec-all.jar"
LIST_FILE="$CONFIG_DIR/list.conf"
POST_CONFIG="$CONFIG_DIR/postprocessor.json"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
JAR_URL="https://github.com/RikaCelery/XhRec/releases/download/${VERSION}/XhRec-all.jar"

# 找到承载安装目录的现有父路径，用它核对磁盘空间。
probe="$INSTALL_ROOT"
while [[ ! -e "$probe" && "$probe" != "/" ]]; do probe="$(dirname "$probe")"; done
AVAIL_KB="$(df -Pk "$probe" | awk 'NR==2 {print $4}')"
(( AVAIL_KB >= 1048576 )) || fail "目标磁盘可用空间不足 1 GiB。"
MOUNT_INFO="$(df -hT "$probe" | awk 'NR==2 {print $1" | "$2" | 可用 "$5" | 挂载 "$7}')"

if ss -lntH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$PORT$"; then
    fail "端口 $PORT 已被占用，请选择其他端口。"
fi

log "安装计划"
printf '  目标磁盘：%s\n' "$MOUNT_INFO"
printf '  安装根目录：%s\n' "$INSTALL_ROOT"
printf '  录制目录：%s\n' "$OUT_DIR"
printf '  临时目录：%s\n' "$TMP_DIR"
printf '  日志目录：%s\n' "$LOG_DIR"
printf '  控制台端口：%s\n' "$PORT"
printf '  录制画质：%s\n' "$QUALITY"
printf '  每段时长：%s\n' "${LIMIT:-不限制，由上下播控制}"
printf '  房间数量：%s\n' "${#ROOMS[@]}"
printf '  开机启动：是\n'
printf '  异常重启：是，15 秒后重启\n'
printf '  自动付费：否\n'
printf '  Cookie：不配置\n'

if (( ! ASSUME_YES && ! DRY_RUN )); then
    read -r -p '确认按以上设置安装吗？[y/N]: ' answer </dev/tty
    [[ "$answer" =~ ^[Yy]$ ]] || fail "已取消安装。"
fi

export DEBIAN_FRONTEND=noninteractive
run apt-get update
run apt-get install -y openjdk-21-jre-headless ffmpeg curl ca-certificates

if ! id -u "$APP_USER" >/dev/null 2>&1; then
    run useradd --system --home-dir "$DATA_DIR" --no-create-home --shell /usr/sbin/nologin "$APP_USER"
fi

run install -d -o root -g "$APP_USER" -m 0750 "$INSTALL_ROOT" "$APP_DIR" "$CONFIG_DIR"
run install -d -o "$APP_USER" -g "$APP_USER" -m 0750 "$DATA_DIR" "$OUT_DIR" "$TMP_DIR" "$LOG_DIR"

if (( DRY_RUN )); then
    log "将从以下地址下载：$JAR_URL"
else
    tmp_jar="$(mktemp)"
    trap 'rm -f "$tmp_jar"' EXIT
    curl --fail --location --retry 3 --proto '=https' --tlsv1.2 -o "$tmp_jar" "$JAR_URL"
    [[ "$(stat -c %s "$tmp_jar")" -gt 1048576 ]] || fail "下载的 JAR 文件异常小。"
    [[ "$(od -An -tx1 -N2 "$tmp_jar" | tr -d ' \n')" == "504b" ]] || fail "下载内容不是有效 JAR/ZIP 文件。"
    install -o root -g "$APP_USER" -m 0750 "$tmp_jar" "$JAR_PATH"
    sha256sum "$JAR_PATH" > "$APP_DIR/XhRec-all.jar.sha256"
    rm -f "$tmp_jar"
    trap - EXIT
fi

if (( DRY_RUN )); then
    for room in "${ROOMS[@]}"; do
        printf '[模拟配置] %s q:%s%s\n' "$room" "$QUALITY" "${LIMIT:+ limit:$LIMIT}"
    done
else
    : > "$LIST_FILE"
    for room in "${ROOMS[@]}"; do
        line="$room q:$QUALITY"
        [[ -n "$LIMIT" ]] && line+=" limit:$LIMIT"
        printf '%s\n' "$line" >> "$LIST_FILE"
    done
    chown root:"$APP_USER" "$LIST_FILE"
    chmod 0640 "$LIST_FILE"
    cat > "$POST_CONFIG" <<EOF
{
  "default": [
    {
      "type": "fix_stamp",
      "output": "$OUT_DIR"
    }
  ]
}
EOF
    chown root:"$APP_USER" "$POST_CONFIG"
    chmod 0640 "$POST_CONFIG"
fi

if (( DRY_RUN )); then
    log "将生成 systemd 服务：$SERVICE_FILE"
else
    if systemctl is-active --quiet "$SERVICE_NAME.service" 2>/dev/null; then
        systemctl stop "$SERVICE_NAME.service"
    fi
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=XhRec 自动直播录制
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$DATA_DIR
ExecStart=/usr/bin/java -jar $JAR_PATH -f $LIST_FILE -post $POST_CONFIG -o $OUT_DIR -t $TMP_DIR -p $PORT
Restart=always
RestartSec=15
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=false
ReadWritePaths=$INSTALL_ROOT
UMask=0027
StandardOutput=append:$LOG_DIR/service.log
StandardError=append:$LOG_DIR/service.log

[Install]
WantedBy=multi-user.target
EOF
    chmod 0644 "$SERVICE_FILE"
    systemctl daemon-reload
    systemctl enable --now "$SERVICE_NAME.service"
    sleep 3
    systemctl is-active --quiet "$SERVICE_NAME.service" || {
        systemctl status "$SERVICE_NAME.service" --no-pager || true
        fail "服务未能正常启动，请查看上方日志。"
    }
fi

log "部署完成"
printf '  服务：%s.service\n' "$SERVICE_NAME"
printf '  成品：%s\n' "$OUT_DIR"
printf '  配置：%s\n' "$LIST_FILE"
printf '  日志：%s/service.log\n' "$LOG_DIR"
printf '\n常用命令：\n'
printf '  systemctl status %s --no-pager\n' "$SERVICE_NAME"
printf '  journalctl -u %s -f\n' "$SERVICE_NAME"
printf '  ls -lh %q\n' "$OUT_DIR"
printf '  systemctl restart %s\n' "$SERVICE_NAME"
printf '  systemctl stop %s\n' "$SERVICE_NAME"

warn "XhRec 当前版本的控制台可能监听所有网卡。脚本不会自动修改防火墙；不要在云防火墙中向公网开放 $PORT。"
printf '推荐通过 SSH 隧道访问控制台：\n'
printf '  ssh -N -L %s:127.0.0.1:%s root@服务器地址\n' "$PORT" "$PORT"
printf '然后打开：https://127.0.0.1:%s\n' "$PORT"
