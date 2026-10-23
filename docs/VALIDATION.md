# 验证记录

## Android 真机验证

设备：2211133C；Android 17（API 37）；澎湃 OS4.0.0.12.XMCCNXM；内核 5.15.178-android13；SELinux Enforcing；KernelSU BusyBox 1.36.1.1 topjohnwu。

2026-10-22 验证了：

- 在设备自身的 BusyBox / ASH_STANDALONE 环境下保存 Telegram 视频路径。
- 接受带或不带末尾斜线的路径，以及含中文、空格的下载目录。
- 拒绝路径穿越、私有应用目录和递归映射。
- init 和 MediaProvider 挂载环境中的只读映射报告。
- 普通 ADB Shell 对公共映射目录的文件枚举，未读取视频内容。
- v0.1.3 的中文“执行”结果，不再输出 ENV/CFG/S 内部协议。
- 覆盖更新时保留用户配置。

尚未验证：MX 应用进程的实际播放与拖动进度条、正常模块安装后的完整重启恢复，以及其他设备和系统版本。

## 已修复的设备兼容问题

### v0.1.1

设备 BusyBox 不支持 `flock -w`。改为 `flock -n` 配合最多 10 秒的有限重试；命令错误与真正的锁占用分开处理。

### v0.1.2

在设备 BusyBox 上，合法路径单独校验通过，但在配置读取循环中将校验函数重定向至 `/dev/null` 时返回错误。改为捕获规范化路径后，设备回归用例通过。这是实测执行行为，不代表已确定 BusyBox 内部实现的原因。

### v0.1.3

执行按钮输出中文状态，优先显示错误而不是其他挂载环境中的成功结果，并正确反映暂停状态。

## 自动化验证

- Python 驱动的 Shell 用例覆盖路径校验、配置编码、只读挂载生命周期、占用处理、锁兼容和中文结果。Windows 本地挂载系统调用使用模拟实现。
- 7 项 Node 模型测试覆盖配置往返、特殊字符、路径限制、重复条目与状态。
- Playwright 使用模拟 KernelSU 桥接，验证真实 WebUI 的选择目录、保存、编辑、启停、诊断、错误提示、文本注入处理与移动布局。
- 界面检查宽度包括 320、390、430 像素。
- 打包检查 ZIP CRC、必需文件、重复条目、LF 换行及 Unix 执行权限。
- `tests/linux-mount.sh` 用于真实 Linux 挂载测试，需隔离的 mount namespace；结果以 GitHub Actions 对应提交的运行记录为准。

GitHub Actions 的结果不等于 Android 真机验证。新增设备验证请使用 [DEVICE_TEST.md](DEVICE_TEST.md) 记录。
