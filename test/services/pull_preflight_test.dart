import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:geoform_app/services/api_service.dart';
import 'package:geoform_app/services/connectivity_service.dart';
import 'package:geoform_app/services/pull_preflight.dart';
import 'package:geoform_app/services/sync_service.dart';

class _FakeApi implements ApiService {
  final http.Response resp;
  int calls = 0;
  _FakeApi(this.resp);

  @override
  Future<http.Response> get(String endpoint,
      {Map<String, String>? headers, Map<String, dynamic>? queryParameters}) async {
    calls++;
    return resp;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeConn implements ConnectivityService {
  final bool reachable;
  _FakeConn(this.reachable);

  @override
  Future<bool> checkServerReachable() async => reachable;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

http.Response _count(int n, {int status = 200}) =>
    http.Response(jsonEncode({'total_count': n}), status);

SyncService _sync(ApiService api, ConnectivityService conn) =>
    SyncService.forTest(apiService: api, connectivity: conn);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline → status offline, server never queried', () async {
    final api = _FakeApi(_count(5));
    final r = await _sync(api, _FakeConn(false)).preflightPull('p1');
    expect(r.status, PullPreflightStatus.offline);
    expect(api.calls, 0);
  });

  test('reachable + count 0 → status empty', () async {
    final r = await _sync(_FakeApi(_count(0)), _FakeConn(true)).preflightPull('p1');
    expect(r.status, PullPreflightStatus.empty);
    expect(r.count, 0);
  });

  test('count below threshold → ready, no large warning', () async {
    final r = await _sync(_FakeApi(_count(500)), _FakeConn(true)).preflightPull('p1');
    expect(r.status, PullPreflightStatus.ready);
    expect(r.count, 500);
    expect(r.warnLarge, isFalse);
  });

  test('count above 1000 → ready with large warning', () async {
    final r = await _sync(_FakeApi(_count(1500)), _FakeConn(true)).preflightPull('p1');
    expect(r.status, PullPreflightStatus.ready);
    expect(r.count, 1500);
    expect(r.warnLarge, isTrue);
  });

  test('exactly 1000 → not a large warning (strictly greater)', () async {
    final r = await _sync(_FakeApi(_count(1000)), _FakeConn(true)).preflightPull('p1');
    expect(r.warnLarge, isFalse);
  });

  test('server error during count → status error', () async {
    final r = await _sync(_FakeApi(_count(0, status: 500)), _FakeConn(true))
        .preflightPull('p1');
    expect(r.status, PullPreflightStatus.error);
    expect(r.message, isNotNull);
  });
}
