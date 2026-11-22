# 命令行主机

Windows x64 联调包包含主机、启动脚本和五个固定的测试文件。解压后，在目录中打开 PowerShell。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Start-NamiHub.ps1 -Lan
```

省略 `-Lan` 时只监听回环地址。默认 HTTPS 端口为 8443，可用 `-Port` 更改。需要观察播放器或阅读器发送的字节范围时，加上 `-TraceReads`。在源码目录运行同一脚本时需要 Dart SDK。

| 控制台命令 | 用途 |
| --- | --- |
| `pair` | 生成新的八位码。待用的旧码立即失效 |
| `devices` | 查看已配对的应用名称和设备 ID |
| `revoke DEVICE_ID` | 撤销一个设备的访问权限 |
| `rescan` | 重扫共享文件并更新目录 |
| `relink RESOURCE_ID 新相对路径` | 文件移走后、重扫前，用新路径关联原资源 ID |
| `quit` | 停止主机并退出 |

`-Root` 指定要共享的目录。`-StateDirectory` 指定这个资料库独立的状态目录，默认位于 `%LOCALAPPDATA%\NamiHub\interop-v1`。状态目录应位于共享范围之外。Windows 首次启动会生成本机 TLS 身份。手动核验时可使用 `hub-public.pem`；含私钥的 `tls.pem` 留在主机。自动化联调可通过受控的 `-OperatorPipe` 读取配对事件。

## 在 Windows 上复验

安装 Dart SDK、Python 3 和 FFmpeg 后，在源码根目录运行：

```powershell
dart pub get
dart analyze lib bin tool
dart run tool/check_pairing.dart
New-Item -ItemType Directory -Force build | Out-Null
dart compile exe bin/nami_hub.dart -o build/nami_hub.exe
python tool/verify.py
python tool/package_windows.py
```

验证使用临时目录和独立的主机身份，覆盖按范围读取、下载重试、版本变化、撤权和视频定位。[桌面端构建与验证](https://github.com/Yo1128/NamiHub/blob/main/desktop/README.md)
