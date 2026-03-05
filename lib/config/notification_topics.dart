import 'package:flutter/material.dart';

/// Model untuk notification topic yang bisa di-subscribe user
class NotificationTopic {
  final String id;           // FCM topic name (harus tanpa spasi, lowercase)
  final String label;        // Nama tampilan
  final String description;  // Deskripsi singkat
  final IconData icon;       // Icon untuk ditampilkan di UI
  final bool isDefault;      // Apakah default aktif saat pertama kali

  const NotificationTopic({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    this.isDefault = true,
  });
}

/// =============================================================
/// EDIT LIST INI UNTUK MENAMBAH/MENGURANGI TOPIC NOTIFIKASI
/// =============================================================
/// 
/// Cara menambah topic baru:
///   1. Tambahkan NotificationTopic baru ke list di bawah
///   2. Pastikan 'id' unik dan sesuai dengan topic di Firebase Console
///   3. Set 'isDefault: true' jika ingin otomatis aktif untuk user baru
///
/// Cara menghapus topic:
///   1. Hapus/comment entry dari list di bawah
///   2. User yang sudah subscribe akan otomatis unsubscribe
///
const List<NotificationTopic> defaultNotificationTopics = [
  NotificationTopic(
    id: 'general',
    label: 'Umum',
    description: 'Notifikasi umum dan pengumuman penting',
    icon: Icons.campaign_outlined,
    isDefault: true,
  ),
  NotificationTopic(
    id: 'updates',
    label: 'Update Aplikasi',
    description: 'Info update dan fitur baru aplikasi',
    icon: Icons.system_update_outlined,
    isDefault: true,
  ),
  NotificationTopic(
    id: 'hotspots',
    label: 'Hotspot alert updates',
    description: 'Hotspot alert updates',
    icon: Icons.article_outlined,
    isDefault: true,
  ),
  NotificationTopic(
    id: 'deforestation',
    label: 'Deforestation alert updates',
    description: 'Deforestation alert updates',
    icon: Icons.local_offer_outlined,
    isDefault: true,
  ),
  NotificationTopic(
    id: 'patokhgu',
    label: 'Patok HGU updates',
    description: 'Patok HGU updates',
    icon: Icons.lightbulb_outlined,
    isDefault: true,
  ),
];
