import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nami_hub/catalog.dart';
import 'library_host.dart';
import 'visual.dart';

void message(BuildContext c, String text) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
}

Future<void> _copy(BuildContext c, String value) async {
  try {
    await Clipboard.setData(ClipboardData(text: value));
    if (c.mounted) message(c, '已复制');
  } catch (_) {
    if (c.mounted) message(c, '复制失败，可选中内容手动复制。');
  }
}

Future<T?> _panel<T>(BuildContext c, String title, WidgetBuilder builder) =>
    showGeneralDialog<T>(
      context: c,
      barrierDismissible: true,
      barrierLabel: '关闭$title',
      barrierColor: const Color(0x660d100c),
      transitionDuration: motion(c, 230),
      requestFocus: true,
      transitionBuilder: (_, a, _, child) {
        final curve = a.drive(CurveTween(curve: Curves.easeOutCubic));
        return FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(.035, 0),
              end: Offset.zero,
            ).animate(curve),
            child: child,
          ),
        );
      },
      pageBuilder: (c, _, _) => SafeArea(
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Material(
              color: paper,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 432),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 23,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭',
                            onPressed: () => Navigator.pop(c),
                            icon: const Icon(Icons.close, size: 19),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      builder(c),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
Future<bool?> confirmPanel(
  BuildContext c,
  String title,
  String body,
  String action,
) => _panel<bool>(
  c,
  title,
  (c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(body, style: const TextStyle(color: muted, height: 1.6)),
      const SizedBox(height: 24),
      Wrap(
        spacing: 8,
        children: [
          ActionButton('取消', Icons.close, () => Navigator.pop(c, false)),
          ActionButton(
            action,
            Icons.check,
            () => Navigator.pop(c, true),
            primary: true,
          ),
        ],
      ),
    ],
  ),
);

class _Value extends StatelessWidget {
  const _Value(this.label, this.value, {this.copy = false, this.code = false});
  final String label, value;
  final bool copy, code;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                value,
                style: TextStyle(
                  fontSize: code ? 13 : 15,
                  fontFamily: code ? mono : null,
                  height: 1.45,
                ),
              ),
            ),
            if (copy)
              IconButton(
                tooltip: '复制$label',
                onPressed: () => _copy(c, value),
                icon: const Icon(Icons.copy, size: 16),
              ),
          ],
        ),
      ],
    ),
  );
}

Future<void> filePanel(BuildContext c, Resource r) => _panel(
  c,
  '文件详情',
  (c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(typeIcon(r.format.$1), size: 32, color: muted),
      const SizedBox(height: 13),
      SelectableText(
        r.name,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
      _Value('相对位置', r.relative, copy: true),
      _Value('格式 / 大小', '${r.format.$2}  ·  ${bytesLabel(r.size)}'),
      _Value('SHA-256', r.digest, copy: true, code: true),
    ],
  ),
);

Future<void> pairPanel(BuildContext c, LibraryHost h) {
  if (h.transport?.hub.activeCode == null) h.newCode();
  return _panel(c, '配对设备', (_) => _PairForm(host: h));
}

class _PairForm extends StatefulWidget {
  const _PairForm({required this.host});
  final LibraryHost host;
  @override
  State<_PairForm> createState() => _PairFormState();
}

class _PairFormState extends State<_PairForm> {
  String? selected;
  late bool manual;
  late Set<String> previousDevices;
  @override
  void initState() {
    super.initState();
    manual = !(widget.host.transport?.discoverable ?? false);
    previousDevices = widget.host.catalog!.devices.keys.toSet();
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(
    listenable: widget.host,
    builder: (c, _) {
      final host = widget.host, transport = host.transport;
      if (transport == null) return const Text('共享已停止');
      final urls = transport.urls;
      final addr =
          selected ??
          urls.where((url) => Uri.parse(url).host != '127.0.0.1').firstOrNull ??
          urls.firstOrNull;
      final code = transport.hub.activeCode;
      final added = host.catalog!.devices.keys.any(
        (id) => !previousDevices.contains(id),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (code != null)
            Text(
              transport.discoverable
                  ? '在同一局域网的 Nami 应用中输入这八位数字。'
                  : '自动发现暂不可用。请在客户端选择手动连接。',
              style: const TextStyle(color: muted, height: 1.55, fontSize: 14),
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(19, 15, 10, 14),
            decoration: BoxDecoration(
              color: dark,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code == null ? (added ? '已完成配对' : '配对码已失效') : '一次性配对码',
                  style: const TextStyle(color: steel, fontSize: 12),
                ),
                if (code != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          alignment: Alignment.centerLeft,
                          fit: BoxFit.scaleDown,
                          child: SelectableText(
                            '${code.substring(0, 4)} ${code.substring(4)}',
                            style: const TextStyle(
                              fontFamily: mono,
                              fontSize: 39,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: paper,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '复制配对码',
                        onPressed: () => _copy(c, code),
                        icon: const Icon(Icons.copy, size: 17, color: paper),
                      ),
                    ],
                  ),
                  _Countdown(
                    key: ValueKey(transport.hub.codeDeadline),
                    deadline: transport.hub.codeDeadline,
                    isActive: () => transport.hub.activeCode == code,
                    onExpired: () => setState(() {}),
                  ),
                ],
                if (code == null)
                  ActionButton('生成新配对码', Icons.refresh, () {
                    previousDevices = host.catalog!.devices.keys.toSet();
                    host.newCode();
                  }, onDark: true),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              expanded: manual,
              child: TextButton.icon(
                icon: Icon(
                  manual ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                label: const Text('手动连接'),
                onPressed: () => setState(() => manual = !manual),
              ),
            ),
          ),
          if (manual) ...[
            if (addr != null)
              _Value('连接地址', addr, copy: true, code: true)
            else
              const Text('当前没有可用的网卡地址。'),
            if (urls.length > 1)
              Align(
                alignment: Alignment.centerLeft,
                child: PopupMenuButton<String>(
                  tooltip: '选择网卡地址',
                  onSelected: (v) => setState(() => selected = v),
                  itemBuilder: (_) => [
                    for (final url in urls)
                      CheckedPopupMenuItem(
                        value: url,
                        checked: url == addr,
                        child: Text(url),
                      ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swap_horiz, size: 16, color: muted),
                        SizedBox(width: 6),
                        Text(
                          '切换网卡地址',
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            _Value(
              '证书指纹 · SHA-256',
              transport.fingerprint,
              copy: true,
              code: true,
            ),
          ],
        ],
      );
    },
  );
}

class _Countdown extends StatefulWidget {
  const _Countdown({
    super.key,
    required this.deadline,
    required this.isActive,
    required this.onExpired,
  });
  final DateTime deadline;
  final bool Function() isActive;
  final VoidCallback onExpired;
  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  late final Timer timer;
  int get seconds =>
      (widget.deadline.difference(DateTime.now()).inMilliseconds / 1000)
          .ceil()
          .clamp(0, 300);
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (seconds == 0 || !widget.isActive()) {
        timer.cancel();
        widget.onExpired();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = seconds;
    return Text(
      '剩余 ${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}',
      style: const TextStyle(color: steel, fontSize: 12, fontFamily: mono),
    );
  }
}

class DeviceList extends StatelessWidget {
  const DeviceList({super.key, required this.host});
  final LibraryHost host;
  @override
  Widget build(BuildContext c) {
    final all = host.catalog?.devices.entries.toList() ?? [];
    if (all.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: rail,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            const Icon(Icons.devices_outlined, size: 40, color: muted),
            const SizedBox(height: 16),
            const Text(
              '还没有已授权设备',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              '配对后的阅读器、音乐和视频客户端会出现在这里。',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '已授权 · ${all.length}',
          style: const TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, color: rule),
        for (final e in all)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 2,
              vertical: 5,
            ),
            leading: const Icon(Icons.devices_other_outlined, color: muted),
            title: Text(e.value['name'] as String),
            subtitle: const Text(
              '可读取当前资料库',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            trailing: PopupMenuButton<String>(
              tooltip: '管理设备',
              icon: const Icon(Icons.more_horiz),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'id', child: Text('复制设备 ID')),
                PopupMenuItem(value: 'revoke', child: Text('撤销授权')),
              ],
              onSelected: (action) async {
                if (action == 'id') {
                  await _copy(c, e.key);
                  return;
                }
                if (await confirmPanel(
                      c,
                      '撤销设备授权？',
                      '“${e.value['name']}” 需要重新配对才能继续读取资料库。',
                      '撤销授权',
                    ) ==
                    true) {
                  host.revoke(e.key);
                }
              },
            ),
          ),
      ],
    );
  }
}
