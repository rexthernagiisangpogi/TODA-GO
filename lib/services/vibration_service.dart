import 'package:vibration/vibration.dart';
import 'package:flutter/services.dart';

class VibrationService {
  static const VibrationService _instance = VibrationService._internal();
  factory VibrationService() => _instance;
  const VibrationService._internal();

  /// Check if vibration is available on the device
  Future<bool> hasVibrator() async {
    return await Vibration.hasVibrator();
  }

  /// Check if custom vibration patterns are supported
  Future<bool> hasCustomVibrationsSupport() async {
    return await Vibration.hasCustomVibrationsSupport();
  }

  /// Vibrate for new passenger notification
  /// Uses a pattern that's attention-grabbing but not annoying
  Future<void> vibrateForNewPassenger() async {
    final hasVibration = await hasVibrator();
    if (!hasVibration) return;

    final hasCustomSupport = await hasCustomVibrationsSupport();
    
    if (hasCustomSupport) {
      // Custom pattern: short-long-short-long (like an alert)
      // Pattern: [wait, vibrate, wait, vibrate, wait, vibrate, wait, vibrate]
      await Vibration.vibrate(
        pattern: [0, 200, 100, 400, 100, 200, 100, 400],
        intensities: [0, 128, 0, 255, 0, 128, 0, 255],
      );
    } else {
      // Fallback: simple vibration sequence
      await Vibration.vibrate(duration: 500);
      await Future.delayed(const Duration(milliseconds: 200));
      await Vibration.vibrate(duration: 300);
    }
  }

  /// Trigger urgent notification vibration (for 4+ passengers)
  Future<void> vibrateForUrgentNotification() async {
    if (!await hasVibrator()) return;
    
    if (await hasCustomVibrationsSupport()) {
      // More intense pattern for urgent notifications
      await Vibration.vibrate(pattern: [0, 200, 100, 200, 100, 300, 100, 200]);
    } else {
      // Fallback: longer vibration for urgency
      await Vibration.vibrate(duration: 800);
    }
  }

  /// Simple single vibration for general notifications
  Future<void> vibrateOnce({int duration = 200}) async {
    final hasVibration = await hasVibrator();
    if (!hasVibration) return;

    await Vibration.vibrate(duration: duration);
  }

  /// Cancel any ongoing vibration
  Future<void> cancel() async {
    await Vibration.cancel();
  }

  /// Light haptic feedback for button taps and interactions
  static void lightHaptic() {
    HapticFeedback.lightImpact();
  }

  /// Medium haptic feedback for confirmations
  static void mediumHaptic() {
    HapticFeedback.mediumImpact();
  }

  /// Heavy haptic feedback for important actions
  static void heavyHaptic() {
    HapticFeedback.heavyImpact();
  }

  /// Selection haptic feedback for UI selections
  static void selectionHaptic() {
    HapticFeedback.selectionClick();
  }
}
