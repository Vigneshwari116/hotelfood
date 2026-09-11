import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:foodstock/database/api_config.dart';
import 'package:foodstock/services/repository.dart';

/// Detects optional VPS features (e.g. menu export metadata columns).
class RemoteCapabilities {
  RemoteCapabilities._();

  static Future<void> refresh() async {
    if (!ApiConfig.enabled) {
      Repository.remoteMenuExportMetadataSupported = true;
      return;
    }

    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.url}/health'))
          .timeout(ApiConfig.requestTimeout);
      if (response.statusCode != 200) {
        Repository.remoteMenuExportMetadataSupported = false;
        return;
      }
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        Repository.remoteMenuExportMetadataSupported =
            body['menu_export_metadata'] == true;
        return;
      }
    } catch (_) {
      // Older servers without the flag — import still works without metadata.
    }
    Repository.remoteMenuExportMetadataSupported = false;
  }
}
