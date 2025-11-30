import 'dart:async';

class NotificationEventService {
  static final NotificationEventService _instance = NotificationEventService._internal();
  factory NotificationEventService() => _instance;
  NotificationEventService._internal();

  // Stream controller untuk broadcast notification events
  final _notificationEventController = StreamController<NotificationEvent>.broadcast();
  
  // Stream yang bisa didengarkan oleh widgets
  Stream<NotificationEvent> get notificationStream => _notificationEventController.stream;

  // Notify bahwa ada notifikasi baru
  void notifyNewNotification() {
    _notificationEventController.add(NotificationEvent.newNotification);
  }

  // Notify bahwa notifikasi telah dibaca
  void notifyNotificationRead() {
    _notificationEventController.add(NotificationEvent.notificationRead);
  }

  // Notify bahwa notifikasi telah dihapus
  void notifyNotificationDeleted() {
    _notificationEventController.add(NotificationEvent.notificationDeleted);
  }

  // Notify bahwa semua notifikasi telah dibaca
  void notifyAllRead() {
    _notificationEventController.add(NotificationEvent.allRead);
  }

  // Notify bahwa semua notifikasi telah dihapus
  void notifyAllDeleted() {
    _notificationEventController.add(NotificationEvent.allDeleted);
  }

  // Dispose stream controller
  void dispose() {
    _notificationEventController.close();
  }
}

enum NotificationEvent {
  newNotification,
  notificationRead,
  notificationDeleted,
  allRead,
  allDeleted,
}
