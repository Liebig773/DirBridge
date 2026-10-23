# DirBridge · 下载目录映射

**作者：liebig · KernelSU 模块 · MIT 开源**

把 Telegram、迅雷等应用的下载目录映射到本地播放器能浏览的公共入口。同一份视频，多个入口；不复制文件、不额外占用一份视频的空间。

[下载安装包](https://github.com/Liebig773/DirBridge/releases/latest) · [更新记录](CHANGELOG.md) · [反馈问题](https://github.com/Liebig773/DirBridge/issues)

## 功能

- **多个下载目录**：添加、编辑、启用、停用或移除最多 64 个映射。
- **不复制文件**：使用只读 bind mount，视频仍保存在原应用目录。
- **中文管理界面**：通过 KernelSU WebUI 选择目录，支持中文和空格。
- **开机自动应用**：重启并解锁后重新建立已保存且启用的映射；暂停或停用的映射不会自动开启。
- **后台定期检查**：每 60 秒检查目录和挂载状态，处理延迟创建目录及媒体服务重启。
- **中文执行结果**：KernelSU 的“执行”按钮会重新应用映射，显示每个目录的状态和播放器入口。
- **配置保留**：覆盖更新保留已有映射配置。
- **纯本地运行**：模块无网络请求，不需要 Zygisk、LSPosed 或 metamodule，不修改 SELinux 策略。

## 使用条件

- 已获得 Root，并安装 **KernelSU / KernelSU Next**。
- 管理器提供标准 KernelSU BusyBox 和 WebUI 接口。
- 安装器最低要求 **Android 10（API 29）**。
- 当前只支持**主用户的内部共享存储**，不支持副用户、工作资料和外置 SD 卡。

这不是普通 APK。无 Root 的普通应用不能通用地读取其他应用受保护的 `Android/data`，也不能建立本模块使用的目录挂载。

## 下载与安装

到 [Releases](https://github.com/Liebig773/DirBridge/releases/latest) 下载：

| 文件 | 用途 |
| --- | --- |
| `DirBridge-v0.1.3.zip` | KernelSU 模块安装包，保持 ZIP 格式安装 |
| `DirBridge-v0.1.3-source.zip` | 完整项目源码，供查看、修改和构建 |
| `SHA256SUMS.txt` | 安装包及源码包的 SHA-256 校验值 |

1. 打开 KernelSU → **模块 → 安装模块**，选择安装包 ZIP。
2. 安装完成后重启手机并解锁。
3. 从模块卡片打开 **WebUI / 打开**，进入 DirBridge 管理页面。

更新时直接覆盖安装新 ZIP，再重启即可，无需先卸载。GitHub 自动生成的 `Source code (zip)` 也是源码，不能作为模块直接安装。

## 添加下载目录

1. 点击 **添加目录**，填写播放器里显示的文件夹名称，例如“电报视频”。
2. 点击 **选择目录**，进入应用包名 → `files` → 实际下载文件夹。
3. 点击 **保存并应用**。需要添加其他软件时，重复以上步骤。

例如：

```text
源目录：
/storage/emulated/0/Android/data/org.telegram.messenger/files/Telegram/Telegram Video

播放器入口：
/storage/emulated/0/Movies/DirBridge/电报视频
```

路径以手机上的实际目录为准。同一应用可添加多组目录，例如 Telegram Video 和 Telegram Documents。

## 在播放器中查看

1. **打开 MX Player 或其他本地播放器，通常就可以直接找到映射目录中的视频。**如果找不到，再按下面的步骤添加路径。
2. 确认播放器已获得视频或所有文件访问权限，然后刷新或重新扫描视频列表。
3. 在播放器的文件夹或扫描目录设置中添加：

   ```text
   /storage/emulated/0/Movies/DirBridge
   ```

   MX Player 可在“设置 → 列表 → 文件夹”中添加；不同版本的菜单名称可能不同。
4. 仍看不到时，检查隐藏文件和 `.nomedia` 排除设置，再打开映射目录查看。

“已挂载”表示系统已建立只读入口。播放器仍需要相应的访问权限和扫描设置。

## 按钮说明

| 按钮 | 功能 |
| --- | --- |
| 添加目录 | 新建下载目录映射 |
| 重新应用 / KernelSU 的执行按钮 | 立即处理已保存的映射，不复制视频，不重启手机 |
| 刷新状态 | 重新读取当前状态 |
| 暂停全部 / 恢复全部 | 暂停或恢复所有启用的映射，暂停状态在重启后保留 |
| 停用 / 启用 | 控制单个映射 |
| 移除映射 | 移除配置并尝试解除挂载，不删除源视频 |
| 查看诊断 | 查看设备、路径和挂载日志，便于定位问题 |

## 常见问题

**为什么需要 Root？** 其他应用的 `Android/data` 受 Android 文件隔离保护；本模块还需要创建跨挂载环境可见的 bind mount。

**会复制、移动或转码视频吗？** 不会。新入口指向原文件，原应用仍可写入，播放器入口为只读。

**原应用删除视频后，映射里还在吗？** 不在。映射不保存第二份数据；清理缓存、删除文件或卸载源应用可能使视频消失。

**显示“等待源目录”？** 先解锁手机，让源应用实际下载文件，并确认选择了存放视频的子目录。

**提示目标目录非空或挂载冲突？** 换一个未使用的映射名称。模块不会覆盖已有文件，也不会强制卸载其他模块的挂载。

**提示目录正在使用？** 先停止播放，再重新应用。后台也会定期重试解除挂载。

**为什么有文件但不能播放？** 未完成下载、分片缓存、加密视频或播放器不支持的格式，不会因为目录映射就变成可播放视频。

**支持哪些路径？** 主用户共享存储中的 `Android/data/<包名>/<子目录>`、`Android/media/<包名>/<子目录>`，以及 `Download`、`Movies`、`DCIM` 的子目录。不能映射整个 `Android/data`、私有的 `/data/data` 或 `/data/user`，也不能把 DirBridge 输出目录再次作为来源。

## 已验证环境与范围

在 **2211133C / Android 17 / 澎湃 OS4.0.0.12.XMCCNXM / KernelSU BusyBox 1.36.1.1** 上，已验证路径保存、init 与 MediaProvider 环境中的只读挂载、普通 ADB Shell 目录枚举和中文执行输出。测试时 SELinux 为 Enforcing。

MX 的实际播放、重启后的自动恢复，以及其他 ROM、Android 版本和 Root 管理器组合，尚未完成验证。Android 10 是安装器下限，不等于所有 Android 10 及以上设备均已通过测试。Magisk 和 APatch 不在当前安装器支持范围内。

详细记录见 [验证记录](docs/VALIDATION.md)、[实机检查清单](docs/DEVICE_TEST.md)和[实现说明](docs/ARCHITECTURE.md)。

## 停用与卸载

先停止播放，再暂停全部或在 KernelSU 中禁用模块。后台会在下一轮尝试解除挂载，禁用后重启不会重建映射。

卸载脚本尝试解除本模块挂载；配置保留在 `/data/adb/dirbridge`。空的 `Movies/DirBridge` 入口目录也会保留，可在卸载并重启后自行删除空目录。重新安装后如果处于暂停状态，点击“恢复全部”。

## 从源码构建

需要 Python 3，无 pip 依赖：

```sh
git clone https://github.com/Liebig773/DirBridge.git
cd DirBridge
python scripts/build.py
```

生成的安装包、源码包和校验值位于 `dist/`。构建固定 ZIP 文件顺序、时间戳、LF 换行和 Unix 权限，便于复现。

运行测试：

```sh
python tests/test_core.py
node --test tests/model.test.cjs
npm install --ignore-scripts
npx playwright install chromium
npm run test:ui
```

Windows 可设置 `DIRBRIDGE_BUSYBOX` 指向 BusyBox for Windows，`CHROME_PATH` 指向本地 Chrome。Linux 真实挂载测试应在隔离的挂载命名空间运行：

```sh
sudo unshare --mount --propagation private sh tests/linux-mount.sh
```

仓库包含 [GitHub Actions 工作流](.github/workflows/ci.yml)。自动化测试验证代码和 Linux 挂载行为，不能代替 Android 真机播放测试。

## 反馈与贡献

欢迎通过 [Issues](https://github.com/Liebig773/DirBridge/issues) 反馈问题，或提交 Pull Request。请提供机型、Android/ROM 版本、KernelSU 版本、播放器版本，以及模块中的诊断信息；发布前删除诊断里的私人路径。

模块源码不包含第三方应用安装包、设备实际配置或视频文件。

## 许可证

Copyright © 2026 liebig。使用 [MIT License](LICENSE) 开源。

## 参考

- [KernelSU 模块指南](https://kernelsu.org/guide/module.html)
- [KernelSU WebUI](https://kernelsu.org/guide/module-webui.html)
- [AOSP 分区存储与 FUSE](https://source.android.com/docs/core/storage/scoped)

本项目独立编写，未包含 fbind、Apps2SD 或 MountX 的实现及专有辅助二进制。
