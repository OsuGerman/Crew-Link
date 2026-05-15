import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vehicle_mod.dart';
import '../../../core/models/vehicle_profile.dart';
import '../../convoy/application/convoy_providers.dart';
import '../data/vehicle_api.dart';

/// HTTP client for the `/vehicles/me` REST resource. Shares the
/// `httpClientProvider` from convoy_providers so test overrides on the
/// http client flow through both feature areas.
final vehicleApiProvider = Provider<VehicleApi>((ref) {
  return VehicleApi(
    config: ref.watch(apiConfigProvider),
    client: ref.watch(httpClientProvider),
  );
});

/// Current user's primary vehicle. Hydrates from `GET /vehicles/me` on
/// first watch; saves go through `PUT /vehicles/me`. The async value
/// `data(null)` means "user has no vehicle yet" — distinct from
/// `loading` and `error` states.
class MyVehicleNotifier extends AsyncNotifier<VehicleProfile?> {
  @override
  Future<VehicleProfile?> build() async {
    final api = ref.read(vehicleApiProvider);
    final token = ref.read(authTokenProvider);
    return api.getMyVehicle(authToken: token);
  }

  Future<VehicleProfile> save({
    required String make,
    required String model,
    int? year,
    String? color,
    int? powerKw,
    String? drivetrain,
    int? displacement,
    String? transmissionType,
    List<VehicleMod> mods = const <VehicleMod>[],
  }) async {
    final api = ref.read(vehicleApiProvider);
    final token = ref.read(authTokenProvider);
    state = const AsyncValue<VehicleProfile?>.loading();
    final saved = await api.putMyVehicle(
      authToken: token,
      make: make,
      model: model,
      year: year,
      color: color,
      powerKw: powerKw,
      drivetrain: drivetrain,
      displacement: displacement,
      transmissionType: transmissionType,
      mods: mods,
    );
    state = AsyncValue.data(saved);
    return saved;
  }

  Future<void> clear() async {
    final api = ref.read(vehicleApiProvider);
    final token = ref.read(authTokenProvider);
    state = const AsyncValue<VehicleProfile?>.loading();
    await api.deleteMyVehicle(authToken: token);
    state = const AsyncValue<VehicleProfile?>.data(null);
  }
}

final myVehicleProvider =
    AsyncNotifierProvider<MyVehicleNotifier, VehicleProfile?>(
  MyVehicleNotifier.new,
);
