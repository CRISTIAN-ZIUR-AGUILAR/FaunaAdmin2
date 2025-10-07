import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:faunadmin2/providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  String _email = '';
  String _password = '';
  bool _loading = false;
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final isWide = w >= 720; // 🔑 breakpoint web/desktop

        // ======= APPBAR solo en móvil =======
        final appBar = isWide
            ? null
            : AppBar(
          title: const Text('Iniciar sesión'),
          toolbarHeight: 56,
        );

        // ======= CONTENIDO =======
        final formCard = _AuthCard(
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Text('Bienvenido', style: text.titleLarge),
                  const SizedBox(height: 18),

                  // -------- Email --------
                  TextFormField(
                    decoration: InputDecoration(
                      labelText: 'Correo electrónico',
                      hintText: 'correo@ejemplo.com',
                      prefixIcon: Icon(PhosphorIconsRegular.envelope, color: cs.onSurfaceVariant),
                    ),
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    onSaved: (v) => _email = (v ?? '').trim(),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Ingresa tu correo';
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v)) return 'Correo no válido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // -------- Password --------
                  TextFormField(
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      hintText: 'Tu contraseña',
                      prefixIcon: Icon(PhosphorIconsRegular.lockKey, color: cs.onSurfaceVariant),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                        icon: Icon(
                          _obscure ? PhosphorIconsRegular.eye : PhosphorIconsRegular.eyeSlash,
                          color: cs.onSurfaceVariant,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSaved: (v) => _password = (v ?? '').trim(),
                    validator: (v) {
                      if (v == null || v.length < 6) return 'Mínimo 6 caracteres';
                      if (v.contains(' ')) return 'Sin espacios';
                      return null;
                    },
                    onFieldSubmitted: (_) => _submit(auth),
                  ),

                  const SizedBox(height: 20),

                  // -------- CTA --------
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: _loading
                          ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                          : const Icon(PhosphorIconsBold.signIn),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text('Iniciar sesión'),
                      ),
                      onPressed: _loading ? null : () => _submit(auth),
                    ),
                  ),

                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(PhosphorIconsRegular.keyhole),
                    onPressed: () {/* recuperar si aplica */},
                    label: const Text('¿Olvidaste tu contraseña?'),
                  ),
                  const SizedBox(height: 6),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('¿No tienes cuenta?'),
                      TextButton(
                        onPressed: () => Navigator.pushReplacementNamed(context, '/register'),
                        child: const Text('Regístrate'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );

        // ======= LAYOUT =======
        return Scaffold(
          appBar: appBar,
          body: isWide
          // ------- WEB/DESKTOP: dos columnas -------
              ? Row(
            children: [
              // Panel lateral verde (branding)
              Flexible(
                flex: 5,
                child: Container(
                  height: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        cs.primary,
                        Color.lerp(cs.primary, Colors.black, 0.12)!,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: DefaultTextStyle(
                            style: text.titleLarge!.copyWith(color: cs.onPrimary),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: Color.lerp(cs.onPrimary, cs.primary, 0.8),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(PhosphorIconsFill.leaf, color: cs.onPrimary, size: 28),
                                ),
                                const SizedBox(height: 14),
                                const Text('FaunaApp', textScaleFactor: 1.2),
                                const SizedBox(height: 8),
                                Text(
                                  'Registro y validación de fauna silvestre de Oaxaca',
                                  style: text.bodyLarge!.copyWith(color: cs.onPrimary.withOpacity(.9)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Columna del formulario
              Flexible(
                flex: 7,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      child: formCard,
                    ),
                  ),
                ),
              ),
            ],
          )
          // ------- MÓVIL -------
              : SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: formCard,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit(AuthProvider auth) async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _loading = true);
    final String? error = await auth.signIn(_email, _password);
    setState(() => _loading = false);

    if (!mounted) return;

    if (error == null) {
      await fb.FirebaseAuth.instance.currentUser?.reload();

      String route;
      if (!auth.isApproved) {
        route = '/pending';
      } else if (auth.isAdmin) {
        route = '/admin/dashboard';
      } else if (auth.needsEmailVerification) {
        route = '/verifyEmail';
      } else {
        route = '/dashboard';
      }

      // 👇 ÚNICO CAMBIO: pasar argumento para evitar auto-nav a /seleccion
      final args = (route == '/dashboard') ? {'skipAutoNav': true} : null;

      Navigator.pushNamedAndRemoveUntil(
        context,
        route,
            (_) => false,
        arguments: args,
      );
    } else {
      if (error == 'Tu cuenta no está registrada o fue rechazada.') {
        await auth.signOut();
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

/// Tarjeta con sombra suave y bordes grandes
class _AuthCard extends StatelessWidget {
  final Widget child;
  const _AuthCard({required this.child});

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

