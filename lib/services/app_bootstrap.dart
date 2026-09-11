import 'package:foodstock/database/api_config.dart';
import 'package:foodstock/database/database_helper.dart';
import 'package:foodstock/services/auth_session.dart';
import 'package:foodstock/services/remote_capabilities.dart';
import 'package:foodstock/services/repository.dart';

/// Fast path before the first frame: restore saved session from device storage.
class AppBootstrap {
  static Future<AuthSession?> runImmediateInit() async {
    final session = await AuthSession.load();
    if (session != null) {
      Repository.instance.bindSession(
        role: session.role,
        locationId: session.locationId,
        locationName: session.locationName,
      );
    }
    return session;
  }

  /// Connect to the shared VPS database and seed default users/locations.
  ///
  /// Runs in the background after login/shell is visible. Never block the
  /// first frame on this call.
  static Future<void> connectRemoteDatabase() async {
    await RemoteCapabilities.refresh();
    await DBHelper.instance.verifyRemoteConnection();
    await Repository.instance.ensureDefaultUsers();
  }

  /// Heavier work that can run after login/shell is visible.
  ///
  /// Menu import is never run here — locations seed their catalog manually
  /// via Menu Items -> Import CSV/Excel. Location stock row sync also runs
  /// here so large catalogs do not block the login screen.
  static Future<void> runDeferredInit() async {
    if (!ApiConfig.enabled) {
      await DBHelper.instance.database;
    }
    await Repository.instance.ensureStandardUnits();
    await Repository.instance.ensureDefaultCategories();
    await Repository.instance.consolidateMenuCategories();
    await Repository.instance.ensureLocationStockRows();
    await Repository.instance.writeOffExpiredStock();
  }
}
