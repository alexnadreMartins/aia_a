import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../logic/auth_repository.dart';
import 'login_screen.dart';
import 'main_window.dart';

class RootWidget extends ConsumerWidget {
  const RootWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);

    if (user == null) {
      return const LoginScreen();
    }
    return const PhotoBookHome();
  }
}
