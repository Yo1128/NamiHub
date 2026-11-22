import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:nami_hub/catalog.dart';
import 'package:nami_hub/transport.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('root', help: 'Directory of files to share (read only).')
    ..addOption(
      'state',
      help: 'Private directory containing tls.pem and service state.',
    )
    ..addOption('bind', defaultsTo: '127.0.0.1')
    ..addOption('port', defaultsTo: '8443')
    ..addFlag(
      'operator-pipe',
      negatable: false,
      help: 'Expose the one-time code on a private automation pipe.',
    )
    ..addFlag(
      'trace-reads',
      negatable: false,
      help: 'Print resource IDs and byte ranges without credentials.',
    )
    ..addFlag('help', negatable: false);
  try {
    final options = parser.parse(args);
    if (options.flag('help')) {
      stdout.writeln(parser.usage);
      return;
    }
    final rootPath = options.option('root'),
        statePath = options.option('state');
    if (rootPath == null || statePath == null)
      throw FormatException(parser.usage);
    final root = Directory(await Directory(rootPath).resolveSymbolicLinks());
    final state = Directory(await Directory(statePath).resolveSymbolicLinks());
    if (p.equals(root.path, state.path) ||
        p.isWithin(root.path, state.path) ||
        p.isWithin(state.path, root.path)) {
      throw ArgumentError(
        'Use separate, non-overlapping share and state directories.',
      );
    }
    final lock = await File(
      p.join(state.path, 'hub.lock'),
    ).open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
      await serve(
        root,
        state,
        options.option('bind')!,
        int.parse(options.option('port')!),
        options.flag('trace-reads'),
        stdout.hasTerminal || options.flag('operator-pipe'),
      );
    } finally {
      await lock.close();
    }
  } catch (e) {
    stderr.writeln('NamiHub: $e');
    exitCode = 1;
  }
}

void event(Map<String, dynamic> value) => stdout.writeln(jsonEncode(value));

Future<void> serve(
  Directory root,
  Directory state,
  String bind,
  int port,
  bool traceReads,
  bool showCode,
) async {
  final catalog = await Catalog.open(root, state);
  await catalog.scan();
  final transport = await HubTransport.listen(
    catalog,
    state,
    bind,
    port,
    onRead: traceReads ? event : null,
  );
  final hub = transport.hub;
  event({
    'event': 'ready',
    'hubId': catalog.hubId,
    'port': transport.server.port,
    'certificateSha256': transport.fingerprint,
    'publicCertificatePath': transport.publicCertificate.path,
    'urls': transport.urls,
    'discovery': transport.discoverable,
    'resources': catalog.resources.length,
  });
  void newCode() {
    final code = hub.createCode();
    event({
      'event': 'pairCode',
      if (showCode) 'code': code,
      'expiresInSeconds': 300,
    });
  }

  newCode();
  stdout.writeln(
    'Commands: pair | devices | revoke DEVICE_ID | rescan | relink RESOURCE_ID relative/path | quit',
  );
  try {
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      final input = line.trim();
      if (input == 'quit') break;
      try {
        if (input == 'pair') {
          newCode();
        } else if (input == 'devices') {
          event({
            'event': 'devices',
            'devices': catalog.devices.entries
                .map((e) => {'deviceId': e.key, 'clientName': e.value['name']})
                .toList(),
          });
        } else if (input.startsWith('revoke ')) {
          event({
            'event': 'revoked',
            'found': hub.revoke(input.substring(7).trim()),
          });
        } else if (input == 'rescan') {
          await catalog.scan();
          event({'event': 'scanned', 'resources': catalog.resources.length});
        } else if (input.startsWith('relink ')) {
          final m = RegExp(r'^relink\s+(\S+)\s+(.+)$').firstMatch(input);
          if (m == null)
            throw FormatException('relink RESOURCE_ID relative/path');
          await catalog.relink(m[1]!, m[2]!);
          event({'event': 'relinked', 'resourceId': m[1]});
        } else {
          stderr.writeln('Unknown command.');
        }
      } catch (e) {
        stderr.writeln('Command failed: $e');
      }
    }
  } finally {
    await transport.close();
  }
}
