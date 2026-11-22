import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami_hub_desktop/library_host.dart';
import 'package:nami_hub_desktop/main.dart';

class _PreparedHost extends LibraryHost {
  _PreparedHost({required super.home, required super.assets});
  @override
  Future<void> initialize() async {}
}

void main() {
  testWidgets(
    'Narrow library, enlarged text and reduced motion keep navigation reachable',
    (t) async {
      final temp = Directory.systemTemp.createTempSync('namihub-layout-');
      final media = Directory('${temp.path}/media')..createSync();
      File('${media.path}/灯塔手记.txt').writeAsStringSync('潮汐');
      final home = Directory('${temp.path}/state')..createSync();
      final host = _PreparedHost(home: home, assets: temp);
      await t.runAsync(() => host.choose(media.path));
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 720);
      t.platformDispatcher.textScaleFactorTestValue = 1.5;
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
        t.platformDispatcher.clearTextScaleFactorTestValue();
        t.platformDispatcher.clearAccessibilityFeaturesTestValue();
      });
      try {
        await t.pumpWidget(HubApp(host: host));
        await t.pumpAndSettle();
        expect(find.text('示例资料库'), findsOneWidget);
        expect(find.text('开始共享'), findsOneWidget);
        await t.tap(find.byTooltip('授权设备'));
        await t.pump();
        expect(find.text('还没有已授权设备'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.tap(find.byTooltip('资料库'));
        await t.pump();
        expect(find.text('示例资料库'), findsOneWidget);
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        await t.runAsync(host.release);
        temp.deleteSync(recursive: true);
      }
    },
  );
}
