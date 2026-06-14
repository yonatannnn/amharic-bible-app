import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase.dart';
import '../providers.dart';
import 'login.dart';
import 'onboarding.dart';
import 'shell.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-fetch the profile whenever the signed-in user changes.
    ref.listen(authChangesProvider, (prev, next) {
      final event = next.asData?.value.event;
      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.signedOut ||
          event == AuthChangeEvent.userUpdated) {
        ref.invalidate(profileProvider);
      }
    });
    ref.watch(authChangesProvider); // rebuild on auth changes

    final session = supabase.auth.currentSession;
    if (session == null) return const LoginScreen();
    return ProfileGate(key: ValueKey(session.user.id));
  }
}

/// Once authenticated, routes to onboarding (no username) or the app shell.
class ProfileGate extends ConsumerWidget {
  const ProfileGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return profile.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const Scaffold(body: Center(child: CircularProgressIndicator())),
      data: (p) {
        final username = p?['username'] as String?;
        if (username == null || username.isEmpty) {
          return OnboardingScreen(onDone: () => ref.invalidate(profileProvider));
        }
        return const Shell();
      },
    );
  }
}
