import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase.dart';
import '../theme.dart';
import '../state/settings.dart' as app;
import '../services/push.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        title: Text('Settings', style: display(context, size: 18, weight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _section(c, 'Reading', _readingCard(c)),
            const SizedBox(height: 26),
            _section(c, 'Account', _accountCard(c)),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _signOut,
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.brand,
                  side: BorderSide(color: c.line),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Sign out'),
              ),
            ),
            const SizedBox(height: 10),
            Center(child: Text('መጽሐፍ ቅዱስ', style: TextStyle(color: c.inkFaint, fontSize: 12))),
          ],
        ),
      ),
    );
  }

  Widget _section(AppColors c, String title, Widget child) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: display(context, size: 19, weight: FontWeight.w700)),
      const SizedBox(height: 12),
      child,
    ]);
  }

  Widget _card(AppColors c, List<Widget> children) => Container(
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(children: children),
      );

  Widget _readingCard(AppColors c) {
    return _card(c, [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Dark mode'),
        value: app.settings.themeMode == ThemeMode.dark,
        activeThumbColor: c.brand,
        onChanged: (v) => setState(() => app.settings.setTheme(v ? ThemeMode.dark : ThemeMode.light)),
      ),
      Divider(color: c.line, height: 1),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Serif scripture'),
        subtitle: Text('Noto Serif Ethiopic', style: TextStyle(color: c.inkFaint, fontSize: 12)),
        value: app.settings.serif,
        activeThumbColor: c.brand,
        onChanged: (v) => setState(() => app.settings.setSerif(v)),
      ),
      Divider(color: c.line, height: 1),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Font size · ${app.settings.readerSize.round()}', style: TextStyle(color: c.inkSoft, fontSize: 14)),
          Slider(
            min: 14, max: 26, value: app.settings.readerSize, activeColor: c.brand,
            onChanged: (v) => setState(() => app.settings.setSize(v)),
          ),
        ]),
      ),
    ]);
  }

  Widget _accountCard(AppColors c) {
    return _card(c, [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.lock_outline, color: c.ink),
        title: const Text('Change password'),
        trailing: Icon(Icons.chevron_right, color: c.inkFaint),
        onTap: _changePassword,
      ),
      Divider(color: c.line, height: 1),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.delete_outline, color: Colors.red),
        title: const Text('Delete account', style: TextStyle(color: Colors.red)),
        trailing: const Icon(Icons.chevron_right, color: Colors.red),
        onTap: _deleteAccount,
      ),
    ]);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  Future<void> _signOut() async {
    final c = colorsOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('Sign out?'),
        content: Text('You\'ll need to sign in again to continue your streaks.',
            style: TextStyle(color: c.inkSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: c.inkSoft))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: c.brand, foregroundColor: c.brandInk),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await PushService.instance.unregister();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await supabase.auth.signOut();
  }

  Future<void> _changePassword() async {
    final c = colorsOf(context);
    final current = TextEditingController();
    final next = TextEditingController();
    bool busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        Future<void> submit() async {
          if (next.text.length < 6) { setLocal(() => error = 'New password must be 6+ characters'); return; }
          setLocal(() { busy = true; error = null; });
          final email = supabase.auth.currentUser?.email;
          try {
            if (email != null) {
              await supabase.auth.signInWithPassword(email: email, password: current.text);
            }
            await supabase.auth.updateUser(UserAttributes(password: next.text));
            if (ctx.mounted) Navigator.pop(ctx);
            _snack('Password updated');
          } on AuthException catch (_) {
            setLocal(() { busy = false; error = 'Current password is incorrect'; });
          } catch (_) {
            setLocal(() { busy = false; error = 'Could not update password'; });
          }
        }

        return AlertDialog(
          backgroundColor: c.surface,
          title: const Text('Change password'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _dialogField(c, current, 'Current password'),
            const SizedBox(height: 10),
            _dialogField(c, next, 'New password'),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: c.inkSoft))),
            FilledButton(
              onPressed: busy ? null : submit,
              style: FilledButton.styleFrom(backgroundColor: c.brand, foregroundColor: c.brandInk),
              child: Text(busy ? '…' : 'Update'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _deleteAccount() async {
    final c = colorsOf(context);
    final confirm = TextEditingController();
    bool busy = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final canDelete = confirm.text.trim().toUpperCase() == 'DELETE';
        return AlertDialog(
          backgroundColor: c.surface,
          title: const Text('Delete account?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('This permanently deletes your account, streaks, messages and saved verses. This can\'t be undone.',
                style: TextStyle(color: c.inkSoft)),
            const SizedBox(height: 12),
            Text('Type DELETE to confirm', style: TextStyle(color: c.inkFaint, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: confirm,
              onChanged: (_) => setLocal(() {}),
              decoration: InputDecoration(
                isDense: true, filled: true, fillColor: c.surface2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red)),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: c.inkSoft))),
            FilledButton(
              onPressed: (!canDelete || busy) ? null : () async {
                setLocal(() => busy = true);
                try {
                  await supabase.rpc('delete_my_account');
                } catch (_) {}
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: Text(busy ? '…' : 'Delete'),
            ),
          ],
        );
      }),
    );
    if (ok == true) {
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      await supabase.auth.signOut();
    }
  }

  Widget _dialogField(AppColors c, TextEditingController ctl, String hint) {
    return TextField(
      controller: ctl,
      obscureText: true,
      decoration: InputDecoration(
        hintText: hint, isDense: true, filled: true, fillColor: c.surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.brand)),
      ),
    );
  }
}
