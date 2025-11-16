import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/onboarding_screen.dart';

class TutorialHelper {
  static const String _passengerKey = 'onboarding_completed_passenger';
  static const String _driverKey = 'onboarding_completed_driver';

  /// Check if user should see onboarding tutorial
  static Future<bool> shouldShowOnboarding(String userType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = userType == 'passenger' ? _passengerKey : _driverKey;
      return !(prefs.getBool(key) ?? false);
    } catch (e) {
      return false; // Don't show tutorial if there's an error
    }
  }

  /// Mark onboarding as completed
  static Future<void> markOnboardingCompleted(String userType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = userType == 'passenger' ? _passengerKey : _driverKey;
      await prefs.setBool(key, true);
    } catch (e) {
      // Silently fail
    }
  }

  /// Show onboarding tutorial
  static Future<void> showTutorial(BuildContext context, String userType) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingScreen(
          userType: userType,
          onComplete: () {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  /// Create a help button widget that shows the tutorial
  static Widget createHelpButton(BuildContext context, String userType) {
    return IconButton(
      tooltip: 'Tutorial',
      icon: const Icon(Icons.help_outline),
      onPressed: () => showTutorial(context, userType),
    );
  }

  /// Wrap a screen with onboarding check
  static Widget wrapWithOnboarding({
    required Widget child,
    required String userType,
  }) {
    return FutureBuilder<bool>(
      future: shouldShowOnboarding(userType),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final shouldShow = snapshot.data ?? false;
        if (shouldShow) {
          return OnboardingScreen(
            userType: userType,
            onComplete: () async {
              await markOnboardingCompleted(userType);
              // The widget will rebuild and show the child
            },
          );
        }

        return child;
      },
    );
  }
}
