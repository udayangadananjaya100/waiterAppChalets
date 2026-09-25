import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'state/app_controller.dart';
import 'ui/auth_screen.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark));
  final preferences = await SharedPreferences.getInstance();
  final controller = AppController(preferences: preferences);
  runApp(WaiterApp(controller: controller));
  await controller.initialize();
}

class WaiterApp extends StatelessWidget {
  final AppController controller;
  const WaiterApp({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
            key: ValueKey(controller.user?.id ?? 'signed-out'),
            title: 'Oruthota Service',
            debugShowCheckedModeBanner: false,
            theme: serviceTheme(),
            home: controller.user != null
                ? HomeScreen(controller: controller)
                : controller.loading
                    ? const Scaffold(
                        body: Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                            BrandMark(size: 66),
                            SizedBox(height: 24),
                            Text('Getting your shift ready…'),
                            SizedBox(height: 20),
                            CircularProgressIndicator(strokeWidth: 2)
                          ])))
                    : AuthScreen(controller: controller),
          ));
}
