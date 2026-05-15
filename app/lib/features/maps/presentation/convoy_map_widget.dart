import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

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
