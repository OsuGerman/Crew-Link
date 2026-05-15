import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/theme/app_theme.dart';
import '../application/maps_providers.dart';
import '../domain/map_viewport.dart';

const _selfPinColor = '#1565C0';
const _otherPinColor = '#2E7D32';
const _labelMaxChars = 8;
const _sourceId = 'convoy-members';
const _circleLayerId = 'convoy-circles';
const _labelLayerId = 'convoy-labels';
const _styleUrl = 'https://tiles.openfreemap.org/styles/liberty';
const _circleRadius = 12.0;
const _labelTextSize = 9.0;
const _strokeWidth = 2.0;
const _strokeOpacity = 1.0;
const _strokeColor = '#FFFFFF';
const _fitPadding = 80.0;

class ConvoyMapWidget extends ConsumerStatefulWidget {
  const ConvoyMapWidget({super.key});

  @override
  ConsumerState<ConvoyMapWidget> createState() => _ConvoyMapWidgetState();
}

class _ConvoyMapWidgetState extends ConsumerState<ConvoyMapWidget> {
  MapLibreMapController? _mapController;
  late final MapViewport _initialViewport;
  bool _styleLoaded = false;
  List<MemberMarker> _pending = const [];

  @override
  void initState() {
    super.initState();
    _initialViewport = ref.read(liveViewportProvider);
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
  }

  Future<void> _onStyleLoaded() async {
    final MapLibreMapController? ctrl = _mapController;
    if (ctrl == null) return;

    await ctrl.addGeoJsonSource(_sourceId, _buildGeoJson([]));

    await ctrl.addCircleLayer(
      _sourceId,
      _circleLayerId,
      const CircleLayerProperties(
        circleRadius: _circleRadius,
        circleColor: ['get', 'pinColor'],
        circleStrokeWidth: _strokeWidth,
        circleStrokeColor: _strokeColor,
        circleStrokeOpacity: _strokeOpacity,
      ),
    );

    await ctrl.addSymbolLayer(
      _sourceId,
      _labelLayerId,
      const SymbolLayerProperties(
        textField: ['get', 'label'],
        textSize: _labelTextSize,
        textColor: _strokeColor,
        textAllowOverlap: true,
        textIgnorePlacement: true,
        textAnchor: 'center',
      ),
    );

    if (mounted) setState(() => _styleLoaded = true);
    if (_pending.isNotEmpty) {
      await _syncMarkers(_pending);
    }
  }

  Future<void> _syncMarkers(List<MemberMarker> markers) async {
    final ctrl = _mapController;
    if (ctrl == null || !_styleLoaded) {
      _pending = markers;
      return;
    }
    _pending = const [];
    await ctrl.setGeoJsonSource(_sourceId, _buildGeoJson(markers));
  }

  Map<String, dynamic> _buildGeoJson(List<MemberMarker> markers) => {
    'type': 'FeatureCollection',
    'features': [
      for (final m in markers)
        {
          'type': 'Feature',
          'id': m.memberId,
          'geometry': {
            'type': 'Point',
            'coordinates': [m.position.longitude, m.position.latitude],
          },
          'properties': {
            'label': m.memberId.length > _labelMaxChars
                ? m.memberId.substring(0, _labelMaxChars)
                : m.memberId,
            'pinColor': m.isSelf ? _selfPinColor : _otherPinColor,
          },
        },
    ],
  };

  Future<void> _fitAll() async {
    final ctrl = _mapController;
    if (ctrl == null) return;
    final markers = ref.read(memberMarkersProvider);
    if (markers.isEmpty) return;

    if (markers.length == 1) {
      final pos = markers.first.position;
      await ctrl.animateCamera(CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)));
      return;
    }

    final lats = markers.map((m) => m.position.latitude);
    final lngs = markers.map((m) => m.position.longitude);
    await ctrl.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
          northeast: LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
        ),
        left: _fitPadding, top: _fitPadding, right: _fitPadding, bottom: _fitPadding,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // MapLibre auf Flutter Web hat Style-Load-Race-Conditions auf 3.41+
    // (style-Callback feuert nie, Layer-Init lädt unendlich). Für die
    // Web-Preview rendern wir einen Platzhalter; native bleibt unverändert.
    if (kIsWeb) {
      return const _WebMapPlaceholder();
    }
    final scheme = Theme.of(context).colorScheme;
    ref.listen(memberMarkersProvider, (_, next) => _syncMarkers(next));
    final markers = ref.watch(memberMarkersProvider);

    return Stack(
      children: [
        MapLibreMap(
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: _onStyleLoaded,
          initialCameraPosition: CameraPosition(
            target: LatLng(_initialViewport.centerLat, _initialViewport.centerLng),
            zoom: _initialViewport.zoomLevel,
          ),
          styleString: _styleUrl,
        ),
        if (!_styleLoaded || markers.isEmpty)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    _styleLoaded ? 'Warte auf GPS-Daten …' : 'Karte lädt …',
                    style: TextStyle(color: scheme.onSurface, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          right: 12,
          bottom: 24,
          child: FloatingActionButton.small(
            key: const ValueKey('fit-all-fab'),
            tooltip: 'Alle anzeigen',
            onPressed: _fitAll,
            child: const Icon(Icons.center_focus_strong),
          ),
        ),
      ],
    );
  }
}

/// Web-Preview-Stand-In für die echte Maplibre-Karte. Echte Karten-
/// Integration läuft nur auf iOS/Android — Web hat in maplibre_gl 0.26
/// Race-Conditions beim Style-Loading.
class _WebMapPlaceholder extends ConsumerWidget {
  const _WebMapPlaceholder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final markers = ref.watch(memberMarkersProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.map_outlined,
                color: AppColors.orange,
                size: 36,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Live-Karte',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${markers.length} Mitglied${markers.length == 1 ? '' : 'er'} live · '
              'Native-Map auf iOS/Android',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(
                  color: AppColors.surfaceOutline,
                  width: 0.6,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline,
                      color: AppColors.orange, size: 18),
                  SizedBox(width: AppSpacing.sm),
                  Text(
                    'Im echten Build: MapLibre + GPS-Pins',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
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
