import 'package:foodstock/database/database_helper.dart';
import 'package:foodstock/services/auth_session.dart';
import 'package:foodstock/services/repository.dart';

/// Fast path before the first frame: open DB, seed users, restore session.
class AppBootstrap {
  static Future<AuthSession?> runEssentialInit() async {
    await DBHelper.instance.appDb;
    await Repository.instance.ensureDefaultUsers();
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

  /// Heavier work that can run after login/shell is visible.
  ///
  /// Menu import is never run here — locations seed their catalog manually
  /// via Menu Items -> Import CSV/Excel. Location stock row sync also runs
  /// here so large catalogs do not block the login screen.
  static Future<void> runDeferredInit() async {
    await Repository.instance.ensureStandardUnits();
    await Repository.instance.ensureDefaultCategories();
    await Repository.instance.consolidateMenuCategories();
    await Repository.instance.ensureLocationStockRows();
    await Repository.instance.writeOffExpiredStock();
  }
}
