// lib/ui/guards/admin_guard.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class AdminGuard extends StatefulWidget {
  final Widget child;
  const AdminGuard({super.key, required this.child});

  @override
  State<AdminGuard> createState() => _AdminGuardState();
}

class _AdminGuardState extends State<AdminGuard> {
  bool _navigated = false;

  void _safeRedirect(String route) {
    if (_navigated) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.hasTriedFirebase || auth.isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!auth.isLoggedIn) {
      _safeRedirect('/login');
      return const SizedBox.shrink();
    }
    if (!auth.isApproved) {
      _safeRedirect('/pending');
      return const SizedBox.shrink();
    }
    if (!auth.isAdmin) {
      _safeRedirect('/seleccion');
      return const SizedBox.shrink();
    }
    return widget.child; // ✅ es admin
  }
}
