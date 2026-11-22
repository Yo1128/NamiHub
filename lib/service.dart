import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:nami_hub_client/pair_protocol.dart';

import 'catalog.dart';

class ApiError implements Exception {
  const ApiError(this.status, this.code);
  final int status;
  final String code;
}

class HubService {
  HubService(
    this.catalog, {
    this.fingerprint = '',
    this.onRead,
    this.onDevicesChanged,
  });
  final String fingerprint;
  final Catalog catalog;
  final void Function(Map<String, dynamic>)? onRead;
  final void Function()? onDevicesChanged;
  String? _code;
  DateTime _deadline = DateTime.now();
  int _attempts = 0;
  String _invitation = '';
  int _hint = 0;
  final _tickets =
      <String, ({HostProof proof, String name, DateTime expires})>{};
  final _starts = <DateTime>[];
  Map<String, dynamic> get discoveryWindow =>
      activeCode == null ? {} : {'invite': _invitation, 'hint': _hint};
  final _active = <String, Set<HttpResponse>>{};
  String? get activeCode =>
      _deadline.isAfter(DateTime.now()) && _attempts > 0 ? _code : null;
  DateTime get codeDeadline => _deadline;

  String createCode() {
    _attempts = 5;
    _deadline = DateTime.now().add(const Duration(minutes: 5));
    _tickets.clear();
    _starts.clear();
    _invitation = pairingNonce();
    final code = Random.secure().nextInt(100000000).toString().padLeft(8, '0');
    _hint = routingHint(_invitation, code);
    return _code = code;
  }

  bool revoke(String deviceId) {
    final old = catalog.devices.remove(deviceId);
    if (old == null) return false;
    try {
      catalog.save();
    } catch (_) {
      catalog.devices[deviceId] = old;
      rethrow;
    }
    for (final response in _active.remove(deviceId) ?? <HttpResponse>{}) {
      unawaited(
        response
            .detachSocket(writeHeaders: false)
            .then<void>((socket) => socket.destroy())
            .catchError((_) {}),
      );
    }
    onDevicesChanged?.call();
    return true;
  }

  String _authenticate(HttpRequest req) {
    final header = req.headers.value('authorization') ?? '';
    if (header.length > 128 || !header.startsWith('Bearer '))
      throw const ApiError(401, 'unauthorized');
    final hash = tokenHash(header.substring(7));
    for (final entry in catalog.devices.entries) {
      if (entry.value['hash'] == hash) return entry.key;
    }
    throw const ApiError(401, 'unauthorized');
  }

  Future<Map> _body(HttpRequest req) async {
    if (req.headers.contentType?.mimeType != 'application/json')
      throw const ApiError(415, 'expected_json');
    final bytes = <int>[];
    await for (final chunk in req.timeout(const Duration(seconds: 10))) {
      if (bytes.length + chunk.length > 2048)
        throw const ApiError(413, 'body_too_large');
      bytes.addAll(chunk);
    }
    final body = jsonDecode(utf8.decode(bytes));
    if (body is! Map) throw const ApiError(400, 'invalid_pair_request');
    return body;
  }

  String _name(Map body) {
    if (body['clientName'] is! String)
      throw const ApiError(400, 'invalid_pair_request');
    final name = (body['clientName'] as String).trim();
    if (name.isEmpty ||
        name.length > 80 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name))
      throw const ApiError(400, 'invalid_client_name');
    return name;
  }

  Never _wrongCode() {
    _attempts--;
    if (_attempts <= 0) _tickets.clear();
    throw const ApiError(403, 'invalid_pair_code');
  }

  Future<void> _pair(HttpRequest req, String step) async {
    final body = await _body(req);
    final code = activeCode;
    if (code == null) throw const ApiError(403, 'pairing_closed');
    if (step == 'manual') {
      if (body['code'] is! String)
        throw const ApiError(400, 'invalid_pair_request');
      final name = _name(body);
      if (body['code'] != code) _wrongCode();
      _grant(req, name);
      return;
    }
    final now = DateTime.now();
    _tickets.removeWhere((_, t) => !t.expires.isAfter(now));
    if (step == 'begin') {
      final name = _name(body);
      if (body['invite'] != _invitation)
        throw const ApiError(403, 'pairing_closed');
      _starts.removeWhere(
        (t) => !t.isAfter(now.subtract(const Duration(seconds: 30))),
      );
      if (_starts.length >= 12 || _tickets.length >= 8)
        throw const ApiError(429, 'pairing_busy');
      _starts.add(now);
      final proof = HostProof(
        PairContext(catalog.hubId, fingerprint, name, _invitation, code),
        body['A'],
      );
      final ticket = pairingNonce();
      _tickets[ticket] = (
        proof: proof,
        name: name,
        expires: now.add(const Duration(seconds: 30)),
      );
      _json(req, 200, {'ticket': ticket, 'B': proof.challenge});
      return;
    }
    final ticket = _tickets.remove(body['ticket']);
    if (ticket == null) throw const ApiError(403, 'pairing_closed');
    final reply = ticket.proof.confirm(body['M1']);
    if (reply == null) _wrongCode();
    _grant(req, ticket.name, evidence: reply);
  }

  void _grant(HttpRequest req, String name, {String? evidence}) {
    final device = randomId(16), token = randomId(32);
    catalog.devices[device] = {'name': name, 'hash': tokenHash(token)};
    try {
      catalog.save();
    } catch (_) {
      catalog.devices.remove(device);
      rethrow;
    }
    _code = null;
    _tickets.clear();
    onDevicesChanged?.call();
    _json(req, 201, {
      'hubId': catalog.hubId,
      'deviceId': device,
      'accessToken': token,
      if (evidence != null) 'M2': evidence,
    });
  }

  void _json(HttpRequest req, int status, Map<String, dynamic> data) {
    final bytes = utf8.encode(jsonEncode(data));
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..contentLength = bytes.length;
    if (req.method != 'HEAD') req.response.add(bytes);
  }

  Future<void> handle(HttpRequest req) async {
    final res = req.response;
    res.headers.set('Cache-Control', 'no-store');
    try {
      final path = req.uri.pathSegments;
      if (path.length < 2 || path[0] != 'v1')
        throw const ApiError(404, 'not_found');
      if (path.length == 2 && path[1] == 'info' && req.method == 'GET') {
        _json(req, 200, {'apiVersion': 1, 'hubId': catalog.hubId});
      } else if (path.length == 2 &&
          path[1] == 'pair' &&
          req.method == 'POST') {
        await _pair(req, 'manual');
      } else if (path.length == 3 &&
          path[1] == 'pair' &&
          (path[2] == 'begin' || path[2] == 'finish') &&
          req.method == 'POST') {
        await _pair(req, path[2]);
      } else {
        final device = _authenticate(req);
        if (path[1] != 'resources') throw const ApiError(404, 'not_found');
        if (!(req.method == 'GET' || req.method == 'HEAD'))
          throw const ApiError(405, 'method_not_allowed');
        if (path.length == 2 && req.method == 'GET') {
          final query = req.uri.queryParameters;
          final limit = int.tryParse(query['limit'] ?? '50') ?? 0;
          final type = query['type'], cursor = query['cursor'] ?? '';
          if (limit < 1 ||
              limit > 100 ||
              (type != null &&
                  !['book', 'audio', 'video', 'other'].contains(type)))
            throw const ApiError(400, 'invalid_query');
          final page = catalog.page(cursor, limit, type);
          _json(req, 200, {
            'items': page.items.map((r) => r.json).toList(),
            'nextCursor': page.nextCursor,
          });
        } else if (path.length == 3 && req.method == 'GET') {
          _json(req, 200, _find(path[2]).json);
        } else if (path.length == 4 && path[3] == 'content') {
          await _content(req, _find(path[2]), device);
        } else {
          throw const ApiError(404, 'not_found');
        }
      }
    } on ApiError catch (error) {
      _json(req, error.status, {'error': error.code});
    } on FormatException {
      _json(req, 400, {'error': 'invalid_request'});
    } on TimeoutException {
      _json(req, 408, {'error': 'request_timeout'});
    } catch (_) {
      try {
        _json(req, 500, {'error': 'server_error'});
      } catch (_) {}
    } finally {
      try {
        await res.close();
      } catch (_) {
        /* Disconnected client. */
      }
    }
  }

  Resource _find(String id) =>
      catalog.resources[id] ?? (throw const ApiError(404, 'resource_missing'));

  Future<void> _content(
    HttpRequest req,
    Resource resource,
    String device,
  ) async {
    final file = await catalog.safeFile(resource.relative);
    if (file == null) throw const ApiError(404, 'resource_missing');
    final stat = await file.stat();
    if (stat.size != resource.size || stat.modified != resource.modified)
      throw const ApiError(409, 'rescan_required');
    final res = req.response, tag = '"${resource.digest}"';
    res.headers
      ..set('ETag', tag)
      ..set('Accept-Ranges', 'bytes');
    final match = req.headers.value('if-match');
    if (match != null && match != '*' && match != tag)
      throw const ApiError(412, 'version_changed');
    final size = resource.size, range = req.headers.value('range');
    var start = 0, end = size - 1;
    if (range != null) {
      final bounds = _range(range, size);
      if (bounds == null) {
        res.headers.set('Content-Range', 'bytes */$size');
        throw const ApiError(416, 'range_not_satisfiable');
      }
      (start, end) = bounds;
      res
        ..statusCode = 206
        ..headers.set('Content-Range', 'bytes $start-$end/$size');
    }
    if (!catalog.devices.containsKey(device))
      throw const ApiError(401, 'unauthorized');
    res
      ..headers.set('Content-Type', resource.format.$2)
      ..contentLength = end - start + 1;
    onRead?.call({
      'event': 'read',
      'resourceId': resource.id,
      'method': req.method,
      'status': res.statusCode,
      'start': start,
      'end': end,
    });
    if (req.method == 'HEAD' || size == 0) return;
    final active = _active.putIfAbsent(device, () => {});
    active.add(res);
    try {
      await res.addStream(
        file
            .openRead(start, end + 1)
            .takeWhile((_) => catalog.devices.containsKey(device)),
      );
    } finally {
      active.remove(res);
      if (active.isEmpty) _active.remove(device);
    }
  }

  (int, int)? _range(String value, int size) {
    final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(value);
    if (m == null || size == 0) return null;
    final a = m[1]!, b = m[2]!;
    if (a.isEmpty) {
      final n = int.tryParse(b);
      return n == null || n <= 0 ? null : (max(0, size - n), size - 1);
    }
    final start = int.tryParse(a), end = b.isEmpty ? size - 1 : int.tryParse(b);
    return start == null || end == null || start >= size || start > end
        ? null
        : (start, min(end, size - 1));
  }
}
