import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/repository.dart';

void main() {
  group('Repository.includeMenuExportMetadataForSave', () {
    test('local saves include metadata during menu import', () {
      expect(
        Repository.includeMenuExportMetadataForSave(
          fromMenuImport: true,
          remoteDbEnabled: false,
          remoteMetadataSupported: false,
        ),
        isTrue,
      );
    });

    test('remote import skips metadata until VPS reports support', () {
      expect(
        Repository.includeMenuExportMetadataForSave(
          fromMenuImport: true,
          remoteDbEnabled: true,
          remoteMetadataSupported: false,
        ),
        isFalse,
      );
      expect(
        Repository.includeMenuExportMetadataForSave(
          fromMenuImport: true,
          remoteDbEnabled: true,
          remoteMetadataSupported: true,
        ),
        isTrue,
      );
    });

    test('manual saves never include import metadata', () {
      expect(
        Repository.includeMenuExportMetadataForSave(
          fromMenuImport: false,
          remoteDbEnabled: false,
          remoteMetadataSupported: true,
        ),
        isFalse,
      );
    });
  });
}
