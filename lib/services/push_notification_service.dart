import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Top-level background message handler. Must not be inside a class.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure handler is registered so messages are received when app is terminated.
}

class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<bool> _isPushEnabledForUser(String uid) async {
    try {
      final snap = await _db.collection('users').doc(uid).get();
      final data = snap.data();
      final settings = (data?['settings'] as Map<String, dynamic>?) ?? {};
      return (settings['pushNotifications'] as bool?) ?? true;
    } catch (_) {
      return true; // default to enabled if unknown
    }
  }

  /// Initialize FCM safely without changing UI flow.
  static Future<void> initialize() async {
    // Register background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Check current user setting before requesting permission or saving token
    final user = _auth.currentUser;
    if (user != null) {
      final enabled = await _isPushEnabledForUser(user.uid);
      if (!enabled) {
        // Do not request permission or sync token if disabled
        return;
      }
    }

    // Request permissions (iOS + Android 13+)
    await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    // Obtain token and persist if user is logged in and allowed
    await _syncTokenWithUser();

    // Handle token refresh with respect to setting
    _messaging.onTokenRefresh.listen((token) async {
      final u = _auth.currentUser;
      if (u == null) return;
      final enabled = await _isPushEnabledForUser(u.uid);
      if (enabled) {
        _saveTokenForCurrentUser(token);
      }
    });

    // Optional: Set foreground presentation options on iOS
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  static Future<void> _syncTokenWithUser() async {
    final user = _auth.currentUser;
    final token = await _messaging.getToken();
    if (user != null && token != null) {
      final enabled = await _isPushEnabledForUser(user.uid);
      if (enabled) {
        try {
          await _saveTokenForCurrentUser(token);
        } catch (_) {
          // Swallow token save failures (e.g., permission-denied)
        }
      }
    }

    // When auth state changes, gate on setting
    _auth.authStateChanges().listen((user) async {
      if (user == null) return;
      final enabled = await _isPushEnabledForUser(user.uid);
      if (!enabled) return;
      final refreshed = await _messaging.getToken();
      if (refreshed != null) {
        try {
          await _saveTokenForCurrentUser(refreshed);
        } catch (_) {
          // Ignore failures to avoid impacting auth flow/UI
        }
      }
    });
  }

  static Future<void> _saveTokenForCurrentUser(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    // Store a single token field. For multi-device, migrate to array or subcollection later.
    try {
      await userRef.set({'fcmToken': token}, SetOptions(merge: true));
    } catch (e) {
      // Rethrow only non-permission errors if needed; otherwise ignore to avoid crashes
      final msg = e.toString();
      if (!msg.contains('permission-denied') && !msg.contains('PERMISSION_DENIED')) {
        rethrow;
      }
    }
  }
}
