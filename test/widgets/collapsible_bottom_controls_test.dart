import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/screens/data_collection/data_collection_screen.dart'
    show CollectionMode;
import 'package:geoform_app/screens/data_collection/widgets/collapsible_bottom_controls.dart';
import 'package:geoform_app/theme/app_theme.dart';

/// Panel kontrol layar koleksi, diuji dengan tema app asli (padding tombol
/// tema membuat tombol 56, dulu tak terhitung sehingga baris bawah terpotong)
/// di layar seukuran iPhone 390×844.
///
/// Kartu mengambang di atas bilah navigasi / home indicator: di bawahnya peta,
/// bukan pita putih; isi tak pernah terpotong; bisa disembunyikan lewat
/// tombol, ketuk pegangan, atau geser cepat.

const _screen = Size(390, 844);

class _Host extends StatefulWidget {
  final GeometryType type;
  final CollectionMode mode;
  final bool isTracking;
  final bool expanded;
  final ValueChanged<double>? onHeight;

  const _Host({
    required this.type,
    required this.mode,
    required this.isTracking,
    required this.expanded,
    this.onHeight,
  });

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool _expanded = widget.expanded;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(children: [
          const Positioned.fill(child: ColoredBox(color: Colors.blueGrey)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CollapsibleBottomControls(
              isExpanded: _expanded,
              onToggleExpanded: () => setState(() => _expanded = !_expanded),
              geometryType: widget.type,
              collectionMode: widget.mode,
              isTracking: widget.isTracking,
              isPaused: false,
              collectedPoints: const [],
              onToggleTracking: () {},
              onTogglePause: () {},
              onAddPoint: () {},
              onUndoPoint: () {},
              onClearPoints: () {},
              onHeightChanged: widget.onHeight,
            ),
          ),
        ]),
      );
}

Future<void> _pump(
  WidgetTester tester, {
  double inset = 34,
  GeometryType type = GeometryType.polygon,
  CollectionMode mode = CollectionMode.tracking,
  bool isTracking = false,
  bool expanded = true,
  ValueChanged<double>? onHeight,
}) async {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = FakeViewPadding(bottom: inset * 3);
  tester.view.viewPadding = FakeViewPadding(bottom: inset * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    home: _Host(
      type: type,
      mode: mode,
      isTracking: isTracking,
      expanded: expanded,
      onHeight: onHeight,
    ),
  ));
  await tester.pumpAndSettle();
}

Rect _card(WidgetTester tester) =>
    tester.getRect(find.byKey(CollapsibleBottomControls.cardKey));

Rect _rectOf(Element element) {
  final box = element.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

List<Rect> _buttons() => [
      ...find.byType(ElevatedButton).evaluate(),
      ...find.byType(OutlinedButton).evaluate(),
      ...find.byType(IconButton).evaluate(),
    ].map(_rectOf).toList();

void main() {
  final configs = <(String, GeometryType, CollectionMode, bool)>[
    ('point', GeometryType.point, CollectionMode.tracking, false),
    ('polygon tracking', GeometryType.polygon, CollectionMode.tracking, false),
    ('polygon sedang tracking', GeometryType.polygon, CollectionMode.tracking, true),
    ('line gambar', GeometryType.line, CollectionMode.drawing, false),
  ];

  for (final inset in [34.0, 48.0, 0.0]) {
    for (final (label, type, mode, isTracking) in configs) {
      for (final expanded in [true, false]) {
        testWidgets(
            '$label, ${expanded ? 'terbuka' : 'ringkas'}, bilah bawah $inset: '
            'tombol utuh di atas bilah, tanpa pita putih', (tester) async {
          await _pump(tester,
              inset: inset,
              type: type,
              mode: mode,
              isTracking: isTracking,
              expanded: expanded);

          final safeBottom = _screen.height - inset;
          final buttons = _buttons();
          expect(buttons, isNotEmpty);
          for (final b in buttons) {
            expect(b.bottom, lessThanOrEqualTo(safeBottom),
                reason: 'tombol $b masuk ke bilah navigasi / terpotong');
          }

          final card = _card(tester);
          // Kartu berhenti di atas bilah navigasi; di bawahnya peta.
          expect(card.bottom, lessThanOrEqualTo(safeBottom));
          expect(card.bottom, greaterThanOrEqualTo(safeBottom - 12));
          for (final b in buttons) {
            expect(card.contains(b.topLeft) && b.bottom <= card.bottom, isTrue,
                reason: 'tombol $b harus utuh di dalam kartu $card');
          }
          final lowest =
              buttons.map((b) => b.bottom).reduce((a, b) => a > b ? a : b);
          expect(card.bottom - lowest, lessThanOrEqualTo(12.5),
              reason: 'ruang putih di bawah tombol terlalu besar');
        });
      }
    }
  }

  testWidgets('tombol Hide/Show controls menyembunyikan dan memunculkan',
      (tester) async {
    await _pump(tester);
    expect(find.byIcon(Icons.undo), findsOneWidget);

    await tester.tap(find.byTooltip('Hide controls'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.undo), findsNothing);
    expect(find.text('Start'), findsOneWidget, reason: 'aksi utama tetap ada');

    await tester.tap(find.byTooltip('Show controls'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.undo), findsOneWidget);
  });

  testWidgets('ketuk pegangan menyembunyikan dan memunculkan', (tester) async {
    await _pump(tester);
    await tester.tapAt(Offset(_screen.width / 2, _card(tester).top + 8));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.undo), findsNothing);

    await tester.tapAt(Offset(_screen.width / 2, _card(tester).top + 8));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.undo), findsOneWidget);
  });

  testWidgets('geser cepat yang pendek ke bawah/atas ikut menyembunyikan',
      (tester) async {
    await _pump(tester);
    await tester.flingFrom(
        _card(tester).center, const Offset(0, 30), 1000);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.undo), findsNothing);

    await tester.flingFrom(
        _card(tester).center, const Offset(0, -30), 1000);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.undo), findsOneWidget);
  });

  testWidgets('geser pelan yang sangat pendek tidak mengubah panel',
      (tester) async {
    await _pump(tester);
    await tester.timedDragFrom(_card(tester).center, const Offset(0, 22),
        const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.undo), findsOneWidget);
  });

  testWidgets('sedang tracking & ringkas: Stop dan Pause tetap terlihat',
      (tester) async {
    await _pump(tester, isTracking: true, expanded: false);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
  });

  testWidgets(
      'melaporkan tinggi yang ditempati dari tepi bawah (untuk tombol peta)',
      (tester) async {
    final heights = <double>[];
    await _pump(tester, onHeight: heights.add);
    expect(heights.last, closeTo(_screen.height - _card(tester).top, 0.01));
    final expandedHeight = heights.last;

    await tester.tap(find.byTooltip('Hide controls'));
    await tester.pumpAndSettle();
    expect(heights.last, closeTo(_screen.height - _card(tester).top, 0.01));
    expect(heights.last, lessThan(expandedHeight));
  });
}
