import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _initialized = false;

  Future<void> initialize({BuildContext? context}) async {
    if (_initialized) return;
    try {
      // iOS permission
      if (Platform.isIOS) {
        await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      // Get and store FCM token
      final token = await _messaging.getToken();
      try {
        await _saveToken(token);
      } catch (_) {
        // Ignore permission or connectivity errors
      }

      // Token refresh
      _messaging.onTokenRefresh.listen((t) async {
        try {
          await _saveToken(t);
        } catch (_) {
          // Ignore to avoid impacting UX
        }
      });

      // Foreground handler (basic UX using SnackBar if context provided)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (context == null) return;
        final notification = message.notification;
        if (notification != null) {
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.showSnackBar(
            SnackBar(content: Text(notification.title ?? 'Notification')),
          );
        }
      });

      _initialized = true;
    } catch (_) {
      // ignore errors silently to avoid breaking flows
    }
  }

  Future<void> _saveToken(String? token) async {
    final user = _auth.currentUser;
    if (user == null || token == null) return;
    try {
      await _db.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      final msg = e.toString();
      if (!msg.contains('permission-denied') && !msg.contains('PERMISSION_DENIED')) {
        rethrow;
      }
    }
  }

  Future<void> subscribeToTodaTopic(String toda) async {
    if (toda.isEmpty) return;
    final topic = _topicForToda(toda);
    await _messaging.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTodaTopic(String toda) async {
    if (toda.isEmpty) return;
    final topic = _topicForToda(toda);
    await _messaging.unsubscribeFromTopic(topic);
  }

  Future<void> subscribeToPickupTopic(String pickupId) async {
    if (pickupId.isEmpty) return;
    final topic = _topicForPickup(pickupId);
    await _messaging.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromPickupTopic(String pickupId) async {
    if (pickupId.isEmpty) return;
    final topic = _topicForPickup(pickupId);
    await _messaging.unsubscribeFromTopic(topic);
  }

  // Enqueue notifications into Firestore for a backend process (Cloud Function) to deliver via FCM
  Future<void> enqueueDriverNotificationForToda({
    required String toda,
    required String pickupId,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    final topic = _topicForToda(toda);
    await _db.collection('notifications').add({
      'target': 'topic',
      'topic': topic,
      'pickupId': pickupId,
      'title': title,
      'body': body,
      'data': data ?? {},
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'queued',
    });
  }

  Future<void> enqueuePassengerNotificationForPickup({
    required String pickupId,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    final topic = _topicForPickup(pickupId);
    await _db.collection('notifications').add({
      'target': 'topic',
      'topic': topic,
      'pickupId': pickupId,
      'title': title,
      'body': body,
      'data': data ?? {},
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'queued',
    });
  }

  String _topicForToda(String toda) => 'toda_${toda.replaceAll(' ', '_').toLowerCase()}';
  String _topicForPickup(String pickupId) => 'pickup_$pickupId';
}
