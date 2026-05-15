import 'package:crew_link/core/models/convoy_member.dart';
import 'package:crew_link/core/models/gps_update.dart';

typedef MemberPosition = ({ConvoyMember member, GpsUpdate position});

/// Abstraktion für Karten-Datenquellen (Tiles, Member-Positionen).
/// Implementierung folgt im Live-Map-Milestone.
abstract interface class MapRepository {
  /// Stream aller aktuellen Member-Positionen im Konvoi.
  Stream<List<MemberPosition>> memberPositions(String convoyId);
}
