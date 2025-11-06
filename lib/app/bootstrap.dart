import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';
import '../services/push_notification_service.dart';
import 'toda_go_app.dart';

enum AppFlavor { mobile, web }

Future<void> bootstrap(AppFlavor flavor) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  try {
    await PushNotificationService.initialize();
  } catch (_) {}
  runApp(const AppRoot());
}
