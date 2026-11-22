import 'dart:io';

import 'package:nami_hub/catalog.dart';
import 'package:path/path.dart' as p;

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

List<String> collect(Catalog catalog, {String? type, required int limit}) {
  final ids = <String>[];
  var cursor = '';
  while (true) {
    final page = catalog.page(cursor, limit, type);
    ids.addAll(page.items.map((r) => r.id));
    if (page.nextCursor == null) return ids;
    check(
      page.items.length == limit &&
          page.nextCursor == ids.last &&
          ids.last.compareTo(cursor) > 0,
      'Unexpected page boundary',
    );
    cursor = ids.last;
  }
}

Future<void> main() async {
  final temp = await Directory.systemTemp.createTemp('nami-catalog-');
  try {
    final root = await Directory(p.join(temp.path, 'share')).create();
    final state = await Directory(p.join(temp.path, 'state')).create();
    for (final name in ['notes.txt', 'second.epub', 'clip.mp4', 'other.bin']) {
      await File(p.join(root.path, name)).writeAsString('abc');
    }
    final book = File(p.join(root.path, 'notes.txt'));
    final stamp = DateTime.utc(2025, 1, 1);
    await book.setLastModified(stamp);
    final catalog = await Catalog.open(root, state);
    await Future.wait([catalog.scan(), catalog.scan()]);
    for (final type in [null, 'book', 'video', 'other', 'audio']) {
      final expected =
          catalog.resources.values
              .where((r) => type == null || r.format.$1 == type)
              .map((r) => r.id)
              .toList()
            ..sort();
      for (final limit in [1, 2, 4, 100]) {
        check(
          collect(catalog, type: type, limit: limit).join(',') ==
              expected.join(','),
          'Incomplete or unordered pages',
        );
      }
    }

    final original = catalog.resources.values.singleWhere(
      (r) => r.name == 'notes.txt',
    );
    await catalog.state.setLastModified(stamp);
    await book.writeAsString('xyz');
    await book.setLastModified(stamp);
    await catalog.scan();
    check(
      catalog.resources[original.id]!.digest != original.digest,
      'Equal-size edit with preserved file time was missed',
    );
    check(
      (await catalog.state.lastModified()).isAtSameMomentAs(stamp),
      'A rescan with unchanged identities rewrote the state file',
    );

    final renamed = await book.rename(p.join(root.path, 'renamed.txt'));
    final blocked = await Directory('${catalog.state.path}.next').create();
    var failed = false;
    try {
      await catalog.relink(original.id, 'renamed.txt');
    } on FileSystemException {
      failed = true;
    }
    check(
      failed && catalog.resources[original.id]!.name == 'notes.txt',
      'Failed relink changed the published snapshot',
    );
    await blocked.delete();
    await Future.wait([
      catalog.relink(original.id, 'renamed.txt'),
      catalog.scan(),
    ]);
    final reopened = await Catalog.open(root, state);
    await reopened.scan();
    check(
      reopened.resources[original.id]!.name == 'renamed.txt',
      'Relink lost the resource identity after restart',
    );
    await renamed.delete();
    await reopened.scan();
    check(
      !collect(reopened, limit: 1).contains(original.id),
      'Deleted resource still appears in paginated results',
    );
    stdout.writeln(
      'Catalog paging, exact versions, atomic updates and restart passed.',
    );
  } finally {
    await temp.delete(recursive: true);
  }
}
