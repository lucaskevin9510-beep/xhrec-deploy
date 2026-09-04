#!/usr/bin/env bash
# XhRec Telegram 通知器：读取事件 JSONL，所有通知都带主播名。
set -Eeuo pipefail

CONFIG="${XHREC_NOTIFY_CONFIG:-/etc/xhrec/telegram.env}"
EVENTS="${XHREC_EVENTS_FILE:-/var/lib/xhrec/events/events.jsonl}"
STATE="${XHREC_NOTIFY_STATE:-/var/lib/xhrec/events/notify.state}"

[[ -r "$CONFIG" ]] || { printf '找不到 Telegram 配置：%s\n' "$CONFIG" >&2; exit 1; }
# shellcheck disable=SC1090
. "$CONFIG"
: "${TELEGRAM_BOT_TOKEN:?缺少 TELEGRAM_BOT_TOKEN}"
: "${TELEGRAM_CHAT_ID:?缺少 TELEGRAM_CHAT_ID}"
mkdir -p "$(dirname "$STATE")"
touch "$STATE"

send() {
  local text="$1"
  curl --fail --silent --show-error --retry 3 \
    -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${text}" >/dev/null
}

format_event() {
  python3 - "$1" <<'PY'
import json, sys
x=json.loads(sys.argv[1])
name=x.get('主播名') or x.get('room_name') or x.get('room') or '未知主播'
event=x.get('event','')
when=x.get('time','')
file=x.get('file','')
size=x.get('size','')
duration=x.get('duration','')
messages={
 'online': f'🟢 主播上线\n\n主播：{name}\n状态：已开始录制\n时间：{when}',
 'interrupted': f'🟠 直播流暂时中断\n\n主播：{name}\n状态：正在自动重连\n说明：暂不判断为下播\n时间：{when}',
 'unavailable': f'🟡 当前无法获取视频流\n\n主播：{name}\n可能原因：私秀、票房直播、授权失效或平台限制\n处理：保留监控，等待恢复\n时间：{when}',
 'recovered': f'🔵 直播流已恢复\n\n主播：{name}\n状态：已继续录制\n时间：{when}',
 'offline': f'⚫ 主播已下播\n\n主播：{name}\n状态：录制结束\n时间：{when}',
 'exported': f'✅ 视频已导出\n\n主播：{name}\n时长：{duration or "未知"}\n大小：{size or "未知"}\n文件：{file or "未知"}',
}
print(messages.get(event, f'ℹ️ 录制状态更新\n\n主播：{name}\n事件：{event}\n时间：{when}'))
PY
}

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  id="$(printf '%s' "$line" | sha256sum | cut -d' ' -f1)"
  grep -qxF "$id" "$STATE" && continue
  msg="$(format_event "$line")"
  send "$msg"
  printf '%s\n' "$id" >> "$STATE"
done < <(tail -n 0 -F "$EVENTS")
