import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nami_hub/catalog.dart';
import 'package:path/path.dart' as p;

import 'library_host.dart';
import 'library_index.dart';
import 'panels.dart';
import 'visual.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(HubApp(host: LibraryHost.windows()));
}

class HubApp extends StatelessWidget {
  const HubApp({super.key, required this.host});
  final LibraryHost host;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NamiHub',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: paper,
      fontFamily: 'Segoe UI',
      fontFamilyFallback: const ['Microsoft YaHei UI', 'Microsoft YaHei'],
      colorScheme: ColorScheme.fromSeed(
        seedColor: signal,
        surface: paper,
      ).copyWith(primary: const Color(0xffa73514), onSurface: ink),
      focusColor: signal.withValues(alpha: .20),
      splashFactory: NoSplash.splashFactory,
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 450),
      ),
    ),
    home: LibraryWindow(host: host),
  );
}

class LibraryWindow extends StatefulWidget {
  const LibraryWindow({super.key, required this.host});
  final LibraryHost host;
  @override
  State<LibraryWindow> createState() => _LibraryWindowState();
}

class _LibraryWindowState extends State<LibraryWindow> {
  LibraryHost get h => widget.host;
  bool devices = false;
  String kind = 'all', search = '';
  final field = TextEditingController(), queryFocus = FocusNode();
  @override
  void initState() {
    super.initState();
    h.initialize();
  }

  @override
  void dispose() {
    field.dispose();
    queryFocus.dispose();
    super.dispose();
  }

  Future<void> choose() async {
    if (h.busy) return;
    if (h.online) {
      final ok = await confirmPanel(
        context,
        '切换资料库？',
        '当前共享会停止。选好新目录后，可以重新开始共享。',
        '切换目录',
      );
      if (ok != true || !mounted) return;
    }
    try {
      final path = await const MethodChannel(
        'nami_hub/desktop',
      ).invokeMethod<String>('choose');
      if (path == null || !mounted) return;
      await h.choose(path);
      if (mounted && h.error == null) {
        setState(() {
          kind = 'all';
          search = '';
          field.clear();
        });
      }
    } on PlatformException {
      if (mounted) message(context, '文件夹选择器未能打开，请重试。');
    }
  }

  Future<void> share() async {
    if (h.catalog == null) {
      await choose();
      return;
    }
    if (h.online) {
      await pairPanel(context, h);
      return;
    }
    await h.start();
    if (mounted && h.online) await pairPanel(context, h);
  }

  Future<void> stop() async {
    if (await confirmPanel(
          context,
          '停止局域网共享？',
          '设备正在读取的内容可能中断，已有授权会保留。',
          '停止共享',
        ) ==
        true) {
      await h.stop();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: h,
    builder: (context, _) {
      final width = MediaQuery.sizeOf(context).width;
      final compact = width < 860, tiny = width < 610;
      final index = h.index;
      final files = index.files;
      final activeKind = index.count(kind) > 0 ? kind : 'all';
      final visible = index.filter(activeKind, search);
      final side = tiny
          ? 16.0
          : width >= 1100
          ? 42.0
          : 25.0;
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              _Rail(
                compact: compact,
                tiny: tiny,
                devices: devices,
                online: h.online,
                count: h.catalog?.devices.length ?? 0,
                onChange: (v) => setState(() => devices = v),
              ),
              Expanded(
                child: FocusTraversalGroup(
                  child: _SurfaceEntrance(
                    key: ValueKey(devices),
                    child: CustomScrollView(
                      key: PageStorageKey(devices ? 'devices' : 'library'),
                      slivers: [
                        if (devices)
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              side,
                              tiny ? 18 : 30,
                              side,
                              0,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '授权设备',
                                      style: TextStyle(
                                        fontSize: tiny ? 27 : 34,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -1.2,
                                      ),
                                    ),
                                  ),
                                  if (h.busy)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: SizedBox.square(
                                        dimension: 17,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  ActionButton(
                                    h.catalog == null
                                        ? '选择目录'
                                        : (h.online ? '配对设备' : '开始共享'),
                                    h.catalog == null
                                        ? Icons.folder_open_outlined
                                        : (h.online
                                              ? Icons.add
                                              : Icons.wifi_tethering),
                                    h.busy ? null : share,
                                    primary: true,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (h.error != null)
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(side, 12, side, 0),
                            sliver: SliverToBoxAdapter(
                              child: Material(
                                color: const Color(0xffffe9df),
                                child: ListTile(
                                  title: Text(
                                    h.error!,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  trailing: IconButton(
                                    tooltip: '重新选择目录',
                                    onPressed: choose,
                                    icon: const Icon(Icons.folder_open),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (!devices) ...[
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              side,
                              tiny ? 18 : 30,
                              side,
                              0,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: _Cover(
                                host: h,
                                index: index,
                                kind: activeKind,
                                onShare: h.busy || h.catalog == null
                                    ? null
                                    : share,
                                tiny: tiny,
                                onChoose: h.busy ? null : choose,
                                onStop: h.busy ? null : stop,
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(side, 26, side, 0),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _LibraryToolbar(
                                    index: index,
                                    selectedKind: activeKind,
                                    controller: field,
                                    focusNode: queryFocus,
                                    busy: h.busy,
                                    onRefresh: h.busy || h.catalog == null
                                        ? null
                                        : h.refresh,
                                    onQuery: (value) =>
                                        setState(() => search = value),
                                    onSelect: (value) =>
                                        setState(() => kind = value),
                                  ),
                                  const SizedBox(height: 13),
                                  const Divider(height: 1, color: rule),
                                  _Columns(tiny: tiny, header: true),
                                ],
                              ),
                            ),
                          ),
                          if (visible.isEmpty)
                            SliverPadding(
                              padding: EdgeInsets.symmetric(
                                horizontal: side,
                                vertical: 24,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: Text(
                                  h.busy
                                      ? '正在读取资料库…'
                                      : files.isEmpty
                                      ? '目录中还没有文件。'
                                      : '没有匹配的文件。',
                                  style: const TextStyle(color: muted),
                                ),
                              ),
                            ),
                          SliverPadding(
                            padding: EdgeInsets.symmetric(horizontal: side),
                            sliver: SliverList.builder(
                              itemCount: visible.length,
                              itemBuilder: (c, i) {
                                final r = visible[i];
                                return Material(
                                  color: paper,
                                  child: InkWell(
                                    onTap: () => filePanel(c, r),
                                    child: _Columns(
                                      tiny: tiny,
                                      resource: r,
                                      showPath: index.ambiguousName(r),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ] else
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(side, 24, side, 0),
                            sliver: SliverToBoxAdapter(
                              child: DeviceList(host: h),
                            ),
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _SurfaceEntrance extends StatelessWidget {
  const _SurfaceEntrance({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext c) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: motion(c, 190),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (_, t, child) => Opacity(
      opacity: .80 + .20 * t,
      child: Transform.translate(offset: Offset(0, 7 * (1 - t)), child: child),
    ),
  );
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.compact,
    required this.tiny,
    required this.devices,
    required this.online,
    required this.count,
    required this.onChange,
  });
  final bool compact, tiny, devices, online;
  final int count;
  final ValueChanged<bool> onChange;
  @override
  Widget build(BuildContext c) {
    Widget nav(bool value, String name, IconData icon) {
      final active = devices == value;
      return Semantics(
        selected: active,
        child: Tooltip(
          message: compact ? name : '',
          child: Material(
            color: active ? const Color(0xffdfe2d9) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            child: InkWell(
              onTap: () => onChange(value),
              borderRadius: BorderRadius.circular(7),
              child: SizedBox(
                height: 44,
                child: Row(
                  mainAxisAlignment: compact
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    if (!compact) const SizedBox(width: 12),
                    Icon(icon, size: 19, color: active ? ink : muted),
                    if (!compact) ...[
                      const SizedBox(width: 12),
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: active ? ink : muted,
                        ),
                      ),
                      if (value && count > 0) ...[
                        const Spacer(),
                        Text(
                          '$count',
                          style: const TextStyle(
                            fontFamily: mono,
                            color: muted,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: compact ? (tiny ? 52 : 66) : 172,
      color: rail,
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 12, vertical: 22),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.only(left: compact ? 0 : 6),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                const HubMark(size: 30),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  const Text(
                    'NamiHub',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 49),
          nav(false, '资料库', Icons.layers_outlined),
          const SizedBox(height: 4),
          nav(true, '授权设备', Icons.devices_outlined),
          const Spacer(),
          const Divider(color: rule),
          const SizedBox(height: 10),
          Tooltip(
            message: Platform.localHostname,
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                if (!compact) const SizedBox(width: 9),
                const Icon(Icons.computer, size: 20, color: muted),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '本机',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          Platform.localHostname,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: mono,
                            fontSize: 11,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({
    required this.host,
    required this.index,
    required this.kind,
    required this.tiny,
    required this.onChoose,
    required this.onShare,
    required this.onStop,
  });
  final LibraryHost host;
  final LibraryIndex index;
  final String kind;
  final bool tiny;
  final VoidCallback? onChoose, onStop, onShare;
  @override
  Widget build(BuildContext c) {
    final types = [
      'book',
      'video',
      'other',
      'audio',
    ].where((k) => index.count(k) > 0).toList();
    final has = host.catalog != null;
    final left = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: host.online ? signal : steel,
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: host.trayActive
                  ? '关闭窗口后继续共享，可从系统托盘打开或退出。'
                  : host.online
                  ? '关闭窗口将停止共享。'
                  : '只有开始共享后，已配对的设备才能读取文件。',
              child: Text(
                host.online ? '局域网共享中' : '尚未共享',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xffc6cbbf),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          host.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: paper,
            fontWeight: FontWeight.w600,
            fontSize: tiny ? 30 : 39,
            height: 1.15,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 9),
        if (has)
          Tooltip(
            message: host.catalog!.root.path,
            child: Text(
              host.catalog!.root.path.length > 54
                  ? '…${p.separator}${p.split(host.catalog!.root.path).reversed.take(3).toList().reversed.join(p.separator)}'
                  : host.catalog!.root.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: mono,
                color: steel,
              ),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          has
              ? '${index.files.length} 个文件   ·   ${bytesLabel(index.totalBytes)}'
              : '从本机选择共享文件夹',
          style: const TextStyle(color: steel, fontSize: 13),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 6,
          children: [
            if (has)
              ActionButton(
                host.online ? '配对设备' : '开始共享',
                host.online ? Icons.add : Icons.wifi_tethering,
                onShare,
                primary: true,
              ),
            ActionButton(
              has ? '更换目录' : '选择目录',
              Icons.folder_open_outlined,
              onChoose,
              onDark: true,
            ),
            if (host.online)
              ActionButton(
                '停止共享',
                Icons.stop_circle_outlined,
                onStop,
                onDark: true,
              ),
          ],
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark,
        borderRadius: BorderRadius.circular(13),
      ),
      child: LayoutBuilder(
        builder: (c, b) {
          final artWidth = b.maxWidth >= 490
              ? (b.maxWidth * .43).clamp(160.0, 405.0)
              : 0.0;
          return Stack(
            alignment: Alignment.centerRight,
            children: [
              if (artWidth > 0)
                Positioned.fill(
                  left: b.maxWidth - artWidth,
                  right: 8,
                  child: ArchiveStack(
                    types: types,
                    selected: kind,
                    online: host.online,
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  tiny ? 20 : 30,
                  27,
                  artWidth + 12,
                  27,
                ),
                child: Align(alignment: Alignment.centerLeft, child: left),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LibraryToolbar extends StatelessWidget {
  const _LibraryToolbar({
    required this.index,
    required this.selectedKind,
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.onRefresh,
    required this.onQuery,
    required this.onSelect,
  });
  final LibraryIndex index;
  final String selectedKind;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final VoidCallback? onRefresh;
  final ValueChanged<String> onQuery, onSelect;

  @override
  Widget build(BuildContext context) {
    final heading = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '库内文件',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 6),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          IconButton(
            tooltip: '重新索引',
            icon: const Icon(Icons.refresh, size: 18),
            color: muted,
            onPressed: onRefresh,
          ),
      ],
    );
    if (index.files.isEmpty) return heading;

    final search = TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onQuery,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: '搜索文件',
        prefixIcon: const Icon(Icons.search, size: 18, color: muted),
        prefixIconConstraints: const BoxConstraints(minWidth: 36),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清除搜索',
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  controller.clear();
                  onQuery('');
                  focusNode.requestFocus();
                },
              ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
        filled: true,
        fillColor: rail,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: muted),
        ),
      ),
    );
    final filters = Wrap(
      spacing: 5,
      runSpacing: 3,
      children: [
        for (final key in [
          'all',
          ...kinds.keys.where((key) => index.count(key) > 0),
        ])
          _Filter(
            label: key == 'all' ? '全部' : kinds[key]!,
            count: key == 'all' ? index.files.length : index.count(key),
            value: key == selectedKind,
            onTap: () => onSelect(key),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 550;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wide)
              Row(
                children: [
                  Expanded(child: heading),
                  SizedBox(width: 205, child: search),
                ],
              )
            else
              heading,
            const SizedBox(height: 8),
            filters,
            if (!wide) ...[const SizedBox(height: 8), search],
          ],
        );
      },
    );
  }
}

class _Filter extends StatelessWidget {
  const _Filter({
    required this.label,
    required this.value,
    required this.count,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext c) => Semantics(
    selected: value,
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: value ? ink : muted,
        backgroundColor: value ? const Color(0xffe3e6dd) : Colors.transparent,
        minimumSize: const Size(44, 35),
        padding: const EdgeInsets.symmetric(horizontal: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        textStyle: TextStyle(
          fontSize: 13,
          fontWeight: value ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: TextStyle(fontFamily: mono, fontSize: 11, color: muted),
          ),
        ],
      ),
    ),
  );
}

class _Columns extends StatelessWidget {
  const _Columns({
    required this.tiny,
    this.header = false,
    this.showPath = false,
    this.resource,
  });
  final bool tiny, header, showPath;
  final Resource? resource;
  @override
  Widget build(BuildContext c) {
    final r = resource;
    const caption = TextStyle(color: muted, fontSize: 12);
    return Container(
      constraints: BoxConstraints(minHeight: header ? 35 : 48),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: rule, width: .7)),
      ),
      child: Row(
        children: [
          Expanded(
            child: header
                ? const Text('文件名', style: caption)
                : Row(
                    children: [
                      Icon(typeIcon(r!.format.$1), color: muted, size: 19),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (showPath)
                              Text(
                                p.dirname(r.relative) == '.'
                                    ? '资料库根目录'
                                    : p.dirname(r.relative),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: caption,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          if (!tiny)
            SizedBox(
              width: 94,
              child: Text(
                header
                    ? '格式'
                    : p.extension(r!.name).replaceFirst('.', '').toUpperCase(),
                style: header
                    ? caption
                    : const TextStyle(
                        fontFamily: mono,
                        fontSize: 12,
                        color: muted,
                      ),
              ),
            ),
          SizedBox(
            width: tiny ? 72 : 90,
            child: Text(
              header ? '大小' : bytesLabel(r!.size),
              textAlign: TextAlign.end,
              style: header
                  ? caption
                  : const TextStyle(
                      fontFamily: mono,
                      color: muted,
                      fontSize: 12,
                    ),
            ),
          ),
          SizedBox(
            width: tiny ? 18 : 30,
            child: header
                ? null
                : const Align(
                    alignment: Alignment.centerRight,
                    child: Icon(Icons.chevron_right, color: muted, size: 16),
                  ),
          ),
        ],
      ),
    );
  }
}
