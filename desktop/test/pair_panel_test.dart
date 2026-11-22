import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami_hub/catalog.dart';
import 'package:nami_hub/service.dart';
import 'package:nami_hub/transport.dart';
import 'package:nami_hub_desktop/library_host.dart';
import 'package:nami_hub_desktop/panels.dart';

class _Invitation extends Fake implements HubService {
  @override
  String? activeCode = '00112233';
  @override
  DateTime codeDeadline = DateTime.now().add(const Duration(minutes: 5));
}

class _LocalNetwork extends Fake implements HubTransport {
  _LocalNetwork(this.hub);
  @override
  final _Invitation hub;
  @override
  bool get discoverable => true;
  @override
  List<String> get urls => ['https://127.0.0.1:8443', 'https://192.0.2.1:8443'];
  @override
  String get fingerprint => '0' * 64;
}

class _Catalog extends Fake implements Catalog {
  @override
  Map<String, dynamic> get devices => {};
}

void main() {
  testWidgets(
    'pair sheet keeps fallback details optional and hides an invalidated invitation',
    (tester) async {
      final code = _Invitation();
      final host =
          LibraryHost(home: Directory.systemTemp, assets: Directory.systemTemp)
            ..catalog = _Catalog()
            ..transport = _LocalNetwork(code);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => pairPanel(context, host),
                child: const Text('配对'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('配对'));
      await tester.pumpAndSettle();
      expect(find.text('0011 2233'), findsOneWidget);
      expect(find.text('连接地址'), findsNothing);
      await tester.tap(find.text('手动连接'));
      await tester.pumpAndSettle();
      expect(find.text('https://192.0.2.1:8443'), findsOneWidget);
      code.activeCode = null;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('配对码已失效'), findsOneWidget);
      expect(find.text('0011 2233'), findsNothing);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );
}
