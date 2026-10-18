import 'package:flutter/material.dart';

import '../theme/colors.dart';
import 'games_database.dart';
import 'guest_pass.dart';
import 'table_screen.dart';

/// The whole app for someone opening efoc.party/play?pass=CODE: type a
/// name, sit at that one table. No login, no Logs, no chat outside the
/// table. main.dart runs this instead of EfocApp for /play links.
class GuestPlayApp extends StatelessWidget {
  final String code;
  const GuestPlayApp({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Efoc — guest table',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: EfocColors.bg,
        colorScheme: ColorScheme.dark(
          primary: EfocColors.accent,
          secondary: EfocColors.accentBright,
          surface: EfocColors.surface,
          error: EfocColors.danger,
        ),
      ),
      home: GuestPlayScreen(code: code),
    );
  }
}

class GuestPlayScreen extends StatefulWidget {
  final String code;
  const GuestPlayScreen({super.key, required this.code});

  @override
  State<GuestPlayScreen> createState() => _GuestPlayScreenState();
}

class _GuestPlayScreenState extends State<GuestPlayScreen> {
  final _name = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    GuestPass.lastName().then((n) {
      if (n != null && mounted && _name.text.isEmpty) _name.text = n;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final name = _name.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isEmpty || name.length > 20) {
      setState(() => _error = 'Pick a name, up to 20 characters');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await GuestPass.redeem(widget.code, name);
      GamesDatabase.instance.useGuestToken(t.token, t.uid);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TableScreen(
            gameId: t.gameId,
            roomId: t.roomId,
            groupId: t.groupId,
            myUid: t.uid,
            myName: t.name,
            guest: true,
          ),
        ),
      );
      if (mounted) setState(() => _left = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 28),
              children: [
                const Text('🃏',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 56)),
                const SizedBox(height: 16),
                Text(
                  _left ? 'Thanks for playing!' : 'You\'re invited to a table',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _left
                      ? 'You can go back in while the link still works.'
                      : 'Just pick a name. No account, no email. Only the '
                          'people at this table see it, and it\'s gone when '
                          'the link expires.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _name,
                  maxLength: 20,
                  enabled: !_loading,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  cursorColor: EfocColors.accent,
                  onSubmitted: (_) => _go(),
                  decoration: InputDecoration(
                    hintText: 'Your name',
                    counterText: '',
                    hintStyle: const TextStyle(
                        color: EfocColors.textFaint, fontSize: 15),
                    filled: true,
                    fillColor: EfocColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 18),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: EfocColors.danger, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _go,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EfocColors.accent,
                      disabledBackgroundColor:
                          EfocColors.accent.withValues(alpha: 0.4),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(27),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            _left ? 'Back to the table' : 'Take a seat',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
