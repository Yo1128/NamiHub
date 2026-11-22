import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:nami_hub_client/nami_hub_client.dart';

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

Future<void> main(List<String> args) async {
  final origin = Uri.parse(args[0]), cache = Directory(args[2]);
  final wrong = HubClient(origin: origin, certificateSha256: '0' * 64);
  var refused = false;
  try {
    await wrong.info();
  } on HandshakeException {
    refused = true;
  } on HubException {
    refused = true;
  } finally {
    wrong.close();
  }
  check(refused, 'Wrong certificate was accepted');
  final client = HubClient(origin: origin, certificateSha256: args[1]);
  try {
    final code = stdin.readLineSync()!;
    final session = await client.pair(code, 'Dart SDK integration');
    check(
      (await client.info())['hubId'] == session.hubId,
      'Unexpected Hub identity',
    );
    final rows = await client.resources(pageSize: 1).toList();
    final manifest = jsonDecode(await File(args[3]).readAsString()) as Map;
    final expected = {
      for (final item in manifest['items']) item['displayName']: item,
    };
    check(rows.length == expected.length, 'Incomplete pages');
    for (final item in rows) {
      final match = expected[item.name];
      check(
        match != null &&
            item.digest == match['sha256'] &&
            item.size == match['sizeBytes'],
        'Fixture differs: ${item.name}',
      );
      check(
        (await client.resource(item.id)).version == item.version,
        'Item detail differs',
      );
    }
    final books = await client.resources(type: 'book', pageSize: 1).toList();
    check(
      books.length == 2 && books.every((b) => b.type == 'book'),
      'Type filtering',
    );
    final book = books.firstWhere((b) => b.name.endsWith('.txt'));
    final interrupted = HubClient(
      origin: Uri.parse(args[4]),
      certificateSha256: args[1],
      session: const HubSession(
        hubId: 'fixture',
        deviceId: 'test',
        token: 'test-only',
      ),
    );
    try {
      await interrupted.download(book, File('${cache.path}/interrupted-book'));
    } finally {
      interrupted.close();
    }
    await cache.create(recursive: true);
    final dest = File('${cache.path}/book');
    final part = File('${dest.path}.${book.version}.part');
    const prefix = 4096;
    await (await client.read(
      book,
      start: 0,
      end: prefix - 1,
    )).pipe(part.openWrite());
    final restored = HubClient(
      origin: origin,
      certificateSha256: args[1],
      session: session,
    );
    try {
      await restored.download(book, dest);
    } finally {
      restored.close();
    }
    check(
      (await sha256.bind(dest.openRead()).first).toString() == book.digest,
      'Resumed book digest',
    );
    await dest.writeAsString('previous valid edition');
    await part.writeAsBytes(List.filled(book.size, 0));
    try {
      await client.download(book, dest);
      throw StateError('Corruption accepted');
    } on HubException catch (e) {
      check(e.code == 'integrity_failed', 'Unexpected integrity error');
    }
    check(
      await dest.readAsString() == 'previous valid edition' &&
          !await part.exists(),
      'Failed update destroyed the previous edition',
    );
    for (final item in rows) {
      final file = File('${cache.path}/${item.id}');
      await client.download(item, file);
      check(
        (await sha256.bind(file.openRead()).first).toString() == item.digest,
        'Downloaded digest',
      );
    }
    final video = rows.firstWhere((r) => r.type == 'video');
    final playback = client.playbackRequest(video);
    check(
      !playback.uri.hasQuery &&
          playback.headers['If-Match'] == '"${video.version}"' &&
          playback.headers.containsKey('Authorization') &&
          playback.certificateSha256 == args[1],
      'Native playback descriptor',
    );
    stdout.writeln(
      jsonEncode({
        'sdk': 'passed',
        'files': rows.length,
        'deviceId': session.deviceId,
        'resumeOffset': prefix,
      }),
    );
  } finally {
    client.close();
  }
}
