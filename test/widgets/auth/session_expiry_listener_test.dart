import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/auth_service.dart';
import 'package:geoform_app/widgets/auth/session_expiry_listener.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      '401 → dialog login ulang (data tetap); Later menunda; '
      'requestReLogin memunculkan lagi', (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'token-1',
      'user_data': '{"id":"surveyor","username":"surveyor"}',
      'is_logged_in': true,
    });
    final auth = AuthService()..debugResetSessionExpiry();
    await auth.getToken(); // isi cache token seperti saat app berjalan

    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      builder: (context, child) => SessionExpiryListener(
        navigatorKey: navKey,
        auth: auth,
        child: child!,
      ),
      home: const Scaffold(body: Text('home')),
    ));

    auth.reportUnauthorized('/mobile/geodata/');
    await tester.pumpAndSettle();
    expect(find.text('Session expired'), findsOneWidget);
    expect(find.text('surveyor'), findsOneWidget);
    expect(auth.isSessionExpired, isTrue);

    // Sandi kosong → pesan validasi, dialog tetap terbuka.
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Enter your password.'), findsOneWidget);

    // "Later": dialog tertutup, sinyal 401 berikutnya ditunda.
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Session expired'), findsNothing);
    expect(auth.isSessionExpired, isFalse);
    expect(auth.tokenRejected, isTrue);

    auth.reportUnauthorized('/mobile/projects/');
    await tester.pumpAndSettle();
    expect(find.text('Session expired'), findsNothing);

    // Tombol "Sign in again" di UI sync → dialog muncul walau ditunda.
    auth.requestReLogin();
    await tester.pumpAndSettle();
    expect(find.text('Session expired'), findsOneWidget);

    auth.debugResetSessionExpiry();
  });
}
