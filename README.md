# XhRec 自动录制部署工具

用于在 Debian/Ubuntu 服务器部署 XhRec 直播监控与录制服务。

> 仅用于录制你有权保存的公开直播。请遵守平台规则与当地法律；本项目不绕过 DRM、验证码、付费墙或访问控制，也不会启用自动付费。

## 当前文件

- `install.sh`：交互式一键安装器，也支持命令行参数。
- `xhrec-recorder.sh`：systemd 服务控制、状态、磁盘和文件健康检查。
- `xhrec-notify.sh`：Telegram 通知组件；通知模板强制带主播名，并区分上线、断流、恢复、不可访问、下播、导出。

## 安装

```bash
sudo bash install.sh
```

向导会询问：

- 选择安装或卸载；
- 安装根目录（可选已挂载磁盘，例如 `/mnt/storage/xhrec`）；
- 控制台端口；
- 画质；
- 一个或多个 Stripchat 房间；
- 是否配置 Cookie（隐藏输入，并保存为权限为 600 的 `data/users.txt`）；
- 是否设置测试分段时长。

正式长期监控时，测试时长留空。安装后由 systemd 保证 SSH 断开、服务器重启或 XhRec 异常退出后继续运行。

安装确认提示为 `[Y/n]`，直接回车即确认。

卸载：

```bash
sudo bash install.sh --uninstall --install-root /var/lib/xhrec
```

卸载会停止并删除对应的 systemd 服务、XhRec 程序、配置、日志、临时文件和录制目录。请确认录制目录中没有需要保留的视频。

也可以非交互部署：

```bash
sudo bash install.sh \
  --room https://stripchat.com/主播名 \
  --install-root /mnt/storage/xhrec \
  --quality 1080p \
  --port 18190 \
  --yes
```

模拟检查：

```bash
bash install.sh \
  --room https://stripchat.com/主播名 \
  --install-root /mnt/storage/xhrec \
  --quality 480p \
  --limit 60 \
  --port 18190 \
  --dry-run
```

## 安装后

```bash
systemctl status xhrec --no-pager
journalctl -u xhrec -f
ls -lh /mnt/storage/xhrec/recordings/
```

常用命令：

```bash
bash xhrec-recorder.sh status   # 查看录制服务状态
bash xhrec-recorder.sh logs     # 查看实时日志
bash xhrec-recorder.sh files    # 查看导出文件
bash xhrec-recorder.sh health   # 检查磁盘、服务和近期文件
```

控制台建议通过 SSH 隧道访问，不要把端口直接暴露公网：

```bash
ssh -N -L 18190:127.0.0.1:18190 root@服务器地址
```

然后访问 `https://127.0.0.1:18190`。

## Telegram 通知设计

通知组件的目标状态是：

- 🟢 主播上线并开始录制；
- 🟠 直播流暂时中断，正在重连；
- 🟡 房间可能在线但当前不可访问（私秀、票房、授权失效或平台限制）；
- 🔵 直播流恢复；
- ⚫ 确认主播下播；
- ✅ 视频完成导出。

每条消息都包含主播名。短暂断流不会直接通知“下播”。

Telegram Token 与 Chat ID 只能保存在服务器本地受限配置中，不能提交到仓库。`config.example.env` 只提供变量名模板。

XhRec 面板的 API Token 默认保持为空，便于通过本机或 SSH 隧道管理添加主播、停止录制和修改设置；不要把面板端口直接暴露到公网。浏览器面板语言由 XhRec 前端的浏览器语言/localStorage 决定，当前安装器不伪造语言设置。

## 重要限制

XhRec 的房间状态、媒体流状态和实际付费/私秀原因并不总能一一对应。因此通知器不能保证识别出具体原因，只能报告“当前不可访问”，并保留监控与重连。只有房间状态明确离线或经过可靠的连续离线判定，才应通知确认下播。

## 目录约定

安装器选择的根目录下：

```text
app/          XhRec JAR
config/       list.conf 与本地配置
data/         运行数据
recordings/   导出的 MP4
tmp/          临时片段
logs/         服务日志
```

## 安全说明

- 默认创建非登录系统用户 `xhrec` 运行录制；
- 不自动保存 Cookie；
- 不启用 `autopay`；
- 不提交真实 Token、Cookie、临时授权参数或录制文件；
- 安装前请先执行 `--dry-run` 查看路径、端口与配置。
