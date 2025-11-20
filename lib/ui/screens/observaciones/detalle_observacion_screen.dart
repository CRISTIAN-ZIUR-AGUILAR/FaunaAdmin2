// lib/ui/screens/observaciones/detalle_observacion_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:faunadmin2/services/observacion_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
// Mapa
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';
// Modelos / providers / servicios
import 'package:faunadmin2/models/observacion.dart';
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/services/permisos_service.dart';

class DetalleObservacionScreen extends StatelessWidget {
  final String observacionId;
  const DetalleObservacionScreen({super.key, required this.observacionId});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('observaciones')
        .doc(observacionId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(child: Text('Error: ${snap.error}')),
          );
        }
        if (!snap.hasData || !snap.data!.exists) {
          return const Scaffold(
            body: Center(child: Text('Observación no encontrada')),
          );
        }
        final data = snap.data!.data()!;
        final obs = Observacion.fromMap(data, snap.data!.id);
        // Fotos (mediaUrls -> portada al inicio -> fallback legacy 'fotos')
        final List<String> fotos = () {
          final base = List<String>.from(obs.mediaUrls);
          if (_hasStr(obs.coverUrl) && !base.contains(obs.coverUrl!.trim())) {
            base.insert(0, obs.coverUrl!.trim());
          }
          if (base.isNotEmpty) return base;
          final ff = data['fotos'];
          if (ff is List) {
            final legacy = ff.whereType<String>().toList();
            legacy.sort((a, b) {
              final ah = a.startsWith('http'), bh = b.startsWith('http');
              if (ah == bh) return 0;
              return ah ? -1 : 1;
            });
            return legacy;
          }
          return const <String>[];
        }();
        // Fecha “de registro” fallback si no hay fecha_captura
        DateTime? fechaRegistro;
        final fr = data['fecha_registro'];
        if (fr is Timestamp) fechaRegistro = fr.toDate();
        if (fr is String) fechaRegistro = DateTime.tryParse(fr);
        fechaRegistro ??= obs.fechaCaptura;
        // ===== Permisos V2 =====
        final auth = context.read<AuthProvider>();
        final permisos = PermisosService(auth);
        final bool canEditV2 = permisos.canEditObsV2(
          idProyecto: obs.idProyecto,
          uidAutor: obs.uidUsuario,
          estado: obs.estado,
        );
        final bool canDeleteV2 = permisos.canDeleteObsV2(
          idProyecto: obs.idProyecto,
          uidAutor: obs.uidUsuario,
          estado: obs.estado,
        );
        // Ahora usamos el getter del modelo en lugar de recalcular aquí
        final bool datosCompletos = obs.datosCompletos;
        final bool canSubmit = permisos.canSubmitToPending(
          uidAutor: obs.uidUsuario,
          estadoActual: obs.estado,
          datosCompletos: datosCompletos,
        );
        String? blockedReason;
        if (!canEditV2) {
          final esAutor = (auth.uid != null && obs.uidUsuario == auth.uid);
          switch (obs.estado) {
            case EstadosObs.borrador:
              blockedReason =
              esAutor ? null : 'Solo el autor o un admin pueden editar el borrador.';
              break;
            case EstadosObs.pendiente:
              blockedReason =
              'Solo un supervisor/dueño del mismo proyecto o admin pueden editar en Pendiente.';
              break;
            case EstadosObs.aprobado:
            case EstadosObs.rechazado:
            case EstadosObs.archivado:
              blockedReason =
              'Las observaciones ${obs.estado} solo las puede editar un admin.';
              break;
            default:
              blockedReason = 'No tienes permisos para editar esta observación.';
          }
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Detalle de observación'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // 1) Fotografías (16:9 en tarjeta)
                  _SectionWrap(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                      child: _MediaCarousel(
                        urls: fotos,
                        onOpenFullscreen: (i) =>
                            _openFullscreen(context, fotos, i),
                      ),
                    ),
                  ),
                  // 2) CONTENEDOR ÚNICO con tabs (incluye banner y acciones al final)
                  _SectionWrap(
                    child: _ObservacionContentCard(
                      obs: obs,
                      fotos: fotos,
                      canEdit: canEditV2,
                      canDelete: canDeleteV2,
                      canSubmit: canSubmit,
                      blockedReason: blockedReason,
                      rejectedAt: obs.validatedAt,
                      updatedAt: (obs.updatedAt ?? obs.ultimaModificacion),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  static Color _estadoColor(BuildContext context, String estado) {
    final cs = Theme.of(context).colorScheme;
    switch (estado) {
      case EstadosObs.borrador:
        return cs.secondary;
      case EstadosObs.pendiente:
        return cs.primary;
      case EstadosObs.aprobado:
        return Colors.green.shade700;
      case EstadosObs.rechazado:
        return Colors.red.shade700;
      case EstadosObs.archivado:
        return cs.outline;
      default:
        return cs.onSurfaceVariant;
    }
  }
  void _openFullscreen(BuildContext context, List<String> urls, int initial) {
    if (urls.isEmpty) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      barrierColor: Colors.black.withOpacity(.95),
      pageBuilder: (_, __, ___) =>
          _FullscreenMediaViewer(urls: urls, initialIndex: initial),
      transitionBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }
}
// ================== SUBWIDGETS ==================
class _MediaCarousel extends StatefulWidget {
  const _MediaCarousel({required this.urls, required this.onOpenFullscreen});
  final List<String> urls;
  final ValueChanged<int> onOpenFullscreen;

  @override
  State<_MediaCarousel> createState() => _MediaCarouselState();
}

class _MediaCarouselState extends State<_MediaCarousel> {
  final _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    if (urls.isEmpty) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: _cardBg(context),
          alignment: Alignment.center,
          child: const Icon(Icons.photo, size: 48),
        ),
      );
    }

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: PageView.builder(
              controller: _page,
              itemCount: urls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => widget.onOpenFullscreen(i),
                child: _NetworkImageMaybeGs(url: urls[i], fit: BoxFit.cover),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            urls.length,
                (i) => Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == _index
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final u = urls[i];
              final selected = i == _index;
              return GestureDetector(
                onTap: () {
                  _page.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                  setState(() => _index = i);
                },
                onLongPress: () => widget.onOpenFullscreen(i),
                child: Container(
                  width: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _NetworkImageMaybeGs(url: u, fit: BoxFit.cover),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NetworkImageMaybeGs extends StatelessWidget {
  const _NetworkImageMaybeGs({required this.url, this.fit});
  final String url;
  final BoxFit? fit;

  static final Map<String, String> _cache = {};
  static Future<String> resolve(String u) async {
    if (u.isEmpty) return '';
    if (!u.startsWith('gs://')) return u;
    final cached = _cache[u];
    if (cached != null && cached.isNotEmpty) return cached;
    final https = await FirebaseStorage.instance.refFromURL(u).getDownloadURL();
    _cache[u] = https;
    return https;
  }

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _loadingBox();
    if (!url.startsWith('gs://')) {
      return Image.network(
        url,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: _err,
        loadingBuilder: _loading,
      );
    }
    return FutureBuilder<String>(
      future: resolve(url),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) return _loadingBox();
        if (snap.hasError) return _err(ctx, null, snap.error);
        final resolved = snap.data ?? '';
        if (resolved.isEmpty) return _loadingBox();
        return Image.network(
          resolved,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: _err,
          loadingBuilder: _loading,
        );
      },
    );
  }

  Widget _err(_, __, ___) => Container(
    color: Colors.black12,
    alignment: Alignment.center,
    child: const Icon(Icons.broken_image),
  );

  Widget _loading(BuildContext _, Widget child, ImageChunkEvent? p) =>
      p == null ? child : _loadingBox();

  static Widget _loadingBox() => Container(
    color: Colors.black12,
    alignment: Alignment.center,
    child: const SizedBox(
      width: 26,
      height: 26,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

class _FullscreenMediaViewer extends StatefulWidget {
  const _FullscreenMediaViewer({required this.urls, this.initialIndex = 0});
  final List<String> urls;
  final int initialIndex;

  @override
  State<_FullscreenMediaViewer> createState() =>
      _FullscreenMediaViewerState();
}

class _FullscreenMediaViewerState extends State<_FullscreenMediaViewer> {
  late final PageController _page;
  late int _index;
  final _transformationControllers = <int, TransformationController>{};

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _page = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _page.dispose();
    for (final c in _transformationControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TransformationController _ctrlFor(int i) =>
      _transformationControllers[i] ??= TransformationController();
  void _resetZoom(int i) => _ctrlFor(i).value = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _page,
              onPageChanged: (i) => setState(() => _index = i),
              itemCount: urls.length,
              itemBuilder: (_, i) {
                final url = urls[i];
                return Center(
                  child: FutureBuilder<String>(
                    future: _NetworkImageMaybeGs.resolve(url),
                    builder: (ctx, snap) {
                      final resolved = snap.data ?? '';
                      if (snap.connectionState != ConnectionState.done ||
                          resolved.isEmpty) {
                        return const SizedBox(
                          width: 46,
                          height: 46,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                          ),
                        );
                      }
                      return GestureDetector(
                        onDoubleTap: () {
                          final m = _ctrlFor(i).value;
                          final isZoomed = m.storage[0] > 1.01;
                          if (isZoomed) {
                            _resetZoom(i);
                          } else {
                            _ctrlFor(i).value =
                            Matrix4.identity()..scale(2.0);
                          }
                        },
                        child: InteractiveViewer(
                          transformationController: _ctrlFor(i),
                          minScale: 1,
                          maxScale: 4,
                          child: Image.network(resolved, fit: BoxFit.contain),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withOpacity(.15),
                ),
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'Cerrar',
              ),
            ),
            if (urls.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    urls.length,
                        (i) => Container(
                      width: 8,
                      height: 8,
                      margin:
                      const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                        i == _index ? Colors.white : Colors.white30,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ==== Tarjetas / contenedores ====
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SectionWrap extends StatelessWidget {
  const _SectionWrap({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).size.width >= 900 ? 24.0 : 16.0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: child,
        ),
      ),
    );
  }
}

// ==== RESUMEN: grilla responsiva y orden fijo ====
class _ResumenItem {
  _ResumenItem({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Color? color;
}

class _ResumenGrid extends StatelessWidget {
  const _ResumenGrid({required this.items});
  final List<_ResumenItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final maxW = c.maxWidth;
      final cols = (maxW ~/ 260).clamp(1, 3); // 1..3 columnas
      final colW = (maxW - (cols - 1) * 12) / cols;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: items.map((it) {
          return SizedBox(
            width: colW,
            child: _StatCard(
              icon: it.icon,
              label: it.label,
              value: it.value,
              onTap: it.onTap,
              color: it.color,
            ),
          );
        }).toList(),
      );
    });
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.primary;
    return Material(
      color: cs.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: c),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
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

// ==== BLOQUE REUSABLE: Mapa + Acerca ====
class _MapAndAcercaRow extends StatelessWidget {
  const _MapAndAcercaRow({required this.obs});
  final Observacion obs;

  @override
  Widget build(BuildContext context) {
    final isTwoCols = MediaQuery.of(context).size.width >= 900;
    final left = _MapaSection(obs: obs);
    final right = _AcercaSection(obs: obs);

    if (isTwoCols) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 16),
          Expanded(child: right),
        ],
      );
    }
    return Column(
      children: [
        left,
        const SizedBox(height: 16),
        right,
      ],
    );
  }
}

// ==== Sección MAPA ====
class _MapaSection extends StatelessWidget {
  const _MapaSection({required this.obs});
  final Observacion obs;

  @override
  Widget build(BuildContext context) {
    final String ubicCorta = obs.displayUbicacionCorta;

    return _SectionCard(
      title: 'Mapa',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (obs.lat != null && obs.lng != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _MiniMapInteractive(
                lat: obs.lat!,
                lng: obs.lng!,
                privacyRadiusMeters: 100,
              ),
            )
          else
            Container(
              height: 160,
              alignment: Alignment.center,
              decoration: _cardBg(context),
              child: const Text('Sin coordenadas'),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_hasStr(ubicCorta) && ubicCorta != '—')
                _StatCard(
                  icon: Icons.place_outlined,
                  label: 'Ubicación',
                  value: ubicCorta,
                ),
              if (obs.lat != null && obs.lng != null)
                Chip(
                  avatar:
                  const Icon(Icons.gps_fixed, size: 18),
                  label: Text(
                    '${obs.lat!.toStringAsFixed(5)}, ${obs.lng!.toStringAsFixed(5)}',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (obs.lat != null && obs.lng != null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.content_copy),
                  label: const Text('Copiar coordenadas'),
                  onPressed: () async {
                    final text =
                        '${obs.lat!.toStringAsFixed(6)}, ${obs.lng!.toStringAsFixed(6)}';
                    await Clipboard.setData(
                      ClipboardData(text: text),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Coordenadas copiadas'),
                        ),
                      );
                    }
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Google Maps'),
                  onPressed: () async {
                    final uri = Uri.parse(
                      'https://www.google.com/maps?q=${obs.lat},${obs.lng}',
                    );
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ==== Sección ACERCA ====
class _AcercaSection extends StatelessWidget {
  const _AcercaSection({required this.obs});
  final Observacion obs;

  @override
  Widget build(BuildContext context) {
    String? _edadFmt(num? v) {
      if (v == null) return null;
      final esUno = v == 1 || v == 1.0;
      return '${v.toString()} ${esUno ? 'año' : 'años'}';
    }

    return _SectionCard(
      title: 'Acerca de',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (obs.especieNombreComun ??
                obs.especieId ??
                'Especie: N/D'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Builder(
            builder: (_) {
              final cient = obs.displayNombreCientifico.trim();
              final show =
                  cient.isNotEmpty && cient != 'Sin especie';
              return show
                  ? Padding(
                padding:
                const EdgeInsets.only(top: 2.0),
                child: Text(
                  cient,
                  softWrap: true,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
                ),
              )
                  : const SizedBox.shrink();
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (_hasStr(obs.taxoClase))
                _StatCard(
                  icon: Icons.category,
                  label: 'Clase',
                  value: obs.taxoClase!,
                ),
              if (_hasStr(obs.taxoOrden))
                _StatCard(
                  icon: Icons.account_tree_outlined,
                  label: 'Orden',
                  value: obs.taxoOrden!,
                ),
              if (_hasStr(obs.taxoFamilia))
                _StatCard(
                  icon: Icons.family_restroom_outlined,
                  label: 'Familia',
                  value: obs.taxoFamilia!,
                ),
              if (obs.edadAproximada != null)
                _StatCard(
                  icon: Icons.cake_outlined,
                  label: 'Edad aproximada',
                  value: _edadFmt(obs.edadAproximada)!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==== Sección NOTAS ====
class _NotasSection extends StatelessWidget {
  const _NotasSection({required this.obs});
  final Observacion obs;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Notas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_hasStr(obs.notas) ? obs.notas! : 'Sin notas'),
          if (_hasStr(obs.rastroDetalle)) ...[
            const SizedBox(height: 12),
            Text(
              'Detalle de rastro',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(obs.rastroDetalle!),
          ],
        ],
      ),
    );
  }
}

// ===== Panel lateral (observador + totales + sparkline) =====
class _MetaPanel extends StatelessWidget {
  const _MetaPanel({required this.obs, this.firstPhoto});
  final Observacion obs;
  final String? firstPhoto;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        _MetaCard(
          title: 'Observador principal',
          userId: obs.uidUsuario,
          displayNameOverride: _orDash(obs.autorNombre),
          fallbackAvatar: firstPhoto,
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                'Totales',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.photo_camera_outlined,
                      size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _hasStr(obs.autorNombre)
                          ? 'Observaciones de ${obs.autorNombre}'
                          : 'Observaciones del usuario',
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant,
                      borderRadius:
                      BorderRadius.circular(8),
                    ),
                    child: const Text('—'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Actividad mensual',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: _SparklineCard(
                  monthValues:
                  _dummyMonthlySeries(obs),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static List<int> _dummyMonthlySeries(Observacion obs) {
    final now = DateTime.now();
    final base = List<int>.filled(12, 40);
    final m = (obs.fechaCaptura ?? now).month - 1;
    base[m] = 90;
    return base;
  }
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({
    required this.title,
    this.userId,
    this.displayNameOverride,
    this.fallbackAvatar,
  });
  final String title;
  final String? userId;
  final String? displayNameOverride;
  final String? fallbackAvatar;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final users =
    FirebaseFirestore.instance.collection('usuarios');

    if (userId == null || userId!.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _UserAvatar(
              userId: null,
              fallback: fallbackAvatar,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _orDash(displayNameOverride),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _UserAvatar(
            userId: userId,
            fallback: fallbackAvatar,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FutureBuilder<
                DocumentSnapshot<Map<String, dynamic>>>(
              future: users.doc(userId).get(),
              builder: (ctx, snap) {
                final data = snap.data?.data();
                final displayName =
                    displayNameOverride ??
                        (data != null
                            ? (data['displayName']
                        as String?)
                            : null) ??
                        '—';
                return Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(
                        color:
                        cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayName,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                        fontWeight:
                        FontWeight.w600,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({this.userId, this.fallback});
  final String? userId;
  final String? fallback;
  @override
  Widget build(BuildContext context) {
    final users =
    FirebaseFirestore.instance.collection('usuarios');

    if (userId == null || userId!.isEmpty) {
      if (_hasStr(fallback)) {
        return FutureBuilder<String>(
          future: _NetworkImageMaybeGs.resolve(fallback!),
          builder: (ctx2, s2) {
            if (s2.connectionState !=
                ConnectionState.done ||
                (s2.data ?? '').isEmpty) {
              return const CircleAvatar(
                radius: 22,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              );
            }
            return CircleAvatar(
              radius: 22,
              backgroundImage:
              NetworkImage(s2.data!),
            );
          },
        );
      }
      return const CircleAvatar(
        radius: 22,
        child: Icon(Icons.person_outline),
      );
    }

    return FutureBuilder<
        DocumentSnapshot<Map<String, dynamic>>>(
      future: users.doc(userId).get(),
      builder: (ctx, snap) {
        String? photo =
        snap.data?.data()?['photoURL']
        as String?;
        photo ??= fallback;
        if (!_hasStr(photo)) {
          return const CircleAvatar(
            radius: 22,
            child: Icon(Icons.person_outline),
          );
        }
        return FutureBuilder<String>(
          future: _NetworkImageMaybeGs.resolve(photo!),
          builder: (ctx2, s2) {
            if (s2.connectionState !=
                ConnectionState.done ||
                (s2.data ?? '').isEmpty) {
              return const CircleAvatar(
                radius: 22,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              );
            }
            return CircleAvatar(
              radius: 22,
              backgroundImage:
              NetworkImage(s2.data!),
            );
          },
        );
      },
    );
  }
}

class _SparklineCard extends StatelessWidget {
  const _SparklineCard({required this.monthValues});
  final List<int> monthValues;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      child: CustomPaint(
        painter: _SparklinePainter(monthValues, cs.primary),
        willChange: false,
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color);
  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final paintLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    final paintFill = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(.15);

    final maxV =
    (values.reduce((a, b) => a > b ? a : b)).clamp(1, 100);
    final stepX = size.width / (values.length - 1);
    final path = Path();
    final pathFill = Path();

    for (int i = 0; i < values.length; i++) {
      final x = i * stepX;
      final y =
          size.height - (values[i] / maxV) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        pathFill.moveTo(x, size.height);
        pathFill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        pathFill.lineTo(x, y);
      }
    }
    pathFill.lineTo(size.width, size.height);
    pathFill.close();
    canvas.drawPath(pathFill, paintFill);
    canvas.drawPath(path, paintLine);
  }

  @override
  bool shouldRepaint(
      covariant CustomPainter oldDelegate) =>
      false;
}

// ===== Proyecto / Info / Mapa helpers =====
class _ProyectoName extends StatelessWidget {
  final String proyectoId;
  const _ProyectoName({required this.proyectoId});

  @override
  Widget build(BuildContext context) {
    final ref =
    FirebaseFirestore.instance.collection('proyectos').doc(proyectoId);
    return FutureBuilder<
        DocumentSnapshot<Map<String, dynamic>>>(
      future: ref.get(),
      builder: (ctx, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const Text('Proyecto: —');
        }
        final nombre =
        (snap.data!.data()?['nombre'] as String?)?.trim();
        return Row(
          children: [
            const Icon(Icons.work_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Proyecto: ${nombre ?? '—'}'),
            ),
          ],
        );
      },
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.5),
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ActionsBar extends StatelessWidget {
  const _ActionsBar({
    required this.obs,
    this.canEdit = false,
    this.canDelete = false,
    this.canSubmit = false,
    this.rejectedAt,
    this.updatedAt,
  });

  final Observacion obs;
  final bool canEdit;
  final bool canDelete;
  final bool canSubmit;
  final DateTime? rejectedAt;
  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    final repo = ObservacionRepository();
    final uidActual = context.read<AuthProvider>().uid;

    final bool tieneId =
    (obs.id != null && obs.id!.isNotEmpty);
    final bool isBorrador =
        obs.estado == EstadosObs.borrador;
    final bool isRechazado =
        obs.estado == EstadosObs.rechazado;

    final bool fueEditadoDespues = isRechazado &&
        rejectedAt != null &&
        updatedAt != null &&
        updatedAt!.isAfter(rejectedAt!);

    final bool puedeEnviarBorrador =
        isBorrador && canSubmit && tieneId;
    final bool puedeReenviar =
        isRechazado && canEdit && fueEditadoDespues && tieneId;

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: (canEdit && tieneId)
              ? () => Navigator.of(context).pushNamed(
            '/observaciones/edit',
            arguments: obs.id!,
          )
              : null,
          icon: const Icon(Icons.edit),
          label: const Text('Editar'),
        ),
        if (isBorrador)
          OutlinedButton.icon(
            onPressed: puedeEnviarBorrador
                ? () async {
              try {
                await repo.enviarAPendiente(
                  obs,
                  uid: uidActual,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Enviado a revisión'),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                    ),
                  );
                }
              }
            }
                : null,
            icon: const Icon(Icons.outgoing_mail),
            label: const Text('Enviar a revisión'),
          ),
        if (isRechazado)
          Tooltip(
            message: fueEditadoDespues
                ? 'Reenviar a revisión'
                : 'Edita la observación después del rechazo para habilitar el reenvío',
            child: OutlinedButton.icon(
              onPressed: puedeReenviar
                  ? () async {
                try {
                  await repo.reenviarRevision(
                    obs,
                    uid: uidActual,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Reenviado a revisión'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                      ),
                    );
                  }
                }
              }
                  : null,
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('Reenviar a revisión'),
            ),
          ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
          ),
          onPressed: (canDelete && tieneId)
              ? () async {
            final ok =
                await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text(
                        'Eliminar observación'),
                    content: Text(
                      isBorrador
                          ? '¿Eliminar tu borrador? Esta acción no se puede deshacer.'
                          : '¿Eliminar esta observación? Esta acción no se puede deshacer.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(ctx, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(ctx, true),
                        child: const Text('Eliminar'),
                      ),
                    ],
                  ),
                ) ??
                    false;
            if (!ok) return;
            try {
              await repo.eliminarObservacion(obs);
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Observación eliminada'),
                  ),
                );
                Navigator.of(context).maybePop();
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            }
          }
              : null,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Eliminar'),
        ),
      ],
    );
  }
}

// ===== Utils visuales / strings =====
BoxDecoration _cardBg(BuildContext context) => BoxDecoration(
  color: Theme.of(context).colorScheme.surface,
  border: Border.all(
    color: Theme.of(context).colorScheme.outlineVariant,
  ),
  borderRadius: BorderRadius.circular(16),
);

bool _hasStr(String? s) => (s ?? '').trim().isNotEmpty;
String _orDash(String? s) =>
    _hasStr(s) ? s!.trim() : '—';

/// ====== Mini-mapa interactivo ======
class _MiniMapInteractive extends StatefulWidget {
  const _MiniMapInteractive({
    required this.lat,
    required this.lng,
    this.privacyRadiusMeters = 100,
  });
  final double lat;
  final double lng;
  final double privacyRadiusMeters;

  @override
  State<_MiniMapInteractive> createState() =>
      _MiniMapInteractiveState();
}

class _MiniMapInteractiveState
    extends State<_MiniMapInteractive> {
  late final fm.MapController _map;

  @override
  void initState() {
    super.initState();
    _map = fm.MapController();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark =
        Theme.of(context).brightness == Brightness.dark;
    final pos = ll.LatLng(widget.lat, widget.lng);

    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;
      final double h =
      w >= 1100 ? 260 : (w >= 700 ? 210 : 180);

      final bool hasMouse = kIsWeb ||
          const {
            TargetPlatform.windows,
            TargetPlatform.linux,
            TargetPlatform.macOS,
          }.contains(defaultTargetPlatform);

      final flags = fm.InteractiveFlag.drag |
      fm.InteractiveFlag.pinchZoom |
      fm.InteractiveFlag.pinchMove |
      fm.InteractiveFlag.doubleTapZoom |
      fm.InteractiveFlag.doubleTapDragZoom |
      (hasMouse
          ? fm.InteractiveFlag.scrollWheelZoom
          : fm.InteractiveFlag.none);

      final tileUrl = isDark
          ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
          : 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';

      final map = fm.FlutterMap(
        mapController: _map,
        options: fm.MapOptions(
          initialCenter: pos,
          initialZoom: 14,
          minZoom: 3,
          maxZoom: 19,
          interactionOptions: fm.InteractionOptions(
            flags: flags,
            scrollWheelVelocity: 0.005,
            rotationThreshold: double.infinity,
          ),
        ),
        children: [
          fm.TileLayer(
            urlTemplate: tileUrl,
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'com.faunadmin.app',
            retinaMode: MediaQuery.of(context)
                .devicePixelRatio >
                1.5,
          ),
          if (widget.privacyRadiusMeters > 0)
            fm.CircleLayer(
              circles: [
                fm.CircleMarker(
                  point: pos,
                  color: cs.primary.withOpacity(.15),
                  borderColor:
                  cs.primary.withOpacity(.35),
                  borderStrokeWidth: 2,
                  radius: widget.privacyRadiusMeters,
                  useRadiusInMeter: true,
                ),
              ],
            ),
          fm.MarkerLayer(
            markers: [
              fm.Marker(
                point: pos,
                width: 38,
                height: 38,
                child: const Icon(
                  Icons.location_on,
                  size: 38,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
        ],
      );

      final wrapped = hasMouse
          ? MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: map,
      )
          : map;
      return SizedBox(
        height: h,
        child: Stack(
          children: [
            wrapped,
            Positioned(
              right: 8,
              top: 8,
              child: Column(
                children: [
                  _MapMiniFab(
                    icon: Icons.add,
                    tooltip: 'Acercar',
                    onTap: () => _map.move(
                      _map.camera.center,
                      (_map.camera.zoom + 1)
                          .clamp(3, 19),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _MapMiniFab(
                    icon: Icons.remove,
                    tooltip: 'Alejar',
                    onTap: () => _map.move(
                      _map.camera.center,
                      (_map.camera.zoom - 1)
                          .clamp(3, 19),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _MapMiniFab extends StatelessWidget {
  const _MapMiniFab({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon),
          ),
        ),
      ),
    );
  }
}

// ======= CONTENEDOR ÚNICO CON TABS =======
class _ObservacionContentCard extends StatelessWidget {
  const _ObservacionContentCard({
    required this.obs,
    required this.fotos,
    required this.canEdit,
    required this.canDelete,
    required this.canSubmit,
    this.blockedReason,
    this.rejectedAt,
    this.updatedAt,
  });

  final Observacion obs;
  final List<String> fotos;
  final bool canEdit, canDelete, canSubmit;
  final String? blockedReason;
  final DateTime? rejectedAt, updatedAt;

  @override
  Widget build(BuildContext context) {
    final isWide =
        MediaQuery.of(context).size.width >= 1100;

    return Container(
      decoration: _cardBg(context),
      padding: const EdgeInsets.all(16),
      child: DefaultTabController(
        length: 5, // Resumen, Mapa, Acerca, Proyecto, Notas
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(
                    'Detalles',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge,
                  ),
                  const Spacer(),
                ],
              ),
            ),

            // Pestañas
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding:
              const EdgeInsets.symmetric(horizontal: 12),
              tabs: const [
                Tab(text: 'Resumen'),
                Tab(text: 'Mapa'),
                Tab(text: 'Acerca de'),
                Tab(text: 'Proyecto'),
                Tab(text: 'Notas'),
              ],
            ),
            const SizedBox(height: 12),

            // Contenido
            ConstrainedBox(
              constraints:
              const BoxConstraints(minHeight: 320),
              child: SizedBox(
                height: 0,
                child: TabBarView(
                  children: [
                    // ===== Resumen (2 cols en web) =====
                    SingleChildScrollView(
                      child: isWide
                          ? Row(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _SectionCard(
                              title: 'Resumen',
                              child: _ResumenGrid(
                                items:
                                _buildResumenItems(
                                    context, obs),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 330,
                            child: _MetaPanel(
                              obs: obs,
                              firstPhoto: fotos
                                  .isNotEmpty
                                  ? fotos.first
                                  : null,
                            ),
                          ),
                        ],
                      )
                          : Column(
                        children: [
                          _SectionCard(
                            title: 'Resumen',
                            child: _ResumenGrid(
                              items:
                              _buildResumenItems(
                                  context, obs),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _MetaPanel(
                            obs: obs,
                            firstPhoto: fotos
                                .isNotEmpty
                                ? fotos.first
                                : null,
                          ),
                        ],
                      ),
                    ),
                    // ===== Mapa =====
                    SingleChildScrollView(
                      child: _MapaSection(obs: obs),
                    ),
                    // ===== Acerca de =====
                    SingleChildScrollView(
                      child: _AcercaSection(obs: obs),
                    ),
                    // ===== Proyecto =====
                    SingleChildScrollView(
                      child: _buildProyectoBlock(obs),
                    ),
                    // ===== Notas =====
                    SingleChildScrollView(
                      child: _NotasSection(obs: obs),
                    ),
                  ],
                ),
              ),
            ),
            // Banner + Acciones
            if (blockedReason != null) ...[
              const SizedBox(height: 16),
              _InfoBanner(text: blockedReason!),
            ],
            const SizedBox(height: 16),
            _ActionsBar(
              obs: obs,
              canEdit: canEdit,
              canDelete: canDelete,
              canSubmit: canSubmit,
              rejectedAt: rejectedAt,
              updatedAt: updatedAt,
            ),
          ],
        ),
      ),
    );
  }

  List<_ResumenItem> _buildResumenItems(
      BuildContext context, Observacion obs) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final fecha =
        obs.fechaCaptura ?? obs.createdAt;
    final ubicCorta = obs.displayUbicacionCorta;

    return [
      _ResumenItem(
        icon: Icons.verified,
        label: 'Estado',
        value: obs.estadoLabel, // getter en el modelo
        color: DetalleObservacionScreen._estadoColor(
          context,
          obs.estado,
        ),
      ),
      if (fecha != null)
        _ResumenItem(
          icon: Icons.event,
          label: 'Fecha',
          value: df.format(fecha),
        ),
      if (_hasStr(ubicCorta) && ubicCorta != '—')
        _ResumenItem(
          icon: Icons.place_outlined,
          label: 'Ubicación',
          value: ubicCorta,
        ),
      if (obs.lat != null && obs.lng != null)
        _ResumenItem(
          icon: Icons.gps_fixed,
          label: 'Coordenadas',
          value:
          '${obs.lat!.toStringAsFixed(5)}, ${obs.lng!.toStringAsFixed(5)}',
          onTap: () async {
            final t =
                '${obs.lat!.toStringAsFixed(6)}, ${obs.lng!.toStringAsFixed(6)}';
            await Clipboard.setData(ClipboardData(text: t));
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(
                const SnackBar(
                  content: Text('Coordenadas copiadas'),
                ),
              );
            }
          },
        ),
      if (obs.altitud != null)
        _ResumenItem(
          icon: Icons.terrain,
          label: 'Altitud',
          value:
          '${obs.altitud!.toStringAsFixed(1)} m',
        ),
      if (_hasStr(obs.condicionAnimal))
        _ResumenItem(
          icon: Icons.pets,
          label: 'Condición',
          value: obs.displayCondicion, // getter modelo
        ),
      if (_hasStr(obs.rastroTipo))
        _ResumenItem(
          icon: Icons.fingerprint,
          label: 'Rastro',
          value: obs.displayRastro, // getter modelo
        ),
      if (obs.edadAproximada != null)
        _ResumenItem(
          icon: Icons.cake_outlined,
          label: 'Edad aprox.',
          value:
          '${obs.edadAproximada} ${obs.edadAproximada == 1 ? 'año' : 'años'}',
        ),
      if (_hasStr(obs.lugarNombre))
        _ResumenItem(
          icon: Icons.label_outline,
          label: 'Lugar',
          value: obs.lugarNombre!,
        ),
      if (_hasStr(obs.lugarTipo))
        _ResumenItem(
          icon: Icons.terrain_outlined,
          label: 'Tipo de lugar',
          value: obs.lugarTipo!,
        ),
      if (_hasStr(obs.ubicRegion))
        _ResumenItem(
          icon: Icons.public,
          label: 'Región',
          value: obs.ubicRegion!,
        ),
      if (_hasStr(obs.ubicDistrito))
        _ResumenItem(
          icon: Icons.account_balance,
          label: 'Distrito',
          value: obs.ubicDistrito!,
        ),
    ];
  }

  Widget _buildProyectoBlock(Observacion obs) {
    if (_hasStr(obs.proyectoNombre) ||
        _hasStr(obs.idProyecto)) {
      return _SectionCard(
        title: 'Proyecto',
        child: _hasStr(obs.proyectoNombre)
            ? Row(
          children: [
            const Icon(Icons.work_outline,
                size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Proyecto: ${obs.proyectoNombre}',
              ),
            ),
          ],
        )
            : _ProyectoName(
          proyectoId: obs.idProyecto!,
        ),
      );
    }
    return _SectionCard(
      title: 'Proyecto',
      child: Row(
        children: const [
          Icon(Icons.work_outline, size: 18),
          SizedBox(width: 8),
          Expanded(child: Text('Sin proyecto')),
        ],
      ),
    );
  }
}
