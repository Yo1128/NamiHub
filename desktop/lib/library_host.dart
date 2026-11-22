import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nami_hub/catalog.dart';
import 'package:nami_hub/service.dart';
import 'package:nami_hub/transport.dart';
import 'package:path/path.dart' as p;

import 'library_index.dart';

class LibraryHost extends ChangeNotifier {
  LibraryHost({required this.home, required this.assets, this.port = 8443});
  factory LibraryHost.windows() => LibraryHost(
    home: Directory(
      Platform.environment['NAMI_HUB_DESKTOP_HOME'] ??
          p.join(Platform.environment['LOCALAPPDATA']!, 'NamiHub'),
    ),
    assets: Directory(
      p.join(p.dirname(Platform.resolvedExecutable), 'data', 'hub'),
    ),
  );
  final Directory home, assets;
  final int port;
  Catalog? catalog;
  HubTransport? transport;
  RandomAccessFile? _lock;
  bool busy = false;
  bool trayActive = false;
  Future<void> _tray(bool enabled) async {
    try {
      trayActive =
          await const MethodChannel(
            'nami_hub/desktop',
          ).invokeMethod<bool>('sharing', enabled) ??
          false;
    } on PlatformException {
      trayActive = false;
    } on MissingPluginException {
      trayActive = false;
    }
  }

  String? error;
  bool get online => transport != null;
  Directory get sample => Directory(p.join(assets.path, 'media'));
  bool get isSample =>
      catalog != null && p.equals(catalog!.root.path, sample.path);
  String get name => catalog == null
      ? '选择资料库'
      : isSample
      ? '示例资料库'
      : p.basename(catalog!.root.path).isEmpty
      ? catalog!.root.path
      : p.basename(catalog!.root.path);
  LibraryIndex index = LibraryIndex(const []);
  List<Resource> get files => index.files;
  File get _preferences => File(p.join(home.path, 'desktop-library.json'));

  Future<void> _run(String failure, Future<void> Function() operation) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await operation();
    } on SocketException catch (e) {
      error = '无法开始共享，请检查端口 $port 是否被占用。\n${e.message}';
    } on StateError catch (e) {
      error = '$failure\n${e.message}';
    } catch (e) {
      error = '$failure\n$e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> initialize() => _run('资料库加载失败，可重新选择文件夹。', () async {
    await home.create(recursive: true);
    var path = sample.path;
    if (await _preferences.exists()) {
      final saved = jsonDecode(await _preferences.readAsString()) as Map;
      path = saved['builtIn'] == true ? sample.path : saved['path'] as String;
    } else {
      final existing = File(p.join(home.path, 'interop-v1', 'hub-v1.json'));
      if (await existing.exists()) {
        final old = jsonDecode(await existing.readAsString())['root'] as String;
        if (await Directory(old).exists()) path = old;
      }
    }
    await _open(path);
  });

  Future<void> choose(String path) => _run('无法切换资料库。', () async {
    await _open(path);
  });
  Future<void> _open(String path) async {
    final root = Directory(await Directory(path).resolveSymbolicLinks());
    if (catalog != null && p.equals(root.path, catalog!.root.path)) return;
    final privateDir = await home.resolveSymbolicLinks();
    if (p.equals(root.path, privateDir) ||
        p.isWithin(root.path, privateDir) ||
        p.isWithin(privateDir, root.path)) {
      throw StateError('共享文件夹必须与 NamiHub 的私有数据目录分开。');
    }
    final key = sha256
        .convert(utf8.encode(p.canonicalize(root.path)))
        .toString();
    var state = Directory(p.join(home.path, 'libraries', key));
    final legacy = File(p.join(home.path, 'interop-v1', 'hub-v1.json'));
    if (await legacy.exists()) {
      // A damaged legacy file must not prevent choosing a separate library.
      // Leave the legacy file in place for recovery.
      try {
        final data = jsonDecode(await legacy.readAsString());
        if (data is Map &&
            data['root'] is String &&
            p.equals(data['root'] as String, root.path)) {
          state = legacy.parent;
        }
      } on FormatException {
        // Use the selected directory's own state.
      }
    }
    await state.create(recursive: true);
    final handle = await File(
      p.join(state.path, 'hub.lock'),
    ).open(mode: FileMode.append);
    try {
      try {
        await handle.lock(FileLock.exclusive);
      } on FileSystemException {
        throw StateError('该资料库由另一个 NamiHub 实例使用。关闭该实例后重试。');
      }
      final next = await Catalog.open(root, state);
      await next.scan();
      final temp = File('${_preferences.path}.$pid.next');
      await temp.writeAsString(
        jsonEncode({
          'path': root.path,
          'builtIn': p.equals(root.path, sample.path),
        }),
        flush: true,
      );
      await temp.rename(_preferences.path);
      if (online) await _stopSharing();
      await _lock?.close();
      _lock = handle;
      catalog = next;
      index = LibraryIndex(next.resources.values);
    } catch (_) {
      await handle.close();
      rethrow;
    }
  }

  Future<void> refresh() => _run('重新索引失败，已保留上次索引。', () async {
    final current = catalog;
    if (current == null) return;
    await current.scan();
    index = LibraryIndex(current.resources.values);
  });
  Future<void> start() => _run('共享启动失败。', () async {
    final c = catalog;
    if (c == null || online) return;
    final state = c.state.parent;
    if (!await File(p.join(state.path, 'tls.pem')).exists()) {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        p.join(assets.path, 'init_tls.ps1'),
        '-StateDirectory',
        state.path,
      ]);
      if (result.exitCode != 0) throw StateError('无法创建本机 TLS 证书。');
    }
    transport = await HubTransport.listen(
      c,
      state,
      '0.0.0.0',
      port,
      onDevicesChanged: notifyListeners,
    );
    await _tray(true);
  });
  Future<void> stop() => _run('未能停止共享。', _stopSharing);
  Future<void> _stopSharing() async {
    await transport?.close();
    transport = null;
    await _tray(false);
  }

  void newCode() {
    transport?.hub.createCode();
    notifyListeners();
  }

  void revoke(String id) {
    if (catalog == null) return;
    try {
      (transport?.hub ?? HubService(catalog!)).revoke(id);
    } catch (e) {
      error = '撤销授权失败。\n$e';
    }
    notifyListeners();
  }

  Future<void> release() async {
    await transport?.close();
    if (trayActive) await _tray(false);
    await _lock?.close();
  }
}
