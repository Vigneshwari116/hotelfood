import 'package:flutter/foundation.dart';
import 'package:foodstock/database/api_config.dart';
import 'package:foodstock/database/database_helper.dart';
import 'package:foodstock/services/app_bootstrap.dart';

/// Tracks background VPS connectivity without blocking the first UI frame.
class ShopServerConnection extends ChangeNotifier {
  ShopServerConnection._();

  static final ShopServerConnection instance = ShopServerConnection._();

  bool connecting = false;
  bool ready = false;
  String? error;

  bool get needsRemoteConnection => ApiConfig.enabled;

  String get statusMessage {
    if (!needsRemoteConnection) {
      return 'Ready';
    }
    if (connecting) {
      return 'Connecting to shop server at ${ApiConfig.url}...';
    }
    if (error != null) {
      return error!;
    }
    if (ready) {
      return 'Connected to shop server';
    }
    return 'Waiting to connect to shop server...';
  }

  Future<void> connect() async {
    if (!needsRemoteConnection) {
      connecting = false;
      ready = true;
      error = null;
      notifyListeners();
      try {
        await AppBootstrap.connectRemoteDatabase();
      } catch (e) {
        ready = false;
        error = _friendlyError(e);
        notifyListeners();
      }
      return;
    }

    connecting = true;
    ready = false;
    error = null;
    notifyListeners();

    try {
      await DBHelper.instance.reconnect();
      await AppBootstrap.connectRemoteDatabase();
      ready = true;
      error = null;
    } catch (e) {
      ready = false;
      error = _friendlyError(e);
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  String _friendlyError(Object e) {
    final text = e.toString();
    if (text.contains('TimeoutException') ||
        text.contains('Cannot reach the shop server')) {
      return 'Cannot reach the shop server at ${ApiConfig.url}. '
          'Check the device internet connection and tap Retry.';
    }
    return text;
  }
}
