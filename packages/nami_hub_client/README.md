# nami_hub_client

供 Dart / Flutter 原生应用连接 NamiHub HTTP API v1。首次输入主机显示的八位码，用 `await HubLan.pair(code, clientName)` 获取已连接的 `HubClient`。持久保存 `client.origin`、`client.certificateSha256` 及安全存储中的 `client.session!`。重开时用 `await HubLan.restore(origin, pin, session)`，成功后保存可能变化的地址。两条路径用完均需 `close()`。Android 可传入当前 Wi-Fi 或以太网的 IPv4 网关作为可选的 `localGateway`，支持由电脑共享热点的网络。兼容旧服务时可手动输入地址、证书指纹和配对码。

| 调用 | 用途 |
|---|---|
| `HubClient(origin: ..., certificateSha256: ..., session: ...)` | 创建客户端，已有配对可传入以前保存的会话 |
| `info()`、`pair(code, clientName)` | 获取主机身份，首次配对并取得应用专属凭据 |
| `resources(type: ..., pageSize: ...)`、`resource(id)` | 逐页列资源或读取单项元数据 |
| `read(item, start: ..., end: ...)` | 返回当前版本的字节流，两端均为包含的字节位置，调用方负责消费或取消订阅 |
| `download(item, target, retries: 1)` | 允许 0–3 次网络重试，检查部分文件、版本与完整摘要，成功后替换目标 |
| `playbackRequest(item)` | 取得给原生输入使用的 URI、私密请求头和证书指纹 |
| `close()` | 释放网络连接 |

共享书籍、视频和音频默认通过 `read` 按需获取。用户选择「下载到本机」时才使用 `download` 创建可离线使用的完整副本。SDK 提供传输接口，在线阅读或播放、下载入口和进度由各客户端实现。

SDK 会在目标旁保存带版本的 `.part` 和用于协调写入的 `.lock`。调用方应为每个 Hub 资源选择独立的应用私有缓存位置，并在资源淘汰时回收旧版部分文件。凭据放在平台凭据存储中。播放请求头不应进入业务数据库、异常报告或日志。

运行自动配对示例

```powershell
dart pub get
dart run example/pair_lan.dart
# 手动连接旧主机
dart run example/connect.dart https://127.0.0.1:8443 <主机窗口显示的证书SHA256>
```

首次配对会消耗当前配对码，其他客户端使用主机 `pair` 命令重新取码。平台连接失败可能表现为 `SocketException`、`HandshakeException` 或超时；服务端业务错误以 `HubException.code` 和 `status` 提供。
