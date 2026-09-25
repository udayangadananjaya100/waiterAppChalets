import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oruthota_waiter/main.dart';
import 'package:oruthota_waiter/state/app_controller.dart';
import 'package:oruthota_waiter/ui/home_screen.dart';

Future<void> loadFonts() async {
  for (final name in ['Manrope', 'Lora']) {
    final loader = FontLoader(name)
      ..addFont(rootBundle.load('assets/fonts/$name.ttf'));
    await loader.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);
  Future<AppController> start(WidgetTester tester,
      {bool practice = true, double width = 390, double scale = 1}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({'guide_seen': true});
    final app =
        AppController(preferences: await SharedPreferences.getInstance());
    if (practice) await app.practice();
    app.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pumpWidget(WaiterApp(controller: app));
    await tester.pumpAndSettle();
    addTearDown(app.dispose);
    return app;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (const bool.fromEnvironment('SCREENSHOTS')) {
      await expectLater(
          find.byType(MaterialApp), matchesGoldenFile('screenshots/$name.png'));
    }
  }

  testWidgets('Login and setup render without overflow on a small phone',
      (tester) async {
    await start(tester, practice: false, width: 360);
    expect(find.text('Welcome to your shift.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, '01-sign-in');
    await tester.tap(find.byTooltip('Connection settings'));
    await tester.pumpAndSettle();
    expect(find.text('Connect your restaurant'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Full practice flow: table → draft → sent order → cashier → confirmed bill',
      (tester) async {
    final app = await start(tester);
    await capture(tester, '02-tables');
    await tester.ensureVisible(find.byType(TableCard).first);
    await tester.tap(find.byType(TableCard).first);
    await tester.pumpAndSettle();
    expect(find.text('Table 01'), findsOneWidget);
    await capture(tester, '03-menu');
    await tester.tap(find.byTooltip('Add Sri Lankan rice & curry'));
    await tester.pumpAndSettle();
    expect(app.cartCount('t1'), 1);
    await tester.tap(find.text('Review draft'));
    await tester.pumpAndSettle();
    await capture(tester, '04-review-draft');
    await tester.tap(find.text('Send order to restaurant'));
    await tester.pumpAndSettle();
    expect(app.cartCount('t1'), 0);
    expect(app.snapshot.orderFor('t1')?.total, 1850);
    expect(tester.takeException(), isNull);
    await capture(tester, '05-live-order');
    await tester.tap(find.text('Send bill to cashier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send bill'));
    await tester.pumpAndSettle();
    expect(app.snapshot.orderFor('t1')?.billed, isTrue);
    expect(find.text('The bill is ready.'), findsOneWidget);
    await tester.tap(find.textContaining('View bill •'));
    await tester.pumpAndSettle();
    expect(find.text('Total confirmed by cashier'), findsOneWidget);
    await capture(tester, '06-guest-bill');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Other waiters’ tables are read-only and large text remains usable',
      (tester) async {
    await start(tester, width: 360, scale: 1.3);
    expect(tester.takeException(), isNull);
    await tester.drag(
        find.byType(CustomScrollView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('03'), findsOneWidget);
    await tester.tap(find.text('03'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nimal Silva is serving'), findsOneWidget);
    expect(find.text('Send bill to cashier'), findsNothing);
    expect(find.text('Mark served'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
