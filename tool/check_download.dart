import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:nami_hub_client/nami_hub_client.dart';
import 'package:path/path.dart' as p;

class LocalClient extends HubClient {
  LocalClient()
    : super(origin: Uri.https('localhost'), certificateSha256: '0' * 64);
  int requests = 0;
  bool interrupt = true;
  final interrupted = Completer<void>();

  @override
  Future<Stream<List<int>>> read(
    HubResource item, {
    int? start,
    int? end,
  }) async {
    requests++;
    if (interrupt) {
      interrupt = false;
      interrupted.complete();
      throw const SocketException('Temporary disconnect');
    }
    return Stream.value(item.size == 0 ? [] : [1, 2, 3]);
  }
}

HubResource item(List<int> bytes) {
  final digest = sha256.convert(bytes).toString();
  return HubResource.fromJson({
    'resourceId': 'sample',
    'displayName': 'sample.txt',
    'type': 'book',
    'mimeType': 'text/plain',
    'sizeBytes': bytes.length,
    'contentVersion': digest,
    'sha256': digest,
  });
}

Future<void> main() async {
  final temp = await Directory.systemTemp.createTemp('nami-download-');
  final client = LocalClient();
  try {
    final book = item([1, 2, 3]);
    final target = File(p.join(temp.path, 'book.txt'));
    final first = client.download(book, target);
    await client.interrupted.future;
    await Future<void>.delayed(const Duration(milliseconds: 90));
    try {
      await client.download(item([]), target);
      throw StateError('A second version took ownership during retry');
    } on HubException catch (error) {
      if (error.code != 'download_busy') rethrow;
    }
    await first;
    if ((await target.readAsBytes()).length != 3 || client.requests != 2) {
      throw StateError('The original transfer did not recover');
    }

    final empty = item([]);
    final other = File(p.join(temp.path, 'empty.txt'));
    final partial = File('${other.path}.${empty.version}.part');
    final blocker = await Directory(partial.path).create();
    try {
      await client.download(empty, other);
      throw StateError('A directory was treated as a partial file');
    } on FileSystemException {
      if (client.requests != 2)
        throw StateError('HTTP read started without a writable file');
    }
    await blocker.delete();
    await partial.create();
    await client.download(empty, other);
    if (!await other.exists() ||
        await other.length() != 0 ||
        client.requests != 3) {
      throw StateError('Empty file was published without checking its source');
    }
    stdout.writeln(
      'Download retry ownership, unwritable destinations and empty files passed.',
    );
  } finally {
    client.close();
    await temp.delete(recursive: true);
  }
}
