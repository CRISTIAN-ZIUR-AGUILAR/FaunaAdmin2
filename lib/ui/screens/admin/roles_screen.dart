// lib/ui/screens/admin/roles_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import 'package:faunadmin2/models/rol.dart';
import 'package:faunadmin2/services/firestore_service.dart';
import 'package:faunadmin2/services/seed_service.dart';

class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key});

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  final _fs = FirestoreService();

  // IDs protegidos: no se pueden eliminar.
  final Set<int> _protectedIds = const {
    Rol.admin,
    Rol.supervisor,
    Rol.recolector,
    Rol.duenoProyecto,
    Rol.colaborador,
  };

  // --- Navegación segura al Dashboard Admin ---
  void _goBack() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.maybePop();
    } else {
      nav.pushReplacementNamed('/admin/dashboard');
    }
  }

  void _openCreateDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _RoleDialog(
        onSave: (id, desc) async {
          await _fs.setRol(Rol(id: id, descripcion: desc));
        },
      ),
    );
  }

  void _openEditDialog(Rol rol) {
    showDialog(
      context: context,
      builder: (ctx) => _RoleDialog(
        initial: rol,
        onSave: (id, desc) async {
          await _fs.setRol(Rol(id: id, descripcion: desc));
        },
        readOnlyId: true,
      ),
    );
  }

  Future<void> _confirmDelete(Rol rol) async {
    if (_protectedIds.contains(rol.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este rol es parte del catálogo base y no puede eliminarse.')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar rol'),
        content: Text('¿Eliminar el rol "${rol.descripcion}" (id=${rol.id})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await _fs.deleteRol(rol.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rol eliminado')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _seedIfEmpty() async {
    final seeded = await SeedService().seedRolesIfEmpty();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(seeded ? 'Roles sembrados' : 'El catálogo ya existe')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authUser = fb.FirebaseAuth.instance.currentUser;
    final nombreHeader = 'Administrador'; // si quieres, puedes traerlo de tu perfil usuarios
    final correoHeader = authUser?.email ?? '—';

    return WillPopScope(
      onWillPop: () async {
        final nav = Navigator.of(context);
        if (nav.canPop()) return true;
        nav.pushReplacementNamed('/admin/dashboard');
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Roles'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBack,
          ),
          actions: [
            IconButton(
              tooltip: 'Sembrar catálogo base',
              icon: const Icon(Icons.cloud_download_outlined),
              onPressed: _seedIfEmpty,
            ),
            IconButton(
              tooltip: 'Nuevo rol',
              icon: const Icon(Icons.add),
              onPressed: _openCreateDialog,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openCreateDialog,
          icon: const Icon(Icons.add),
          label: const Text('Nuevo rol'),
        ),
        // 👇 Encabezado inline + contenido (sin depender de AdminHeader)
        body: Column(
          children: [
            _InlineHeader(
              title: nombreHeader,
              subtitle: correoHeader,
              contextText: 'Catálogo de roles',
            ),
            Expanded(
              child: StreamBuilder<List<Rol>>(
                stream: _fs.streamRoles(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final roles = [...snap.data!]..sort((a, b) => a.id.compareTo(b.id));

                  if (roles.isEmpty) {
                    return _Empty(onSeed: _seedIfEmpty);
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: roles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final r = roles[i];
                      final isProtected = _protectedIds.contains(r.id);
                      return Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          leading: CircleAvatar(child: Text('${r.id}')),
                          title: Text(
                            r.descripcion.isNotEmpty ? r.descripcion : 'Rol ${r.id}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: isProtected ? const Text('Rol base (protegido)') : null,
                          trailing: Wrap(
                            spacing: 6,
                            children: [
                              IconButton(
                                tooltip: 'Editar',
                                icon: const Icon(Icons.edit),
                                onPressed: () => _openEditDialog(r),
                              ),
                              IconButton(
                                tooltip: isProtected ? 'No permitido' : 'Eliminar',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: isProtected ? null : () => _confirmDelete(r),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Encabezado inline reutilizable en pantallas admin ----------

class _InlineHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? contextText;

  const _InlineHeader({
    required this.title,
    required this.subtitle,
    this.contextText,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface.withOpacity(.7);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 1.5,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                child: Text(
                  (title.isNotEmpty ? title[0] : 'A').toUpperCase(),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: onSurface)),
                    if (contextText != null && contextText!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(contextText!, style: TextStyle(color: onSurface, fontSize: 12.5)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------- Dialog para crear/editar --------------

class _RoleDialog extends StatefulWidget {
  final Rol? initial;
  final bool readOnlyId;
  final Future<void> Function(int id, String descripcion) onSave;

  const _RoleDialog({
    this.initial,
    this.readOnlyId = false,
    required this.onSave,
  });

  @override
  State<_RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends State<_RoleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _idCtrl;
  late final TextEditingController _descCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _idCtrl = TextEditingController(text: widget.initial?.id.toString() ?? '');
    _descCtrl = TextEditingController(text: widget.initial?.descripcion ?? '');
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final id = int.tryParse(_idCtrl.text.trim()) ?? 0;
    final desc = _descCtrl.text.trim();

    setState(() => _saving = true);
    try {
      // si es creación, evitar colisión por id
      if (widget.initial == null) {
        final exists = await FirebaseFirestore.instance
            .collection('roles')
            .doc(id.toString())
            .get();
        if (exists.exists) {
          throw 'Ya existe un rol con id=$id';
        }
      }

      await widget.onSave(id, desc);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cambios guardados')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;

    return AlertDialog(
      title: Text(isEdit ? 'Editar rol' : 'Nuevo rol'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _idCtrl,
                decoration: const InputDecoration(
                  labelText: 'ID de rol',
                  helperText: 'Entero positivo. No se recomienda cambiar los IDs base.',
                ),
                keyboardType: TextInputType.number,
                readOnly: widget.readOnlyId,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requerido';
                  final n = int.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Debe ser un entero > 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  hintText: 'Ej. SUPERVISOR',
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requerido';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(isEdit ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }
}

// -------------- Empty state --------------

class _Empty extends StatelessWidget {
  final VoidCallback onSeed;
  const _Empty({required this.onSeed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.badge_outlined, size: 52, color: cs.primary),
            const SizedBox(height: 12),
            const Text(
              'No hay roles en el catálogo.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Puedes sembrar el catálogo base (ADMIN, SUPERVISOR, RECOLECTOR, DUEÑO PROYECTO, COLABORADOR).',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onSeed,
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Sembrar catálogo base'),
            ),
          ],
        ),
      ),
    );
  }
}

