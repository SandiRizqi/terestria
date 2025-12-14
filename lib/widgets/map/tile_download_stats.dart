import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/tile_download_manager.dart';

/// Widget untuk menampilkan statistik download tile
/// Berguna untuk monitoring dan debugging
class TileDownloadStats extends StatefulWidget {
  const TileDownloadStats({Key? key}) : super(key: key);

  @override
  State<TileDownloadStats> createState() => _TileDownloadStatsState();
}

class _TileDownloadStatsState extends State<TileDownloadStats> {
  final TileDownloadManager _downloadManager = TileDownloadManager();
  Timer? _timer;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _updateStats();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        _updateStats();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateStats() {
    setState(() {
      _stats = _downloadManager.getStatistics();
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeDownloads = _stats['activeDownloads'] ?? 0;
    final queuedDownloads = _stats['queuedDownloads'] ?? 0;
    final successRate = _stats['successRate'] ?? 'N/A';

    // Don't show if no activity
    if (activeDownloads == 0 && queuedDownloads == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.download,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            'Downloading: $activeDownloads | Queue: $queuedDownloads',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (successRate != 'N/A') ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green[700],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                successRate,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
