#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
bash -n install.sh xhrec-recorder.sh xhrec-notify.sh
grep -q "主播：" xhrec-notify.sh
grep -q "ProtectSystem=strict" install.sh
grep -q "ReadWritePaths=\$INSTALL_ROOT" install.sh
grep -q "recordings" install.sh
grep -q -- "-post \$POST_CONFIG" install.sh
grep -q '"type": "fix_stamp"' install.sh
