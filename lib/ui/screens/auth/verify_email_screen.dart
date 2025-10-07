// lib/ui/screens/auth/verify_email_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart'; // 👈 íconos

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({Key? key}) : super(key: key);

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _sent = false;
  bool _checking = false;
  final _auth = FirebaseAuth.instance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (auth.isAdmin) {
      // Redirige de inmediato al admin
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/admin/dashboard');
      });
    }
  }

  Future<void> _sendVerification() async {
    await _auth.currentUser!.sendEmailVerification();
    setState(() => _sent = true);
  }

  Future<void> _checkVerified() async {
    setState(() => _checking = true);
    await _auth.currentUser!.reload();
    setState(() => _checking = false);
    if (_auth.currentUser!.emailVerified) {
      // Usuario normal verificado → selección
      Navigator.pushReplacementNamed(context, '/dashboard');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aún no has verificado tu correo')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cs   = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (auth.isAdmin) {
      // Mostrar loader mientras redirige
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Verifica tu correo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _InfoCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ícono de estado en círculo (cambia si ya se envió)
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withOpacity(.6),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      _sent
                          ? PhosphorIconsDuotone.checkCircle
                          : PhosphorIconsDuotone.envelopeSimpleOpen,
                      size: 36,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Verifica tu correo electrónico',
                    style: text.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  Text(
                    _sent
                        ? 'Revisa tu bandeja (y spam) para el enlace de verificación. Cuando ya lo hayas hecho, presiona “Ya verifiqué – Continuar”.'
                        : 'Pulsa el botón para enviar el correo de verificación a tu dirección registrada.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),

                  // CTA principal (envía o valida)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _sent ? _checkVerified : _sendVerification,
                      icon: _checking
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                          : Icon(_sent
                          ? PhosphorIconsBold.check
                          : PhosphorIconsBold.paperPlaneRight),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(_sent ? 'Ya verifiqué – Continuar' : 'Enviar correo'),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Botón secundario para volver al login (opcional)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                    },
                    icon: const Icon(PhosphorIconsRegular.signIn),
                    label: const Text('Volver al login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Widget child;
  const _InfoCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
      child: child,
    );
  }
}

