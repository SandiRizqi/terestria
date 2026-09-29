import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../screens/readiness/field_readiness_screen.dart';
import '../../services/readiness/field_readiness.dart';
import '../../services/readiness/field_readiness_service.dart';
import '../../utils/app_logger.dart';

const _promptDayKey = 'readiness_prompt_day';

/// Butir yang bisa menghentikan tracking di tengah jalan — hanya ini yang
/// ditanyakan saat Start (penyimpanan & Emlid sudah dicek alur Start sendiri).
const _startCritical = {
  'location_permission',
  'location_service',
  'battery',
  'notifications',
};

/// Butir checklist yang layak ditanyakan sebelum Start.
List<ReadinessItem> startBlockingItems(List<ReadinessItem> items) => items
    .where((i) =>
        _startCritical.contains(i.id) &&
        (i.level == ReadinessLevel.problem ||
            i.level == ReadinessLevel.warning))
    .toList();

String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// Sekali per hari, saat Start tracking pertama: bila ada hal yang bisa
/// menghentikan tracking (izin, GPS mati, optimasi baterai, notifikasi),
/// tawarkan checklist. `true` = lanjut Start. Pemeriksaan yang gagal TIDAK
/// pernah memblokir Start.
Future<bool> maybeShowDailyReadinessCheck(
  BuildContext context, {
  Future<ReadinessInputs> Function()? collect,
  DateTime Function()? now,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final today = _dayKey((now ?? DateTime.now)());
    if (prefs.getString(_promptDayKey) == today) return true;

    final inputs = await (collect ??
        () => FieldReadinessService().collect(testGps: false))();
    final issues = startBlockingItems(evaluateReadiness(inputs));
    await prefs.setString(_promptDayKey, today);
    if (issues.isEmpty || !context.mounted) return true;

    logInfo('Start readiness prompt: ${issues.map((i) => i.id).join(', ')}',
        tag: 'READY');
    final startAnyway = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.fact_check_rounded, color: Colors.orange, size: 28),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Before you start',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 6),
              const Text('These settings can stop tracking in the field:',
                  style: TextStyle(fontSize: 14)),
              const SizedBox(height: 10),
              for (final item in issues)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        item.level == ReadinessLevel.problem
                            ? Icons.error_rounded
                            : Icons.warning_amber_rounded,
                        color: item.level == ReadinessLevel.problem
                            ? Colors.red.shade700
                            : Colors.orange.shade800,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(TextSpan(children: [
                          TextSpan(
                              text: '${item.title}: ',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: item.detail),
                        ])),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48)),
                    child: const Text('Start anyway'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style:
                        FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    child: const Text('Check & fix'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    if (startAnyway == true) return true;
    if (startAnyway == false && context.mounted) {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => const FieldReadinessScreen()));
    }
    // Sheet ditutup tanpa pilihan (swipe/back) = batal; Start berikutnya hari
    // ini langsung jalan (sudah ditanyakan).
    return false;
  } catch (e, st) {
    logWarn('Start readiness check failed; starting anyway',
        tag: 'READY', error: e, stack: st);
    return true;
  }
}
