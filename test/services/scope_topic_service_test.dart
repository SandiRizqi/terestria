import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/services/scope_topic_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('syncTopicsInBackground selesai & persist walau FCM tak tersedia (test env)',
      () async {
    final svc = ScopeTopicService();
    // Firebase tidak diinisialisasi di test → subscribe gagal per-topic tapi
    // DITELAN di dalam service; state scope tetap tersimpan.
    await svc.syncTopicsInBackground([1, 2]);
    expect(await svc.getSubscribedScopes(), [1, 2]);
  });

  test('operasi background berjalan SERIAL (hasil akhir = panggilan terakhir)',
      () async {
    final svc = ScopeTopicService();
    // Tanpa await di antara panggilan — meniru logout→login cepat.
    svc.unsubscribeAllInBackground();
    svc.syncTopicsInBackground([7]);
    final last = svc.syncTopicsInBackground([7, 9]);
    await last; // menunggu antrean terakhir = semua sebelumnya sudah selesai
    expect(await svc.getSubscribedScopes(), [7, 9]);
  });

  test('error di satu operasi tidak mematikan antrean berikutnya', () async {
    final svc = ScopeTopicService();
    svc.unsubscribeAllInBackground(); // apapun hasilnya
    await svc.syncTopicsInBackground([3]);
    expect(await svc.getSubscribedScopes(), [3]);
  });
}
