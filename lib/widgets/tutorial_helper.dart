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

  /// Check if tutorial should be shown after registration
  static Future<bool> shouldShowTutorialAfterRegistration(String userType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'show_tutorial_$userType';
      return prefs.getBool(key) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Clear the post-registration tutorial flag
  static Future<void> clearTutorialFlag(String userType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('show_tutorial_$userType');
      await markOnboardingCompleted(userType);
    } catch (e) {
      // Silently fail
    }
  }

  /// Wrap a screen with post-registration tutorial check
  static Widget wrapWithOnboarding({
    required Widget child,
    required String userType,
  }) {
    return FutureBuilder<bool>(
      future: shouldShowTutorialAfterRegistration(userType),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return child; // Show main screen immediately while checking
        }

        final shouldShow = snapshot.data ?? false;
        if (shouldShow) {
          // Show tutorial after a short delay for smooth transition
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await Future.delayed(const Duration(milliseconds: 300));
            if (context.mounted) {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OnboardingScreen(
                    userType: userType,
                    onComplete: () async {
                      await clearTutorialFlag(userType);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              );
            }
          });
        }

        return child;
      },
    );
  }
}
