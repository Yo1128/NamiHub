# NamiHub

NamiHub 把 Windows 电脑上的文件夹变成只读的局域网资料库。你可以查看正在共享的书籍、视频和音乐，用八位码授权设备，也可以随时停止共享。

[下载 Windows 桌面版（x64 便携 ZIP）](https://github.com/Yo1128/NamiHub/releases/download/v0.2.1/NamiHub-Desktop-0.2.1-windows-x64.zip) · [产品页](https://yo1128.github.io/NamiHub/) · [0.2.1 发行说明与校验值](https://github.com/Yo1128/NamiHub/releases/tag/v0.2.1) · [从源码构建](desktop/README.md)

![Windows 桌面端的共享资料库与分类文件列表](docs/assets/library.webp)

## 开始共享

1. 将 Windows 桌面版 ZIP 完整解压，打开 `NamiHub.exe`。点击「更换目录」选择文件夹，首页会列出即将共享的文件。
2. 点击「开始共享」。在同一局域网内，用下表中支持配对的客户端打开 NamiHub 入口，输入电脑上显示的八位码。每个应用单独配对。
3. 点书名或片名即可打开。需要离线使用时，在客户端的条目菜单中选择「下载到本机」。

共享时关闭窗口，主机会留在系统托盘。要结束共享，点击「停止共享」，或使用托盘菜单中的「退出并停止共享」。在「授权设备」中可以撤销单个应用的访问权限。

## Nami 系列客户端

| 产品 | 用途 | 与 NamiHub 配合 |
| --- | --- | --- |
| [NamiRead](https://yo1128.github.io/NamiRead/#hub-title) · Android | 阅读 TXT 和 EPUB，保存书架、进度与书签 | 0.7.0 在「书架 → ＋ → 浏览 NamiHub 书库」配对，按需读正文，也可下载整本。 |
| [NamiView](https://yo1128.github.io/NamiHub/#namiview) · Windows | 按系列和分季整理动漫，记录观看进度 | Windows 发布候选版在「媒体库 → NamiHub」配对，点片名在线播放或续播，从单集菜单可下载到本机。 |
| [NamiListen](https://yo1128.github.io/NamiListen/) · Windows、Android | 按专辑和歌单播放本机音乐，查看同步歌词 | 当前从本机文件夹导入音乐。八位码配对、在线收听和按曲下载仍在规划中。 |

## 连接问题

- **找不到主机**　检查两端是否在可互访的 IPv4 局域网内。自动发现使用 UDP 47832，共享服务默认使用 HTTPS 8443。网络限制广播时，可在客户端展开「手动连接」，核对主机显示的地址和证书指纹。
- **配对码已使用或过期**　在电脑上生成新码。原有设备继续使用各自保存的授权。
- **文件有变动**　在资料库中刷新，客户端重新读取目录后即可看到新的内容版本。

## 项目结构

| 目录 | 用途 |
| --- | --- |
| [desktop](desktop/) | Flutter Windows 桌面端，包含资料库、文件搜索、配对窗口和系统托盘 |
| [lib](lib/) 和 [bin](bin/) | 文件索引、HTTPS 服务与命令行主机 |
| [packages/nami_hub_client](packages/nami_hub_client/) | Dart 客户端，支持配对、目录、按范围读取和断点下载 |
| [fixtures](fixtures/) | 可再生成的图书、音频和视频联调样本 |

开发者可使用[Dart SDK](packages/nami_hub_client/README.md) 或 [HTTP API v1](docs/api-v1.md) 接入。另见[命令行主机联调](docs/interop.md)、[八位码配对协议](docs/lan-pairing.md)和[各客户端接入进展](docs/client-handoff.md)。
