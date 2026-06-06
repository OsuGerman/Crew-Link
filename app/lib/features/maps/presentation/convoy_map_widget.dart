import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/theme/app_theme.dart';
import '../../convoy/application/convoy_providers.dart';
import '../../convoy/application/waypoint_providers.dart';
import '../../convoy/domain/convoy_standings.dart';
import '../../convoy/domain/waypoint.dart';
import '../../convoy/domain/waypoint_tour.dart';
import '../application/maps_providers.dart';
import '../domain/map_viewport.dart';
import '../domain/route_geojson.dart';

const _selfPinColor = '#1565C0';
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

// Leader-route overlay: a line through the stops + numbered stop pins, added
// before the member layers so live positions stay drawn on top.
const _routeSourceId = 'convoy-route';
const _routeLineLayerId = 'convoy-route-line';
const _routeStopLayerId = 'convoy-route-stops';
const _routeStopLabelLayerId = 'convoy-route-stop-labels';
const _routeColor = '#FF6B35';
const _routeStopColor = '#9E4A1E';
const _routeLineWidth = 4.0;
const _routeStopRadius = 13.0;

/// Map member-pin colour for a green/yellow/red gap tier.
String _tierHex(GapTier t) => switch (t) {
      GapTier.green => '#22C55E',
      GapTier.yellow => '#FFC53D',
      GapTier.red => '#E94560',
    };

class ConvoyMapWidget extends ConsumerStatefulWidget {
  const ConvoyMapWidget({super.key});

  @override
  ConsumerState<ConvoyMapWidget> createState() => _ConvoyMapWidgetState();
}

class _ConvoyMapWidgetState extends ConsumerState<ConvoyMapWidget> {
  MapLibreMapController? _mapController;
  late final MapViewport _initialViewport;
  bool _styleLoaded = false;
  int _fittedCount = 0;

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

    // Route layers first → drawn beneath the live member markers.
    await ctrl.addGeoJsonSource(
      _routeSourceId,
      buildRouteGeoJson(WaypointTour.empty),
    );
    await ctrl.addLineLayer(
      _routeSourceId,
      _routeLineLayerId,
      const LineLayerProperties(
        lineColor: _routeColor,
        lineWidth: _routeLineWidth,
        lineOpacity: 0.85,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
    await ctrl.addCircleLayer(
      _routeSourceId,
      _routeStopLayerId,
      const CircleLayerProperties(
        circleRadius: _routeStopRadius,
        circleColor: [
          'case',
          ['get', 'isCurrent'],
          _routeColor,
          _routeStopColor,
        ],
        circleStrokeWidth: _strokeWidth,
        circleStrokeColor: _strokeColor,
      ),
    );
    await ctrl.addSymbolLayer(
      _routeSourceId,
      _routeStopLabelLayerId,
      const SymbolLayerProperties(
        textField: ['get', 'label'],
        textSize: _labelTextSize,
        textColor: _strokeColor,
        // OpenFreeMap serves "Noto Sans", not the MapLibre default "Open Sans"
        // (which 404s the glyph range → labels never render).
        textFont: ['Noto Sans Regular'],
        textAllowOverlap: true,
        textIgnorePlacement: true,
        textAnchor: 'center',
      ),
    );

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
        // OpenFreeMap serves "Noto Sans", not the MapLibre default "Open Sans"
        // (which 404s the glyph range → labels never render).
        textFont: ['Noto Sans Regular'],
        textAllowOverlap: true,
        textIgnorePlacement: true,
        textAnchor: 'center',
      ),
    );

    if (mounted) setState(() => _styleLoaded = true);
    // Render the CURRENT markers + route immediately: ref.listen only fires on
    // change, so a stationary self (no GPS delta) would otherwise never appear.
    await _syncMarkers(ref.read(memberMarkersProvider));
    await _syncRoute(ref.read(tourProvider));
  }

  Future<void> _syncMarkers(List<MemberMarker> markers) async {
    final ctrl = _mapController;
    if (ctrl == null || !_styleLoaded) return;
    await ctrl.setGeoJsonSource(_sourceId, _buildGeoJson(markers));
    // (Re-)fit whenever a NEW member appears, so the self pin shows at a usable
    // zoom the first time and a colleague who just came online is brought into
    // view instead of being left off-screen.
    if (markers.isNotEmpty && markers.length > _fittedCount) {
      _fittedCount = markers.length;
      await _fitAll();
    }
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
            'label': m.ordinal > 0 ? '${m.ordinal}' : '',
            'pinColor': m.isSelf ? _selfPinColor : _tierHex(m.tier),
          },
        },
    ],
  };

  Future<void> _syncRoute(WaypointTour tour) async {
    final ctrl = _mapController;
    if (ctrl == null || !_styleLoaded) return;
    await ctrl.setGeoJsonSource(_routeSourceId, buildRouteGeoJson(tour));
  }

  /// Leader-only: tapping the map opens a quick name prompt and appends a stop
  /// at the tapped coordinate. The tour syncs to every member via the socket.
  Future<void> _promptAddStop(LatLng latLng) async {
    final controller = TextEditingController();
    final selfId = ref.read(selfMemberIdProvider);
    final defaultLabel = 'Stopp ${ref.read(tourProvider).length + 1}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stopp setzen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: defaultLabel,
            labelText: 'Name des Stopps',
          ),
          onSubmitted: (_) => Navigator.of(ctx).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Setzen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final label = controller.text.trim();
    ref.read(tourProvider.notifier).addStop(
          Waypoint(
            latitude: latLng.latitude,
            longitude: latLng.longitude,
            label: label.isEmpty ? defaultLabel : label,
            setBy: selfId,
            setAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<void> _fitAll() async {
    final ctrl = _mapController;
    if (ctrl == null) return;
    final markers = ref.read(memberMarkersProvider);
    if (markers.isEmpty) return;

    if (markers.length == 1) {
      final pos = markers.first.position;
      // Zoom to a street-level view, not just recenter — otherwise a lone self
      // pin keeps the far-out initial zoom and the map looks "way too small".
      await ctrl.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15.5),
      );
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
    ref.listen(tourProvider, (_, next) => _syncRoute(next));
    final markers = ref.watch(memberMarkersProvider);
    final isLeader = ref.watch(selfIsLeaderProvider);

    return Stack(
      children: [
        MapLibreMap(
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: _onStyleLoaded,
          onMapClick:
              isLeader ? (_, latLng) => _promptAddStop(latLng) : null,
          // Native location puck — the guaranteed blue "you are here" dot,
          // independent of the GeoJSON member layer.
          myLocationEnabled: true,
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
        if (isLeader)
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app_rounded,
                      size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Tippe auf die Karte für einen Stopp',
                    style: TextStyle(fontSize: 12, color: scheme.onSurface),
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
