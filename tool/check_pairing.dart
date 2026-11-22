import 'dart:convert';
import 'dart:io';

import 'package:nami_hub/catalog.dart';
import 'package:nami_hub/transport.dart';
import 'package:nami_hub_client/nami_hub_client.dart';
import 'package:nami_hub_client/pair_protocol.dart';
import 'package:path/path.dart' as p;

void check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

Future<void> rejects(String code, Future<dynamic> Function() action) async {
  try {
    await action();
  } on HubException catch (e) {
    if (e.code == code) return;
    rethrow;
  }
  throw StateError('Expected $code');
}

// Two independent HTTPS services on loopback. A unicast UDP fixture returns
// both announcements on a single NIC, as two computers on a LAN would.
Future<void> main(List<String> args) async {
  final temp = await Directory.systemTemp.createTemp('nami-pair-');
  final hosts = <HubTransport>[];
  RawDatagramSocket? udp;
  try {
    for (var i = 0; i < 2; i++) {
      final root = await Directory(p.join(temp.path, 'books-$i')).create();
      final state = await Directory(p.join(temp.path, 'state-$i')).create();
      await File(p.join(root.path, '$i.txt')).writeAsString('book $i');
      final init = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        'tool/init_tls.ps1',
        '-StateDirectory',
        state.path,
      ]);
      check(init.exitCode == 0, 'Test TLS setup');
      final c = await Catalog.open(root, state);
      await c.scan();
      hosts.add(await HubTransport.listen(c, state, '127.0.0.1', 0));
    }
    var advertise = true, changedPin = false;
    final socket = udp = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      discoveryPort,
    );
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = socket.receive();
      if (packet == null || !advertise) return;
      final request = String.fromCharCodes(packet.data);
      if (!request.startsWith(discoveryPrefix)) return;
      final nonce = request.substring(discoveryPrefix.length);
      if (!validNonce(nonce)) return;
      for (final h in hosts) {
        socket.send(
          utf8.encode(
            jsonEncode({
              'protocol': 'NamiHub/1',
              'nonce': nonce,
              'hubId': h.hub.catalog.hubId,
              'port': h.server.port,
              'pin': changedPin ? '0' * 64 : h.fingerprint,
              ...h.hub.discoveryWindow,
            }),
          ),
          packet.address,
          packet.port,
        );
      }
    });
    final a = hosts[0].hub, b = hosts[1].hub;
    var code = a.createCode();
    while (!code.startsWith('0')) {
      code = a.createCode();
    }
    bool matchesB() =>
        routingHint(b.discoveryWindow['invite'], code) ==
        b.discoveryWindow['hint'];
    b.createCode();
    while (!matchesB()) {
      b.createCode();
    }
    await rejects(
      'ambiguous_pair_code',
      () => HubLan.pair(code, 'Test reader'),
    );
    check(
      a.catalog.devices.isEmpty && b.catalog.devices.isEmpty,
      'Collision registered a device',
    );
    while (matchesB()) {
      b.createCode();
    }
    final client = await HubLan.pair(code, 'Test reader');
    final session = client.session!;
    try {
      check(
        a.activeCode == null &&
            b.activeCode != null &&
            b.catalog.devices.isEmpty,
        'Other invite consumed',
      );
      check(
        (await client.resources(type: 'book').single).name == '0.txt',
        'Wrong book list',
      );
      await rejects(
        'invalid_or_expired_code',
        () => HubLan.pair(code, 'Replay', expectedHubId: session.hubId),
      );
      final gone = Uri.parse('https://127.0.0.1:1');
      final restored = await HubLan.restore(
        gone,
        hosts[0].fingerprint,
        session,
      );
      try {
        check(
          (await restored.resources(type: 'book').single).name == '0.txt',
          'Rediscovery failed',
        );
        a.revoke(session.deviceId);
        await rejects('unauthorized', () => restored.resources().toList());
      } finally {
        restored.close();
      }
      changedPin = true;
      await rejects(
        'certificate_mismatch',
        () => HubLan.restore(gone, hosts[0].fingerprint, session),
      );
      changedPin = false;
      final inviteCode = a.createCode();
      final invite = a.discoveryWindow;
      var wrong = '00000000';
      for (
        var n = 0;
        wrong == inviteCode ||
            routingHint(invite['invite'], wrong) != invite['hint'];
        n++
      ) {
        wrong = n.toString().padLeft(8, '0');
      }
      for (var i = 0; i < 4; i++) {
        await rejects('invalid_pair_code', () => client.pair(wrong, 'manual'));
      }
      await rejects(
        'invalid_pair_code',
        () => HubLan.pair(wrong, 'SRP', expectedHubId: session.hubId),
      );
      check(
        a.activeCode == null && b.activeCode != null,
        'Shared attempt budget',
      );
      advertise = false;
      await rejects('discovery_empty', () => HubLan.pair(code, 'Test reader'));
    } finally {
      client.close();
    }
    stdout.writeln(
      'Passed: leading zero, two hosts, ambiguity, one-time pairing, books, rediscovery, pin change, revocation, shared attempt limit, empty discovery.',
    );
  } finally {
    udp?.close();
    for (final h in hosts) {
      await h.close();
    }
    await temp.delete(recursive: true);
  }
}
