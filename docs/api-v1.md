# NamiHub HTTP API v1

实现版本 0.2.1。以 `https://主机:端口/v1` 为前缀。JSON 使用 UTF-8。客户端应容许响应增加字段。连接地址和凭据可以更新，持久引用使用 `(hubId, resourceId)`，缓存另存 `contentVersion`。0.2.0 新增可选的[局域网发现与配对证明](lan-pairing.md)，保留 0.1.0 的手动配对和已授权设备接口。

## 连接与配对

| 方法与路径 | 认证 | 成功响应 |
|---|---|---|
| `GET /v1/info` | 已信任主机证书 | 200，`{"apiVersion":1,"hubId":"…"}` |
| `POST /v1/pair` | 主机显示的指纹和配对码 | 201，`{"hubId":"…","deviceId":"…","accessToken":"…"}` |
| `GET /v1/resources` | Bearer | 200，含 `items`、`nextCursor` |
| `GET /v1/resources/{id}` | Bearer | 200，单项资源元数据 |
| `GET /v1/resources/{id}/content` | Bearer | 200 完整内容或 206 单一字节范围 |
| `HEAD /v1/resources/{id}/content` | Bearer | 与相应 GET 相同的状态与响应头，响应正文为空 |

配对请求使用 `Content-Type: application/json` 与正文 `{"code":"01234567","clientName":"NamiRead · 我的手机"}`。配对码为字符串，有效期 5 分钟，一次成功后失效。连续输错 5 次后需在主机重新生成。之后通过 `Authorization: Bearer <accessToken>` 携带凭据。主机只保存凭据摘要。每次应用安装独立配对，可以分别撤权。

## 目录与资源

目录查询参数为 `type`、`limit`、`cursor`。`type` 取 `book`、`audio`、`video`、`other`；省略时返回全部类型。每页默认 50 项，取值 1–100。下一页原样携带上页的 `nextCursor`，沿用类型过滤；`null` 结束。列表按 ID 排序，每次请求读取当前目录，重扫后可从第一页刷新。扩展名分类仅供浏览，具体格式能否打开由客户端确定。

| 资源字段 | v1 含义 |
|---|---|
| `resourceId` | 当前 Hub 中的持久 ID。重启和同一位置的内容更新保留它 |
| `displayName` | 含扩展名的显示文件名；服务端绝对路径仅留在主机 |
| `type`、`mimeType` | 内容分类与 HTTP 媒体类型 |
| `sizeBytes` | 原始文件的字节数 |
| `contentVersion`、`sha256` | 此版两者均为文件字节的 SHA-256，小写十六进制。应用分别保存版本与校验值 |

固定目录见 [catalog.json](../fixtures/catalog.json)，三页示例见 [第一页](../fixtures/pages/first.json)、[第二页](../fixtures/pages/second.json)、[最后一页](../fixtures/pages/last.json)。固定数据使用 `fixture_*` ID；实际服务给每个新资料库分配独立 ID。联调时按文件名和摘要匹配样本，并使用本机服务返回的 ID 请求文件。

## 文件读取

完整读取返回 `Content-Length`、`Content-Type`、`Accept-Ranges: bytes` 和带双引号的 `ETag`。客户端从目录选择某一版后，应发送 `If-Match: "<contentVersion>"`。支持 `bytes=100-199`、`bytes=100-`、`bytes=-100`；编号从 0 开始，终点包含在内。部分响应为 206，携带 `Content-Range: bytes 起点-终点/总长` 和实际片段长度。超出文件尾的终点截到文件尾。空文件的完整 GET 返回 200 和零字节。

在线阅读、观看和收听共用此内容接口。客户端按需读取当前版本的范围，通过响应校验后即可把字节交给阅读器或解码器。播放缓冲和已读章节可以回收，打开资源无需等待整文件摘要校验。

用户主动保存离线副本时，根据同版部分文件长度续传，核对 206、范围、ETag 和总长。完整文件通过长度及 SHA-256 校验后才可发布为离线副本。SDK 的 `download` 已执行文件校验，网络中断默认自动重试一次。完整旧副本保留到新版成功可用为止。[客户端交付约定](client-handoff.md)

## 错误与恢复

JSON 错误示例为 `{"error":"version_changed"}`。HEAD 没有错误正文，使用状态码判断。网络连接失败和证书校验失败发生在 HTTP 之前。

| HTTP | 错误码 | 客户端处理 |
|---|---|---|
| 400 / 415 | `invalid_query`、`invalid_pair_request`、`expected_json` 等 | 修正参数或请求格式 |
| 401 | `unauthorized` | 停止当前远程读取，提示重新配对。已保存的本地副本按客户端策略管理 |
| 403 | `invalid_pair_code`、`pairing_closed` | 核对配对码，过期、已用或耗尽次数时从主机取新码 |
| 404 | `resource_missing`、`not_found` | 刷新目录，保留客户端原有进度 |
| 405 | `method_not_allowed` | 内容接口只提供 GET 和 HEAD |
| 409 | `rescan_required` | 已索引文件的大小或修改时间发生变化。主机执行 `rescan` 后重新获取元数据 |
| 412 | `version_changed` | 刷新元数据。在线会话按所选版本重新打开；主动下载的任务按版本隔离部分文件。保留已保存的旧版 |
| 416 | `range_not_satisfiable` | 读取 `Content-Range: bytes */总长`，重新核对偏移与版本。多段范围也返回此状态 |
| 408 / 413 / 500 | `request_timeout`、`body_too_large`、`server_error` | 分别处理超时、超限和主机错误 |

读取入口在打开文件前检查元数据；完成下载后再以整文件摘要确认内容。需要替换正在用于联调的原文件时，完成写入后执行 `rescan`。撤权会拒绝新请求并尝试中止活动传输，已进入客户端播放器缓冲区的字节由客户端控制。Hub 离线时展示离线状态并允许访问已校验的缓存。
