import 'package:shilpa_api/api.dart';
import 'package:shilpa_api/store.dart';

Future<void> main() async {
  final store = await DbStore.open();
  await serve(store);
}
