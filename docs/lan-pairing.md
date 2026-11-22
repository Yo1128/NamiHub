# NamiHub 八位码接入与联调

主机和公共 Dart SDK 版本为 **0.2.0**，NamiRead Android 客户端为 **0.6.1+19**。电脑点击「开始共享」，手机打开「书架 → ＋ → 浏览 NamiHub 书库」，只输入电脑显示的八位码。配对后可直接浏览共享的 TXT 和 EPUB。一次配对只授权当前安装，从主机的「授权设备」可单独撤权。

## 客户端如何接入

```dart
final client = await HubLan.pair(code, 'NamiRead · Android');
try {
  final origin = client.origin;
  final pin = client.certificateSha256;
  final session = client.session!;
  // 保存 origin、pin 和 session.hubId，使用平台凭据存储保护 deviceId 和 token。
  final books = await client.resources(type: 'book').toList();
} finally {
  client.close();
}
```

恢复使用 `await HubLan.restore(origin, pin, session)`。SDK 先访问旧地址的公开身份接口，核对证书和 `hubId` 后才附加会话。旧地址不可达时重新发现，找到同一身份和证书后返回已连接的客户端。调用方将其新地址写回凭据存储。重新配对某个已有来源时，可向 `pair` 传入 `expectedHubId`；返回的会话总是经过新输入的码验证。Android 的 `localGateway` 是可选参数，可取自当前 Wi-Fi 或有线局域网的默认 IPv4 网关，用于电脑热点。两个方法均由调用方在使用后关闭连接。

同一 SDK 可通过 `resources(type: 'audio')` 或 `resources(type: 'video')` 供 NamiListen、NamiView 使用。原生播放器仍需对自己的连接校验证书。独立包内直接运行 `dart run example/pair_lan.dart` 可验证首次配对和书目读取。

## 发现与配对

1. **寻找服务。** 客户端从每个活动 IPv4 接口向 UDP 47832 发送带有随机请求标识的服务查询。电脑以单播返回此标识、Hub ID、HTTPS 端口和证书指纹。SDK 使用响应包的源地址，仅向已匹配的候选主机发起握手。即使配对窗口已关闭，已有设备仍可利用发现服务找回原主机。
2. **筛选窗口。** 每次生成配对码时，主机也生成随机的 128 位窗口标识。有效窗口的响应另含该标识和一个 4 位筛选值，即 SHA-256(`NamiHub/route/1:<窗口标识>:<八码>`) 首字节的低四位。该值只用于缩小候选范围。多台候选仍匹配时，客户端提示在目标电脑取新码。同一窗口从多网卡重复出现时按主机、证书和窗口去重。
3. **证明持有码。** SDK 在候选证书固定的 HTTPS 连接上请求 `POST /v1/pair/begin`，提交窗口标识、设备名称和 SRP 公共值 A。主机返回一次性 ticket 和公共值 B。SDK 向 `POST /v1/pair/finish` 提交 ticket 和客户端证明 M1。主机验证 M1 后发放设备会话，返回 M2。SDK 验证 M2 后才接受并保存会话。两端使用 Pointy Castle 的 SRP-6a、RFC 5054 的 3072 位组和 SHA-256。身份输入绑定协议名、Hub ID、TLS 证书指纹、设备名称和窗口标识。[Pointy Castle SRP 实现](https://pub.dev/documentation/pointycastle/latest/impl.srp_client/SRP6Client-class.html) · [RFC 5054](https://www.rfc-editor.org/rfc/rfc5054)
4. **关闭窗口。** 配对码有效五分钟。手动与自动入口共用五次验证失败的限额。成功一次、重新生成或耗尽次数都会停用原码。票据仅用于当前窗口，30 秒有效且只能提交一次。主机限制未完成票据和新握手数量。UDP 查询、发现响应和读取诊断记录均排除完整配对码和设备 token。

## 错误与用户动作

| SDK 结果 | 用户可采取的动作 |
|---|---|
| `discovery_empty` | 确认电脑正在共享、手机与电脑可互访，重试或选「手动连接」。 |
| `ambiguous_pair_code` | 在目标电脑生成新码，再在当前页面输入。 |
| `invalid_or_expired_code`、`invalid_pair_code`、`pairing_closed` | 核对八位数和前导零，已用、已过期或锁定时取新码。 |
| `pairing_busy` | 稍后重试，原有设备仍可使用。 |
| `certificate_mismatch`、TLS 验证失败、`hub_identity_changed`、`invalid_pair_response` | 核对主机。需要接受新证书时，用新码重新配对，或手动核验主机显示的完整指纹。 |
| 书目或下载返回 401 | 旧授权已失效，提示重新配对。已下载的书、进度及书签保存在手机。 |

## 升级与复验

同一份资料库继续使用原状态目录。旧 NamiRead 0.6.0 可沿用原授权，或通过原地址、指纹和配对码连接。新 NamiRead 的「手动连接」可接入 0.1.0 主机。发现受限时，仅需 HTTPS 可达即可使用手动入口。局域网发现依赖 IPv4，UDP 47832 或 Wi-Fi 客户端互访被阻止时使用手动连接。

在 Windows 主工程运行 `dart run tool/check_pairing.dart`，可复验双主机选择、前导零、冲突、共享重试额度、旧码重用、重定位、证书变化及撤权。运行 `python tool/package_windows.py` 会从打包后的 CLI 和 SDK 分别复验手动及八位码连接。在 NamiRead 的 Android 发布包中，按第一段进入书目，关闭进程、重开，再在电脑上撤权并刷新书目，可复验客户端保存与恢复授权的行为。
