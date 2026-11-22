# 构建 NamiHub 桌面端

在 Windows x64 上安装 Flutter 稳定版和 Visual Studio 的「使用 C++ 的桌面开发」工作负载。本项目使用 Dart 3.8 或更高的 3.x 版本；具体依赖见提交的锁文件。

在源码根目录的 PowerShell 中运行：

```powershell
dart pub get
Set-Location desktop
flutter pub get
flutter build windows --release
.\build\windows\x64\runner\Release\NamiHub.exe
```

程序依赖同目录的 DLL 和 `data` 文件夹。要制作可传给另一台电脑的 ZIP，在 `desktop` 目录运行 `powershell -NoProfile -ExecutionPolicy Bypass -File tool/package.ps1`。主机状态默认保存在当前 Windows 用户的 LocalAppData。开发验收可用 `NAMI_HUB_DESKTOP_HOME` 指定独立目录。

## 验证

```powershell
flutter analyze
flutter test test
flutter test integration_test/library_flow_test.dart -d windows
```

原生测试使用临时资料库和动态端口。将 `NAMI_HUB_PREVIEW` 设为输出目录可得到实际窗口截图。已安装 Python 时，可把 `NAMI_HUB_TRAY_PROBE` 设为 `tool/tray_probe.py` 的完整路径，验证托盘隐藏、后台共享和恢复窗口。

[共享与配对说明](../README.md) · [命令行主机](../docs/interop.md)
