import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:html' as html show Notification;
import 'firebase_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const String _badgeChannelId = 'app_badge_channel';
  static const int _badgeNotificationId = 9999;
  static bool _webPermissionRequested = false;

  static Future<void> initialize() async {
    if (kIsWeb) {
      _requestWebPermission();
      return;
    }
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _plugin.initialize(settings: const InitializationSettings(android: androidSettings, iOS: iosSettings));
    const badgeChannel = AndroidNotificationChannel(
      _badgeChannelId, 'App Badge',
      description: 'App icon badge count',
      importance: Importance.min,
      playSound: false,
      enableVibration: false,
      enableLights: false,
      showBadge: true,
    );
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(badgeChannel);
  }

  static void _requestWebPermission() {
    if (_webPermissionRequested) return;
    _webPermissionRequested = true;
    if (html.Notification.permission == 'default') {
      html.Notification.requestPermission();
    }
  }

  static Future<void> checkAndNotify() async {
    final user = FirebaseService.currentUser;
    if (user == null) return;

    if (kIsWeb) {
      final doc = await FirebaseService.firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return;
      final lastLogin = (doc.data()?['lastLogin'] as Timestamp?)?.toDate();
      await FirebaseService.firestore.collection('users').doc(user.uid).update({
        'lastLogin': Timestamp.fromDate(DateTime.now()),
      });
      if (lastLogin == null) return;
      final hoursSince = DateTime.now().difference(lastLogin).inHours;
      if (hoursSince >= 72) {
        await _showNotification('Long time no see!', "We miss you! Come back to continue your study streak.");
      } else if (hoursSince >= 24) {
        await _showNotification('Daily Streak', "You missed a day! Open PrePora to keep your streak alive.");
      }
      return;
    }

    final doc = await FirebaseService.firestore.collection('users').doc(user.uid).get();
    if (!doc.exists) return;

    final lastLogin = (doc.data()?['lastLogin'] as Timestamp?)?.toDate();
    final now = DateTime.now();

    await FirebaseService.firestore.collection('users').doc(user.uid).update({
      'lastLogin': Timestamp.fromDate(now),
    });

    if (lastLogin == null) return;

    final hoursSince = now.difference(lastLogin).inHours;

    if (hoursSince >= 72) {
      await _showNotification('Long time no see!', "We miss you! Come back to continue your study streak.");
    } else if (hoursSince >= 24) {
      await _showNotification('Daily Streak', "You missed a day! Open PrePora to keep your streak alive.");
    }
  }

  static Future<void> _showNotification(String title, String body) async {
    if (kIsWeb) {
      _showWebNotification(title, body);
      return;
    }
    const androidDetails = AndroidNotificationDetails('streak_channel', 'Daily Streak',
      channelDescription: 'Daily streak reminders', importance: Importance.high, priority: Priority.high);
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    await _plugin.show(id: DateTime.now().millisecondsSinceEpoch ~/ 1000, title: title, body: body, notificationDetails: details);
  }

  static void _showWebNotification(String title, String body) {
    if (html.Notification.permission == 'granted') {
      html.Notification(title, body: body);
    } else if (html.Notification.permission != 'denied') {
      html.Notification.requestPermission().then((permission) {
        if (permission == 'granted') {
          html.Notification(title, body: body);
        }
      });
    }
  }

  static Future<void> showFeedbackNotification(String studentName, String message) async {
    if (kIsWeb) {
      _showWebNotification('New Feedback from $studentName', message);
      return;
    }
    const androidDetails = AndroidNotificationDetails('feedback_channel', 'Feedbacks',
      channelDescription: 'New student feedbacks', importance: Importance.high, priority: Priority.high);
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    await _plugin.show(id: DateTime.now().millisecondsSinceEpoch ~/ 1000, title: 'New Feedback from $studentName', body: message, notificationDetails: details);
  }

  static Future<void> setBadgeCount(int count) async {
    if (kIsWeb) return;
    if (count > 0) {
      final androidDetails = AndroidNotificationDetails(
        _badgeChannelId, 'App Badge',
        channelDescription: 'App icon badge count',
        importance: Importance.min,
        priority: Priority.min,
        playSound: false,
        enableVibration: false,
        number: count,
      );
      final details = NotificationDetails(android: androidDetails);
      await _plugin.show(id: _badgeNotificationId, title: '', body: '', notificationDetails: details);
    } else {
      await _plugin.cancel(id: _badgeNotificationId);
    }
  }

  static Future<void> clearBadge() async {
    if (kIsWeb) return;
    await _plugin.cancel(id: _badgeNotificationId);
  }

  static void startListeningForNotifications(String uid) {
    if (!kIsWeb) return;
    FirebaseService.firestore
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (snap.docs.isEmpty) return;
      final data = snap.docs.first.data() as Map<String, dynamic>;
      final msg = data['message'] as String? ?? '';
      if (msg.isNotEmpty) {
        _showWebNotification('PrePora', msg);
      }
    });
  }
}