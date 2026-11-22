import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nami_hub/catalog.dart';
import 'package:nami_hub/transport.dart';
import 'package:nami_hub_desktop/library_host.dart';
import 'package:nami_hub_desktop/library_index.dart';
import 'package:path/path.dart' as p;

Resource file(String name, int size) =>
    Resource(name, name, size, DateTime.utc(2026), 'a' * 64);

class _Transport extends Fake implements HubTransport {
  bool closed = false;
  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  test(
    'stable sorted snapshots distinguish duplicate names and reuse filtered results',
    () {
      final a = file(p.join('A', '音轨.mp3'), 10);
      final b = file(p.join('B', '音轨.mp3'), 20);
      final notes = file('Notes.EPUB', 5);
      final index = LibraryIndex([b, notes, a]);
      expect(index.files, [notes, a, b]);
      expect(index.count('audio'), 2);
      expect(index.count('book'), 1);
      expect(index.totalBytes, 35);
      expect(index.ambiguousName(a), isTrue);
      expect(index.ambiguousName(notes), isFalse);
      expect(index.filter('all', ''), same(index.files));
      final authors = index.filter('book', ' NOT ');
      expect(authors, [notes]);
      expect(index.filter('book', 'not'), same(authors));
      expect(index.filter('video', 'not'), isEmpty);
    },
  );

  test(
    'same or unavailable folder keeps the active share; refresh replaces the listing',
    () async {
      final temp = await Directory.systemTemp.createTemp('namihub-switch-');
      final root = await Directory(p.join(temp.path, 'Library')).create();
      final home = await Directory(p.join(temp.path, 'State')).create();
      final host = LibraryHost(home: home, assets: temp);
      addTearDown(() async {
        await host.release();
        await temp.delete(recursive: true);
      });
      final legacy = File(p.join(home.path, 'interop-v1', 'hub-v1.json'));
      await legacy.parent.create();
      await legacy.writeAsString('{');
      await host.choose(root.path);
      expect(host.error, isNull);
      expect(await legacy.readAsString(), '{');
      final initial = host.index;
      final transport = _Transport();
      host.transport = transport;
      await host.choose(root.path);
      expect(host.index, same(initial));
      expect(transport.closed, isFalse);
      await host.choose(p.join(temp.path, 'missing'));
      expect(host.error, isNotNull);
      expect(host.transport, same(transport));
      expect(transport.closed, isFalse);
      expect(host.index, same(initial));
      await File(p.join(root.path, '新书.txt')).writeAsString('chapter');
      await host.refresh();
      expect(initial.files, isEmpty);
      expect(host.index, isNot(same(initial)));
      expect(host.index.count('book'), 1);
      expect(host.error, isNull);
    },
  );
}
