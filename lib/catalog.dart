import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

final _random = Random.secure();
String randomId(int bytes) => base64Url
    .encode(List<int>.generate(bytes, (_) => _random.nextInt(256)))
    .replaceAll('=', '');
String tokenHash(String token) => sha256.convert(utf8.encode(token)).toString();

class Resource {
  Resource(this.id, this.relative, this.size, this.modified, this.digest);
  final String id;
  final String relative;
  final int size;
  final DateTime modified;
  final String digest;

  late final String name = p.basename(relative);
  late final (String, String) format = switch (p
      .extension(name)
      .toLowerCase()) {
    '.txt' => ('book', 'text/plain'),
    '.epub' => ('book', 'application/epub+zip'),
    '.wav' => ('audio', 'audio/wav'),
    '.mp3' => ('audio', 'audio/mpeg'),
    '.flac' => ('audio', 'audio/flac'),
    '.m4a' => ('audio', 'audio/mp4'),
    '.aac' => ('audio', 'audio/aac'),
    '.ogg' => ('audio', 'audio/ogg'),
    '.mp4' || '.m4v' => ('video', 'video/mp4'),
    '.mkv' => ('video', 'video/x-matroska'),
    '.webm' => ('video', 'video/webm'),
    '.mov' => ('video', 'video/quicktime'),
    _ => ('other', 'application/octet-stream'),
  };
  Map<String, dynamic> get json => {
    'resourceId': id,
    'displayName': name,
    'type': format.$1,
    'mimeType': format.$2,
    'sizeBytes': size,
    'contentVersion': digest,
    'sha256': digest,
  };
}

typedef _Scan = ({
  Map<String, String> paths,
  Map<String, Resource> files,
  List<Resource> ordered,
});

class Catalog {
  Catalog._(this.root, this.state, this.hubId, this._locations, this.devices);
  final Directory root;
  final File state;
  final String hubId;
  Map<String, String> _locations;
  Map<String, String> get locations => UnmodifiableMapView(_locations);
  final Map<String, dynamic> devices;
  Map<String, Resource> _resources = const {};
  Map<String, Resource> get resources => _resources;
  List<Resource> _byId = [];
  Future<void> _pending = Future.value();

  static Future<Catalog> open(Directory root, Directory stateDir) async {
    final state = File(p.join(stateDir.path, 'hub-v1.json'));
    if (await state.exists()) {
      final data = jsonDecode(await state.readAsString()) as Map;
      if (data['schema'] != 1 || !p.equals(data['root'] as String, root.path)) {
        throw StateError(
          'State belongs to another root or schema. Use a separate state directory.',
        );
      }
      return Catalog._(
        root,
        state,
        data['hubId'],
        Map<String, String>.from(data['locations']),
        Map<String, dynamic>.from(data['devices']),
      );
    }
    final catalog = Catalog._(root, state, randomId(16), {}, {});
    catalog.save();
    return catalog;
  }

  // Synchronous atomic replacement serializes configuration mutations on this isolate.
  void save() => _save(_locations);

  void _save(Map<String, String> paths) {
    final tmp = File('${state.path}.next');
    tmp.writeAsStringSync(
      jsonEncode({
        'schema': 1,
        'root': root.path,
        'hubId': hubId,
        'locations': paths,
        'devices': devices,
      }),
      flush: true,
    );
    tmp.renameSync(state.path);
  }

  Future<File?> safeFile(String relative) => _safeFile(root, relative);

  static Future<File?> _safeFile(Directory root, String relative) async {
    final file = File(p.join(root.path, relative));
    if (!p.isWithin(root.path, file.path)) return null;
    try {
      final resolved = await file.resolveSymbolicLinks();
      if (!p.equals(resolved, file.path) || !p.isWithin(root.path, resolved))
        return null;
      return await FileSystemEntity.type(file.path, followLinks: false) ==
              FileSystemEntityType.file
          ? file
          : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _enqueue(Future<void> Function() change) {
    final result = _pending.then((_) => change());
    _pending = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> scan() => _enqueue(() => _refresh(_locations));

  Future<void> _refresh(Map<String, String> paths) async {
    final rootPath = root.path;
    final result = await Isolate.run(() => _index(rootPath, paths));
    // A plain rescan only adds paths. Missing files keep their IDs for relink.
    if (!identical(paths, _locations) ||
        result.paths.length != _locations.length) {
      _save(result.paths);
    }
    _locations = result.paths;
    _resources = UnmodifiableMapView(result.files);
    _byId = result.ordered;
  }

  static Future<_Scan> _index(
    String rootPath,
    Map<String, String> paths,
  ) async {
    final root = Directory(rootPath);
    final files = <String, Resource>{};
    await for (final item in root.list(recursive: true, followLinks: false)) {
      if (item is! File) continue;
      final relative = p.relative(item.path, from: root.path);
      final file = await _safeFile(root, relative);
      if (file == null) continue;
      final before = await file.stat();
      final digest = (await sha256.bind(file.openRead()).first).toString();
      final after = await file.stat();
      if (before.size != after.size || before.modified != after.modified) {
        throw StateError('File changed during scan: $relative. Retry rescan.');
      }
      final id = paths.putIfAbsent(
        p.canonicalize(p.join(root.path, relative)),
        () => randomId(16),
      );
      files[id] = Resource(id, relative, after.size, after.modified, digest);
    }
    final ordered = files.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return (paths: paths, files: files, ordered: ordered);
  }

  ({List<Resource> items, String? nextCursor}) page(
    String cursor,
    int limit,
    String? type,
  ) {
    var low = 0, high = _byId.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_byId[mid].id.compareTo(cursor) <= 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final page = <Resource>[];
    for (var i = low; i < _byId.length; i++) {
      final resource = _byId[i];
      if (type != null && resource.format.$1 != type) continue;
      if (page.length == limit) return (items: page, nextCursor: page.last.id);
      page.add(resource);
    }
    return (items: page, nextCursor: null);
  }

  Future<void> relink(String id, String relative) => _enqueue(() async {
    if (p.isAbsolute(relative) || await safeFile(relative) == null)
      throw ArgumentError('Expected a regular file within the indexed root.');
    final old = _locations.entries
        .where((entry) => entry.value == id)
        .firstOrNull;
    if (old == null || await File(old.key).exists())
      throw StateError(
        'Old resource must exist in the index and be missing on disk.',
      );
    final key = p.canonicalize(p.join(root.path, relative));
    if (_locations.containsKey(key))
      throw StateError(
        'Target already has an identity. Relink before rescanning.',
      );
    final paths = Map.of(_locations)..remove(old.key);
    paths[key] = id;
    await _refresh(paths);
  });
}
