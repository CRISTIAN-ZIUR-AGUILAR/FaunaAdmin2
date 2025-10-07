import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:faunadmin2/utils/constants.dart';
// 👇 Nuevo: Phosphor
import 'package:phosphor_flutter/phosphor_flutter.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nombreCtrl = TextEditingController();
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();
  final _pass2Ctrl  = TextEditingController();
  final _areaCtrl   = TextEditingController();

  String? _ocupacion;
  String? _nivelAcademico;
  bool _obscure  = true;
  bool _obscure2 = true;
  bool _loading  = false;

  bool _aceptaTerminos = false;

  final _ocupaciones = const ['Estudiante','Profesional','Docente','Investigador','Otro'];
  final _niveles = const ['Técnico','Licenciatura','Maestría','Doctorado','Otro'];

  // ==== Espaciado consistente ====
  static const double kFieldGap   = 14; // entre campos
  static const double kRowGap     = 12; // entre columnas en web
  static const double kSectionGap = 18; // saltos de sección

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    _areaCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool get _formValidNow {
    final emailOk = RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(_emailCtrl.text.trim());
    final passOk  = _passCtrl.text.length >= 8 && _pass2Ctrl.text == _passCtrl.text; // 👈 8+
    final nomOk   = _nombreCtrl.text.trim().isNotEmpty;
    final selectsOk = (_ocupacion?.isNotEmpty == true) && (_nivelAcademico?.isNotEmpty == true);
    return nomOk && emailOk && passOk && selectsOk;
  }

  bool get _canSubmit => !_loading && _aceptaTerminos && _formValidNow;

  Future<void> _mostrarTerminos() async {
    String txt;
    try {
      txt = await rootBundle.loadString(kTerminosAssetPath);
    } catch (_) {
      txt = 'Términos y Condiciones no disponibles.';
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Material(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                controller: controller,
                children: [
                  const Text('Términos y Condiciones',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  SelectableText(txt),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cerrar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();

    if (!_formKey.currentState!.validate()) return;

    if (_ocupacion == null || _ocupacion!.isEmpty) {
      _snack('Selecciona tu ocupación.'); return;
    }
    if (_nivelAcademico == null || _nivelAcademico!.isEmpty) {
      _snack('Selecciona tu nivel académico.'); return;
    }
    if (!_aceptaTerminos) {
      _snack('Debes aceptar los Términos y Condiciones para registrarte.'); return;
    }

    if (mounted) setState(() => _loading = true);

    String? err;
    try {
      err = await auth.signUp(
        nombreCompleto: _nombreCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        ocupacion: _ocupacion!,
        nivelAcademico: _nivelAcademico!,
        area: _areaCtrl.text.trim(),
      );

      if (err == null) {
        final uid = fb.FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await FirebaseFirestore.instance
              .collection('usuarios')
              .doc(uid)
              .set({'terminos': buildTerminosValue()}, SetOptions(merge: true));

          await FirebaseFirestore.instance.collection('consent_logs').add({
            'uid': uid,
            'version': kTerminosVersion,
            'acceptedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      err = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    if (!mounted) return;

    if (err != null) {
      _snack(err);
      return;
    }

    _snack('Cuenta creada. Queda pendiente de aprobación.');
    Navigator.pushReplacementNamed(context, '/pending');
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    void _onChangedRebuild([_]) { if (mounted) setState(() {}); }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final isWide = w >= 720;
        final maxW  = 560.0;

        final appBar = isWide ? null : AppBar(title: const Text('Crear cuenta'));

        // ==== Helper unificado con helperText ====
        InputDecoration _dec({
          required String label,
          IconData? icon,
          String? hint,
          String? helper,
        }) {
          return InputDecoration(
            labelText: label,
            hintText: hint,
            helperText: helper,                 // 👈 aviso pequeño bajo el campo
            helperMaxLines: 2,
            prefixIcon: icon != null ? Icon(icon) : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          );
        }

        Widget _row2(Widget a, Widget b) {
          if (!isWide) {
            return Column(
              children: [
                a,
                const SizedBox(height: kFieldGap),
                b,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: kRowGap),
              Expanded(child: b),
            ],
          );
        }

        final form = AutofillGroup(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction, // 👈 pinta y avisa en vivo
            child: Column(
              children: [
                Text('Crea tu cuenta', style: text.titleLarge),
                const SizedBox(height: kSectionGap),

                // Nombre + Email
                _row2(
                  TextFormField(
                    controller: _nombreCtrl,
                    decoration: _dec(
                      label: 'Nombre completo',
                      icon: PhosphorIconsRegular.identificationBadge,
                      helper: 'Tal como aparece en tu identificación.',
                    ),
                    onChanged: _onChangedRebuild,
                    autofillHints: const [AutofillHints.name],
                    validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Escribe tu nombre completo' : null,
                  ),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: _dec(
                      label: 'Correo electrónico',
                      icon: PhosphorIconsRegular.envelopeSimple,
                      helper: 'Usa un formato válido (ej. nombre@dominio.com).',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    onChanged: _onChangedRebuild,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Escribe tu correo';
                      final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim());
                      return ok ? null : 'Correo inválido';
                    },
                  ),
                ),
                const SizedBox(height: kFieldGap),

                // Password + Confirmación
                _row2(
                  TextFormField(
                    controller: _passCtrl,
                    decoration: _dec(
                      label: 'Contraseña',
                      icon: PhosphorIconsRegular.lockKey,
                      helper: 'Mínimo 8 caracteres.',
                    ).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? PhosphorIconsRegular.eye
                            : PhosphorIconsRegular.eyeSlash),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    onChanged: _onChangedRebuild,
                    validator: (v) =>
                    (v == null || v.length < 8) ? 'Debe tener al menos 8 caracteres' : null,
                  ),
                  TextFormField(
                    controller: _pass2Ctrl,
                    decoration: _dec(
                      label: 'Confirmar contraseña',
                      icon: PhosphorIconsRegular.password,
                      helper: 'Repite la misma contraseña.',
                    ).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_obscure2
                            ? PhosphorIconsRegular.eye
                            : PhosphorIconsRegular.eyeSlash),
                        onPressed: () => setState(() => _obscure2 = !_obscure2),
                      ),
                    ),
                    obscureText: _obscure2,
                    onChanged: _onChangedRebuild,
                    validator: (v) => (v != _passCtrl.text) ? 'Las contraseñas no coinciden' : null,
                  ),
                ),
                const SizedBox(height: kFieldGap),

                // Ocupación + Nivel académico
                _row2(
                  DropdownButtonFormField<String>(
                    decoration: _dec(
                      label: 'Ocupación',
                      icon: PhosphorIconsRegular.briefcase,
                      helper: 'Selecciona la opción que mejor te describe.',
                    ),
                    value: _ocupacion,
                    items: _ocupaciones.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setState(() => _ocupacion = v),
                    validator: (v) => (v == null || v.isEmpty) ? 'Selecciona tu ocupación' : null,
                  ),
                  DropdownButtonFormField<String>(
                    decoration: _dec(
                      label: 'Nivel académico',
                      icon: PhosphorIconsRegular.graduationCap,
                      helper: 'Último grado concluido o en curso.',
                    ),
                    value: _nivelAcademico,
                    items: _niveles.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setState(() => _nivelAcademico = v),
                    validator: (v) => (v == null || v.isEmpty) ? 'Selecciona tu nivel académico' : null,
                  ),
                ),
                const SizedBox(height: kFieldGap),

                // Área (full width)
                TextFormField(
                  controller: _areaCtrl,
                  decoration: _dec(
                    label: 'Área (opcional)',
                    icon: PhosphorIconsRegular.tag,
                    hint: 'Biología, Educación Ambiental, Sistemas, etc.',
                    helper: 'Ayuda a personalizar revisiones (opcional).',
                  ),
                ),
                const SizedBox(height: kSectionGap),

                // Términos
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _mostrarTerminos,
                    child: const Text('Leer Términos y Condiciones'),
                  ),
                ),
                CheckboxListTile(
                  value: _aceptaTerminos,
                  onChanged: (v) => setState(() => _aceptaTerminos = v ?? false),
                  title: const Text('Acepto los Términos y Condiciones'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: kSectionGap),

                // Botón
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _canSubmit ? _submit : null,
                    icon: _loading
                        ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(PhosphorIconsBold.userPlus),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text('Crear cuenta'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Ir a login
                TextButton(
                  onPressed: _loading ? null : () => Navigator.pushReplacementNamed(context, '/login'),
                  child: Text('¿Ya tienes cuenta? Inicia sesión', style: TextStyle(color: cs.primary)),
                ),
              ],
            ),
          ),
        );

        return Scaffold(
          appBar: isWide ? null : AppBar(title: const Text('Crear cuenta')),
          body: isWide
              ? Row(
            children: [
              // Lateral verde
              Flexible(
                flex: 5,
                child: Container(
                  height: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [cs.primary, Color.lerp(cs.primary, Colors.black, 0.12)!],
                    ),
                  ),
                  child: SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: DefaultTextStyle(
                            style: text.titleLarge!.copyWith(color: cs.onPrimary),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text('FaunaApp', textScaleFactor: 1.2),
                                SizedBox(height: 8),
                                Text('Registro de usuarios y validación de perfiles'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Form centrado
              Flexible(
                flex: 7,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      child: _AuthCard(child: form),
                    ),
                  ),
                ),
              ),
            ],
          )
              : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _AuthCard(child: form),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Igual que en login para consistencia
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
