import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/screens/project/create_project_screen.dart';
import 'package:geoform_app/services/connectivity_service.dart';
import 'package:geoform_app/theme/app_theme.dart';
import 'package:geoform_app/theme/light_app_bar.dart';

/// AppBar terang halaman project: ikon (kembali, aksi, menu) dan judul harus
/// gelap. Tema app memasang iconTheme & titleTextStyle putih secara eksplisit,
/// yang mengalahkan `foregroundColor` — dulu tombol jadi tak terlihat.

Color? _iconColor(WidgetTester tester, IconData icon) =>
    tester.widget<RichText>(
      find.descendant(of: find.byIcon(icon), matching: find.byType(RichText)),
    ).text.style?.color;

Color? _textColor(WidgetTester tester, String text) =>
    tester.widget<RichText>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)),
    ).text.style?.color;

void main() {
  testWidgets('dengan tema app: ikon kembali, aksi, menu, dan judul gelap',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: const Scaffold(body: Text('home')),
    ));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: lightAppBar(
          title: const Text('Projects'),
          actions: [
            IconButton(icon: const Icon(Icons.download_rounded), onPressed: () {}),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              itemBuilder: (_) => const [],
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(_iconColor(tester, Icons.arrow_back), AppTheme.textPrimary);
    expect(_iconColor(tester, Icons.download_rounded), AppTheme.textPrimary);
    expect(_iconColor(tester, Icons.more_vert), AppTheme.textPrimary);
    expect(_textColor(tester, 'Projects'), AppTheme.textPrimary);
  });

  testWidgets('layar New project: ✕ dan judul terlihat (gelap)', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: const CreateProjectScreen(),
    ));
    await tester.pump();

    expect(_iconColor(tester, Icons.close_rounded), AppTheme.textPrimary);
    expect(_textColor(tester, 'New project'), AppTheme.textPrimary);

    await tester.pumpWidget(const SizedBox());
    ConnectivityService().stopMonitoring();
    await tester.pump(const Duration(seconds: 6));
  });
}
