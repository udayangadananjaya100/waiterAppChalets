import 'package:flutter/material.dart';
import '../data/live_repository.dart';
import '../state/app_controller.dart';
import 'theme.dart';

class AuthScreen extends StatefulWidget {
  final AppController controller;
  const AuthScreen({super.key, required this.controller});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _hide = true;
  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    try {
      await widget.controller.signIn(_identifier.text, _password.text);
      _password.clear();
    } catch (e) {
      if (mounted) showMessage(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.controller;
    return Scaffold(
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child:
                        ListView(padding: const EdgeInsets.all(26), children: [
                      Row(children: [
                        const BrandMark(size: 38),
                        const SizedBox(width: 10),
                        const Expanded(
                            child: Text('ORUTHOTA CHALETS',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.8))),
                        IconButton(
                            tooltip: 'Connection settings',
                            onPressed: app.busy
                                ? null
                                : () => showConnectionSettings(context, app),
                            icon: const Icon(Icons.tune_rounded, size: 22))
                      ]),
                      const SizedBox(height: 30),
                      Container(
                          height: 180,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                              color: Palette.forest,
                              borderRadius: BorderRadius.circular(24)),
                          child: Stack(children: [
                            const Positioned.fill(
                                child:
                                    CustomPaint(painter: LandscapePainter())),
                            Positioned(
                                left: 24,
                                top: 24,
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                        border:
                                            Border.all(color: Colors.white30),
                                        borderRadius:
                                            BorderRadius.circular(30)),
                                    child: const Text('THE SERVICE COMPANION',
                                        style: TextStyle(
                                            fontSize: 9,
                                            letterSpacing: 1.8,
                                            color: Color(0xFFE4ECD9),
                                            fontWeight: FontWeight.w700)))),
                            const Positioned(
                                left: 24,
                                bottom: 22,
                                child: Text('A little care.\nA memorable stay.',
                                    style: TextStyle(
                                        fontFamily: 'Lora',
                                        fontSize: 26,
                                        height: 1.25,
                                        color: Colors.white)))
                          ])),
                      const SizedBox(height: 28),
                      Text('Welcome to your shift.',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      const Text(
                          'Your tables, orders and team. All in one place.',
                          style: TextStyle(color: Palette.muted, height: 1.6)),
                      const SizedBox(height: 24),
                      if (!app.configured) ...[
                        Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                color: Palette.mint,
                                borderRadius: BorderRadius.circular(14)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('First time here?',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 6),
                                  const Text(
                                      'Connect to your restaurant, or try a practice shift to learn the flow.'),
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                      onPressed: () =>
                                          showConnectionSettings(context, app),
                                      icon: const Icon(Icons.link, size: 18),
                                      label: const Text('Connect restaurant'))
                                ])),
                        const SizedBox(height: 20),
                      ],
                      Form(
                          key: _form,
                          child: AutofillGroup(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                const Text('Email or employee number',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12)),
                                const SizedBox(height: 8),
                                TextFormField(
                                    controller: _identifier,
                                    autofillHints: const [
                                      AutofillHints.username
                                    ],
                                    autocorrect: false,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                        hintText: 'e.g. 0012 or your email',
                                        prefixIcon: Icon(Icons.badge_outlined,
                                            size: 20)),
                                    validator: (v) => v == null ||
                                            v.trim().isEmpty
                                        ? 'Enter your email or employee number.'
                                        : null),
                                const SizedBox(height: 18),
                                const Text('Password',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12)),
                                const SizedBox(height: 8),
                                TextFormField(
                                    controller: _password,
                                    obscureText: _hide,
                                    autofillHints: const [
                                      AutofillHints.password
                                    ],
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    onFieldSubmitted: (_) {
                                      if (app.configured && !app.busy) _login();
                                    },
                                    decoration: InputDecoration(
                                        hintText: 'Enter your password',
                                        prefixIcon: const Icon(
                                            Icons.lock_outline,
                                            size: 20),
                                        suffixIcon: IconButton(
                                            tooltip: _hide
                                                ? 'Show password'
                                                : 'Hide password',
                                            onPressed: () =>
                                                setState(() => _hide = !_hide),
                                            icon: Icon(
                                                _hide
                                                    ? Icons.visibility_outlined
                                                    : Icons
                                                        .visibility_off_outlined,
                                                size: 20))),
                                    validator: (v) => v == null || v.isEmpty
                                        ? 'Enter your password.'
                                        : null),
                                const SizedBox(height: 22),
                                FilledButton(
                                    onPressed: app.configured && !app.busy
                                        ? _login
                                        : null,
                                    child: app.busy
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white))
                                        : const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                                Text('Start my shift'),
                                                SizedBox(width: 14),
                                                Icon(
                                                    Icons.arrow_forward_rounded,
                                                    size: 18)
                                              ])),
                              ]))),
                      if (app.error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(app.error!,
                                style: const TextStyle(color: Palette.red))),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                          onPressed: app.busy ? null : app.practice,
                          icon: const Icon(Icons.explore_outlined, size: 18),
                          label: const Text('Try a practice shift')),
                      const SizedBox(height: 18),
                      const Text(
                          'Need an account? Ask your restaurant manager.\nPractice mode never changes restaurant data.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11, height: 1.7, color: Palette.muted)),
                    ])))));
  }
}

class LandscapePainter extends CustomPainter {
  const LandscapePainter();
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawCircle(Offset(s.width * .8, s.height * .28), 25,
        Paint()..color = const Color(0xFFDFC99C));
    final back = Path()
      ..moveTo(s.width * .32, s.height)
      ..lineTo(s.width * .65, s.height * .3)
      ..lineTo(s.width * .79, s.height * .56)
      ..lineTo(s.width, s.height * .2)
      ..lineTo(s.width, s.height)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0xFF436154));
    final front = Path()
      ..moveTo(s.width * .43, s.height)
      ..quadraticBezierTo(
          s.width * .66, s.height * .48, s.width, s.height * .67)
      ..lineTo(s.width, s.height)
      ..close();
    canvas.drawPath(front, Paint()..color = const Color(0xFF67806A));
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(
          Offset(s.width * .75 + i * 15, s.height),
          Offset(s.width * .93 + i * 15, s.height * .73),
          Paint()
            ..color = const Color(0xFF82947A)
            ..strokeWidth = .7);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<void> showConnectionSettings(
    BuildContext context, AppController app) async {
  final server = TextEditingController(text: app.config.server);
  final database = TextEditingController(text: app.config.supabaseUrl);
  final key = TextEditingController(text: app.config.publicKey);
  final form = GlobalKey<FormState>();
  await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 0, 24, MediaQuery.viewInsetsOf(sheet).bottom + 24),
          child: SingleChildScrollView(
              child: Form(
                  key: form,
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Connect your restaurant',
                            style: Theme.of(sheet).textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        const Text(
                            'Use the same website address as your admin system. Your manager can help with this.',
                            style: TextStyle(color: Palette.muted)),
                        const SizedBox(height: 22),
                        TextFormField(
                            controller: server,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            decoration: const InputDecoration(
                                labelText: 'Admin website',
                                hintText: 'https://admin.your-restaurant.com'),
                            validator: (v) =>
                                ConnectionConfig.validateServer(v ?? '')),
                        const SizedBox(height: 12),
                        ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('Advanced connection',
                                style: TextStyle(fontSize: 12)),
                            subtitle: const Text(
                                'Existing project database is preconfigured',
                                style: TextStyle(fontSize: 10)),
                            children: [
                              const SizedBox(height: 8),
                              TextFormField(
                                  controller: database,
                                  decoration: const InputDecoration(
                                      labelText: 'Supabase project URL'),
                                  validator: (v) =>
                                      Uri.tryParse(v ?? '')?.scheme ==
                                                  'https' &&
                                              (Uri.tryParse(v ?? '')
                                                      ?.host
                                                      .isNotEmpty ??
                                                  false)
                                          ? null
                                          : 'Enter an HTTPS database URL.'),
                              const SizedBox(height: 14),
                              TextFormField(
                                  controller: key,
                                  maxLines: 2,
                                  decoration: const InputDecoration(
                                      labelText: 'Publishable / anon key'),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'A public database key is required.';
                                    }
                                    if (v.startsWith('sb_secret_')) {
                                      return 'Use the publishable key, never a secret key.';
                                    }
                                    return null;
                                  }),
                              const SizedBox(height: 12),
                            ]),
                        const SizedBox(height: 18),
                        FilledButton(
                            onPressed: () async {
                              if (!form.currentState!.validate()) return;
                              await app.saveConfig(ConnectionConfig(
                                  server: server.text
                                      .trim()
                                      .replaceAll(RegExp(r'/+$'), ''),
                                  supabaseUrl: database.text
                                      .trim()
                                      .replaceAll(RegExp(r'/+$'), ''),
                                  publicKey: key.text.trim()));
                              if (sheet.mounted) Navigator.pop(sheet);
                            },
                            child: const Text('Save connection')),
                      ])))));
  // Controllers are disposed after the sheet's reverse animation has completed.
  await Future<void>.delayed(const Duration(milliseconds: 350));
  server.dispose();
  database.dispose();
  key.dispose();
}
