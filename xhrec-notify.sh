#!/usr/bin/env bash
# XhRec Telegram 通知服务：只处理启动后的新增日志和新导出文件。
set -Eeuo pipefail

CONFIG="${XHREC_NOTIFY_CONFIG:?缺少 XHREC_NOTIFY_CONFIG}"
ROOM_LOG="${XHREC_ROOM_LOG:?缺少 XHREC_ROOM_LOG}"
OUTPUT_DIR="${XHREC_OUTPUT_DIR:?缺少 XHREC_OUTPUT_DIR}"
ROOM_LIST="${XHREC_ROOM_LIST:?缺少 XHREC_ROOM_LIST}"
STATE_DIR="${XHREC_NOTIFY_STATE_DIR:?缺少 XHREC_NOTIFY_STATE_DIR}"
INTERVAL="${XHREC_NOTIFY_INTERVAL:-15}"
TELEGRAM_API_BASE="${TELEGRAM_API_BASE:-https://api.telegram.org}"
mkdir -p "$STATE_DIR"
# shellcheck disable=SC1090
. "$CONFIG"
: "${TELEGRAM_BOT_TOKEN:?缺少 TELEGRAM_BOT_TOKEN}"
: "${TELEGRAM_CHAT_ID:?缺少 TELEGRAM_CHAT_ID}"

log_cursor="$STATE_DIR/log.cursor"
file_state="$STATE_DIR/files.sent"

send() {
  local text="$1"
  curl --fail --silent --show-error --retry 3 \
    -X POST "${TELEGRAM_API_BASE}/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${text}" >/dev/null
}

# 首次启动建立日志和文件基线，避免把历史录制重复通知。
if [[ ! -e "$log_cursor" ]]; then
  if [[ -f "$ROOM_LOG" ]]; then
    wc -c < "$ROOM_LOG" > "$log_cursor"
  else
    printf '0\n' > "$log_cursor"
  fi
fi
if [[ ! -e "$file_state" ]]; then
  find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.fixed.mp4' -printf '%p\n' 2>/dev/null | sort > "$file_state" || :
fi

while true; do
  if [[ -f "$ROOM_LOG" ]]; then
    old="$(cat "$log_cursor" 2>/dev/null || printf '0')"
    size="$(wc -c < "$ROOM_LOG")"
    if [[ "$size" =~ ^[0-9]+$ && "$old" =~ ^[0-9]+$ && "$size" -lt "$old" ]]; then old=0; fi
    if (( size > old )); then
      while IFS= read -r line; do
        if [[ "$line" =~ start[[:space:]]recording[[:space:]]([^\(]+)\( ]]; then
          name="${BASH_REMATCH[1]}"
          send "🟢 主播上线\n\n主播：$name\n状态：已开始录制\n时间：$(date '+%Y-%m-%d %H:%M:%S')"
        elif [[ "$line" =~ session[[:space:]]start[[:space:]]failed ]]; then
          names="$(awk 'NF && $1 !~ /^[#;]/ {u=$1; sub(/^.*\//,"",u); print u}' "$ROOM_LIST" 2>/dev/null | paste -sd '、' -)"
          send "🟡 当前无法获取视频流\n\n主播：${names:-监控列表中的主播}\n说明：可能是私秀、票房、授权失效、网络故障或平台限制\n处理：继续重试\n时间：$(date '+%Y-%m-%d %H:%M:%S')"
        elif [[ "$line" =~ stop[[:space:]]recording[[:space:]]([^\(]+)\( ]]; then
          name="${BASH_REMATCH[1]}"
          send "⚫ 录制会话结束\n\n主播：$name\n说明：可能是下播、达到时长限制或手动停止\n时间：$(date '+%Y-%m-%d %H:%M:%S')"
        fi
      done < <(tail -c +$((old + 1)) "$ROOM_LOG")
      printf '%s\n' "$size" > "$log_cursor"
    fi
  fi

  if [[ -d "$OUTPUT_DIR" ]]; then
    find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.fixed.mp4' -printf '%p\n' 2>/dev/null | sort | while IFS= read -r file; do
      grep -Fqx "$file" "$file_state" 2>/dev/null && continue
      name="$(basename "$file")"
      name="$(printf '%s' "$name" | sed -E 's/-[0-9]{4}_[0-9]{2}_[0-9]{2}-.*$//')"
      size="$(stat -c '%s' "$file" 2>/dev/null || printf '0')"
      human="$(numfmt --to=iec --suffix=B "$size" 2>/dev/null || printf '%s bytes' "$size")"
      send "✅ 视频已导出\n\n主播：${name:-未知}\n文件：$(basename "$file")\n大小：$human\n时间：$(date '+%Y-%m-%d %H:%M:%S')"
      printf '%s\n' "$file" >> "$file_state"
    done
  fi
  sleep "$INTERVAL"
done
