import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:nami_hub_client/pair_protocol.dart';

import 'catalog.dart';
import 'service.dart';

class HubTransport {
  HubTransport._(
    this.server,
    this.hub,
    this.fingerprint,
    this.publicCertificate,
    this.urls,
    this._discovery,
  );

  final HttpServer server;
  final HubService hub;
  final String fingerprint;
  final File publicCertificate;
  final List<String> urls;
  final RawDatagramSocket? _discovery;
  bool get discoverable => _discovery != null;

  static Future<HubTransport> listen(
    Catalog catalog,
    Directory state,
    String bind,
    int port, {
    void Function(Map<String, dynamic>)? onRead,
    void Function()? onDevicesChanged,
  }) async {
    final pem = File(p.join(state.path, 'tls.pem'));
    final certificate = RegExp(
      r'-----BEGIN CERTIFICATE-----([\s\S]+?)-----END CERTIFICATE-----',
    ).firstMatch(await pem.readAsString());
    if (certificate == null)
      throw const FormatException('Missing TLS certificate');
    final publicCert = File(p.join(state.path, 'hub-public.pem'));
    await publicCert.writeAsString('${certificate[0]}\n', flush: true);
    final pin = sha256
        .convert(base64.decode(certificate[1]!.replaceAll(RegExp(r'\s'), '')))
        .toString();
    final context = SecurityContext()
      ..useCertificateChain(pem.path)
      ..usePrivateKey(pem.path);
    final hub = HubService(
      catalog,
      fingerprint: pin,
      onRead: onRead,
      onDevicesChanged: onDevicesChanged,
    );
    final server = await HttpServer.bindSecure(bind, port, context);
    try {
      final addresses =
          server.address == InternetAddress.anyIPv4 ||
              server.address == InternetAddress.anyIPv6
          ? (await NetworkInterface.list(
              type: InternetAddressType.IPv4,
              includeLoopback: true,
            )).expand((n) => n.addresses).toList()
          : [server.address];
      final urls = addresses
          .map(
            (a) => Uri(
              scheme: 'https',
              host: a.address,
              port: server.port,
            ).toString(),
          )
          .toList();
      server.idleTimeout = const Duration(seconds: 30);
      server.listen(
        hub.handle,
        onError: (Object _) {
          /* A failed TLS handshake affects only this connection. */
        },
      );
      RawDatagramSocket? discovery;
      if (!server.address.isLoopback &&
          server.address.type == InternetAddressType.IPv4) {
        try {
          discovery = await _advertise(hub, server.address, server.port);
        } on SocketException {
          // Discovery is optional. Pinned manual HTTPS still works on this port.
        }
      }
      return HubTransport._(server, hub, pin, publicCert, urls, discovery);
    } catch (_) {
      await server.close(force: true);
      rethrow;
    }
  }

  Future<void> close() async {
    _discovery?.close();
    await server.close(force: true);
  }

  static Future<RawDatagramSocket> _advertise(
    HubService hub,
    InternetAddress bind,
    int port,
  ) async {
    final socket = await RawDatagramSocket.bind(bind, discoveryPort);
    final timer = Stopwatch()..start();
    var answers = 0;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = socket.receive();
      if (packet == null || packet.data.length != discoveryPrefix.length + 22)
        return;
      final request = String.fromCharCodes(packet.data);
      if (!request.startsWith(discoveryPrefix)) return;
      final nonce = request.substring(discoveryPrefix.length);
      if (!validNonce(nonce)) return;
      if (timer.elapsedMilliseconds >= 1000) {
        timer.reset();
        answers = 0;
      }
      if (++answers > 48) return;
      final response = utf8.encode(
        jsonEncode({
          'protocol': 'NamiHub/1',
          'nonce': nonce,
          'hubId': hub.catalog.hubId,
          'pin': hub.fingerprint,
          'port': port,
          ...hub.discoveryWindow,
        }),
      );
      try {
        socket.send(response, packet.address, packet.port);
      } on SocketException {
        /* Peer left. */
      }
    }, onError: (Object _) {});
    return socket;
  }
}
