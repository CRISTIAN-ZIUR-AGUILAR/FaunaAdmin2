// lib/ui/screens/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

import 'package:faunadmin2/providers/auth_provider.dart';
// import 'package:faunadmin2/providers/notificacion_provider.dart';           // TODO: Rehabilitar notificaciones
// import 'package:faunadmin2/models/notificacion.dart';                       // TODO: Rehabilitar notificaciones
// import 'package:faunadmin2/utils/notificaciones_constants.dart';            // TODO: Rehabilitar notificaciones

// Drawer
import 'package:faunadmin2/ui/widgets/app_drawer.dart';

// Sync + almacenamiento local
import 'package:faunadmin2/services/local_file_storage.dart';
import 'package:faunadmin2/services/sync_observaciones_service.dart';

// Para leer nombre_completo desde Firestore
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

class DashboardScreen extends StatefulWidget {
  final bool skipAutoNavFromRoute;
  const DashboardScreen({super.key, this.skipAutoNavFromRoute = false});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // ---- Nombre desde Firestore
  String? _fullNameFromDb;

  // ---- Sync state
  bool _syncing = false;
  int _pendientesLocal = 0;

  // ✅ Seguro para web: sin importar dart:io
  bool get _isMobile {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // TODO: Rehabilitar notificaciones
      // context.read<NotificacionProvider>().start();

      await _loadNombreCompleto();

      // Solo en móvil tocamos el filesystem local
      if (_isMobile) {
        await _refreshPendingLocal();
        // (Opcional) Auto-sync silencioso al abrir si hay pendientes
        // if (_pendientesLocal > 0) _runSync(showSnackbars: false);
      }
    });
  }

  Future<void> _loadNombreCompleto() async {
    try {
      final uid = fb.FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      final data = doc.data();
      final nombre = (data != null ? (data['nombre_completo'] as String?) : null)?.trim();
      if (!mounted) return;
      if (nombre != null && nombre.isNotEmpty) {
        setState(() => _fullNameFromDb = nombre);
      }
    } catch (_) {
      // Silencioso: si falla, se usa displayName de Auth o 'Usuario'
    }
  }

  // Cuenta carpetas locales que NO estén marcadas como SYNCED (solo móvil)
  Future<void> _refreshPendingLocal() async {
    if (!_isMobile) return;
    try {
      final dirList = await LocalFileStorage.instance.listarObservaciones();
      int count = 0;
      for (final d in dirList) {
        final meta = await LocalFileStorage.instance.leerMeta(d);
        if (meta == null) continue;
        final status = (meta['status'] ?? '').toString().toUpperCase();
        if (status != 'SYNCED') count++;
      }
      if (!mounted) return;
      setState(() => _pendientesLocal = count);
    } catch (_) {
      if (!mounted) return;
      setState(() => _pendientesLocal = 0);
    }
  }

  // Ejecuta la sincronización con la nube usando el servicio (solo móvil)
  Future<void> _runSync({bool showSnackbars = true}) async {
    if (!_isMobile) {
      if (showSnackbars && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La sincronización local solo está disponible en Android/iOS.')),
        );
      }
      return;
    }

    if (_syncing) return;
    setState(() => _syncing = true);

    try {
      final svc = SyncObservacionesService();

      final result = await svc.syncPending(
        context: context,
        deleteLocalAfterUpload: true,
        onLog: (msg) => debugPrint('[SYNC] $msg'),
        onProgress: (done, total) => debugPrint('[SYNC] progreso $done / $total'),
      );

      await _refreshPendingLocal();

      if (showSnackbars && mounted) {
        final ok = result.uploadedCount;
        final skipped = result.skippedCount;
        final failed = result.failedCount;
        final msg = 'Sincronización: $ok subidas, $skipped omitidas, $failed fallidas.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (showSnackbars && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al sincronizar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // ===== NOTIFICACIONES DESACTIVADAS =====
    const int unreadCount = 0;

    // Preferir nombre_completo de Firestore; fallback a displayName de Auth
    final firebaseDisplayName =
    (auth.user?.displayName?.trim().isNotEmpty ?? false) ? auth.user!.displayName!.trim() : null;
    final displayName = (_fullNameFromDb?.isNotEmpty ?? false)
        ? _fullNameFromDb!
        : (firebaseDisplayName ?? 'Usuario');

    final correo = auth.user?.email ?? '—';
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            tooltip: MaterialLocalizations.of(ctx).openAppDrawerTooltip,
          ),
        ),
        // Saludo usando el primer nombre del nombre_completo (o fallback)
        title: Text('Hola, ${displayName.split(' ').first}'),
        actions: [
          // Botón de sincronizar en AppBar (solo móvil)
          if (_isMobile)
            IconButton(
              tooltip: _pendientesLocal > 0
                  ? 'Sincronizar ($_pendientesLocal pendiente${_pendientesLocal == 1 ? '' : 's'})'
                  : 'Sincronizar',
              onPressed: _syncing ? null : () => _runSync(showSnackbars: true),
              icon: _syncing
                  ? const SizedBox(
                  height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_outlined),
            ),

          if (unreadCount > 0)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: _UnreadDot(),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadNombreCompleto();
          if (_isMobile) await _refreshPendingLocal();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            // ===== ENCABEZADO =====
            _HeaderCard(
              name: displayName,
              email: correo,
              onSubirDatosElegirRol: () => Navigator.of(context).pushNamed('/seleccion'),
            ),
            const SizedBox(height: 14),

            // ===== KPIs simples =====
            Row(
              children: [
                Expanded(
                  child: _KpiCard(
                    icon: Icons.person_outline,
                    label: 'Usuario',
                    value: displayName, // ⬅️ nombre_completo
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _KpiCard(
                    icon: Icons.email_outlined,
                    label: 'Correo',
                    value: correo,
                    color: cs.tertiary,
                    compact: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ===== Tarjeta de sincronización (solo móvil) =====
            if (_isMobile)
              _SyncCard(
                pendientes: _pendientesLocal,
                syncing: _syncing,
                onSync: _runSync,
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: cs.surface,
                  border: Border.all(color: cs.outline.withOpacity(.16)),
                ),
                child: const Text(
                  'La sincronización local (archivos en el dispositivo) está disponible solo en Android/iOS.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),

            const SizedBox(height: 16),

            // Placeholder mientras notificaciones siguen en pausa
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: cs.surface,
                border: Border.all(color: cs.outline.withOpacity(.16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Módulos en pausa', style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 8),
                  Text(
                    'Las notificaciones están temporalmente desactivadas.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot();
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: const [
        Icon(Icons.notifications),
        Positioned(
          right: 2,
          top: 8,
          child: SizedBox(
            width: 10,
            height: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            ),
          ),
        )
      ],
    );
  }
}

// ========================= WIDGETS DE UI =========================

class _HeaderCard extends StatelessWidget {
  final String name;
  final String email;
  final VoidCallback onSubirDatosElegirRol;
  final VoidCallback? onMarkAllRead;

  const _HeaderCard({
    required this.name,
    required this.email,
    required this.onSubirDatosElegirRol,
    this.onMarkAllRead,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary.withOpacity(.12), cs.secondary.withOpacity(.08)],
        ),
        border: Border.all(color: cs.outline.withOpacity(.15)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: cs.primary.withOpacity(.15),
            child: Icon(Icons.person, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.bodyMedium!,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(email, style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: -6,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.upload_rounded, size: 18),
                        label: const Text('Subir datos (elegir rol/proyecto)'),
                        onPressed: onSubirDatosElegirRol,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton.icon(
            onPressed: onMarkAllRead, // inactivo mientras no haya notificaciones
            icon: const Icon(Icons.mark_email_read_outlined),
            label: const Text('Marcar todo\ncomo leído'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool compact;

  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cs.surface,
        border: Border.all(color: cs.outline.withOpacity(.16)),
        boxShadow: [BoxShadow(blurRadius: 10, offset: const Offset(0, 2), color: Colors.black.withOpacity(0.05))],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withOpacity(.12),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: compact ? 12 : 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- TARJETA DE SINCRONIZACIÓN ----
class _SyncCard extends StatelessWidget {
  final int pendientes;
  final bool syncing;
  final Future<void> Function({bool showSnackbars}) onSync;

  const _SyncCard({
    required this.pendientes,
    required this.syncing,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cs.surface,
        border: Border.all(color: cs.outline.withOpacity(.16)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: cs.primary.withOpacity(.10),
            child: const Icon(Icons.sync, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sincronizar observaciones guardadas',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  pendientes == 0
                      ? 'No hay observaciones por subir desde el teléfono.'
                      : '$pendientes observación(es) lista(s) para subir desde el teléfono.',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: syncing ? null : () => onSync(showSnackbars: true),
            icon: syncing
                ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(syncing ? 'Sincronizando…' : 'Sincronizar'),
            // 🔧 FIX: fuerza tamaño finito y evita minHeight 64 que rompía el sliver
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
    );
  }
}
