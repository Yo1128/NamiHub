import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nami_hub_client/nami_hub_client.dart';
import 'package:nami_hub_desktop/library_host.dart';
import 'package:nami_hub_desktop/main.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Local library, filtering, authenticated pairing and revocation', (
    tester,
  ) async {
    final home = await Directory.systemTemp.createTemp('namihub-ui-');
    final host = LibraryHost(
      home: home,
      assets: Directory(
        p.join(p.dirname(Platform.resolvedExecutable), 'data', 'hub'),
      ),
      port: 0,
    );
    final surface = GlobalKey();
    Future<void> wait(bool Function() done) async {
      for (var i = 0; i < 160 && !done(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 35));
      }
      expect(done(), isTrue, reason: host.error);
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      final out = Platform.environment['NAMI_HUB_PREVIEW'];
      if (out == null) return;
      final box =
          surface.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await box.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(out).create(recursive: true);
      await File(
        p.join(out, '$name.png'),
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    var frame = 0;
    Future<void> captureMotion(int n) async {
      if (Platform.environment['NAMI_HUB_PREVIEW'] == null) return;
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 28));
        await capture('motion-${(frame++).toString().padLeft(3, '0')}');
      }
    }

    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: surface,
          child: HubApp(host: host),
        ),
      );
      await wait(() => !host.busy && host.catalog != null);
      expect(host.files.length, 5);
      await capture('library');
      await captureMotion(4);
      await tester.tap(find.text('书籍'));
      await captureMotion(9);
      await tester.pumpAndSettle();
      expect(find.text('tide-notes.epub'), findsOneWidget);
      expect(find.text('harbor-seek.mp4'), findsNothing);
      await tester.tap(find.text('tide-notes.epub'));
      await captureMotion(10);
      await tester.pumpAndSettle();
      expect(find.text('文件详情'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await captureMotion(9);
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部'));
      await tester.enterText(find.byType(TextField), 'unmatched');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的文件。'), findsOneWidget);
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始共享'));
      await wait(() => host.online && host.transport!.hub.activeCode != null);
      final t = host.transport!;
      final probe = Platform.environment['NAMI_HUB_TRAY_PROBE'];
      if (probe != null) {
        expect(
          host.trayActive,
          isTrue,
          reason: 'Windows Shell must accept the tray icon',
        );
        final result = await Process.run('python', [
          probe,
          '$pid',
          'https://127.0.0.1:${t.server.port}',
          t.publicCertificate.path,
        ]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
      }
      // Capture a consumed code state or the library, never a valid pairing secret.
      final client = await HubLan.pair(
        t.hub.activeCode!,
        'NamiRead · 联调设备',
        expectedHubId: t.hub.catalog.hubId,
      );
      try {
        expect(client.certificateSha256, t.fingerprint);
        expect((await client.resources(type: 'book').toList()).length, 2);
        await tester.pumpAndSettle();
        expect(find.text('已完成配对'), findsOneWidget);
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('授权设备').first);
        await tester.pumpAndSettle();
        expect(find.text('NamiRead · 联调设备'), findsOneWidget);
        await capture('devices');
        await tester.tap(find.byTooltip('管理设备'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('撤销授权'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('撤销授权').last);
        await tester.pumpAndSettle();
        expect(host.catalog!.devices, isEmpty);
        await expectLater(
          client.resources().toList(),
          throwsA(isA<HubException>().having((e) => e.status, 'status', 401)),
        );
      } finally {
        client.close();
      }
      await tester.tap(find.text('资料库').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('停止共享'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('停止共享').last);
      await wait(() => !host.online);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await host.release();
      await home.delete(recursive: true);
    }
  });
}
