#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
bash -n install.sh xhrec-notify.sh xhrec-recorder.sh
grep -q 'chmod 0660 "\$LIST_FILE"' install.sh
grep -q -- '-u \$USERS_FILE' install.sh
grep -q -- '-post \$POST_CONFIG' install.sh
grep -q 'NOTIFY_SERVICE_FILE' install.sh
grep -q 'Environment=XHREC_ROOM_LIST=\$LIST_FILE' install.sh
grep -q -- '--uninstall' install.sh
# Verify the notifier can parse a new event without sending to Telegram.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/out" "$tmp/state"
printf 'TELEGRAM_BOT_TOKEN=dummy\nTELEGRAM_CHAT_ID=123\n' > "$tmp/tg.env"
printf 'https://stripchat.com/nide_xiaogou q:480p\n' > "$tmp/list.conf"
printf '2026-09-05 INFO start recording nide_xiaogou(123)\n' > "$tmp/log"
# The notifier is long-running; stop after its baseline iteration.
timeout 2s env XHREC_NOTIFY_CONFIG="$tmp/tg.env" XHREC_ROOM_LOG="$tmp/log" XHREC_OUTPUT_DIR="$tmp/out" XHREC_ROOM_LIST="$tmp/list.conf" XHREC_NOTIFY_STATE_DIR="$tmp/state" XHREC_NOTIFY_INTERVAL=1 TELEGRAM_API_BASE=http://127.0.0.1:1 bash ./xhrec-notify.sh >/dev/null 2>&1 || true
[[ -f "$tmp/state/log.cursor" ]]
