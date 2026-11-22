import 'dart:io';

import 'package:nami_hub_client/nami_hub_client.dart';

/// Run with the service's origin and certificate SHA-256 as arguments.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('Usage: connect <https-origin> <certificate-sha256>');
    exitCode = 64;
    return;
  }
  final client = HubClient(
    origin: Uri.parse(args[0]),
    certificateSha256: args[1],
  );
  try {
    stdout.write('Pair code from the Hub window: ');
    final code = stdin.readLineSync();
    if (code == null) throw StateError('Missing pair code');
    final session = await client.pair(code.trim(), 'Nami SDK example');
    stdout.writeln('Paired with ${session.hubId} as ${session.deviceId}');
    await for (final item in client.resources()) {
      stdout.writeln(
        '${item.type}\t${item.name}\t${item.size} bytes\t${item.id}',
      );
    }
  } finally {
    client.close();
  }
}
