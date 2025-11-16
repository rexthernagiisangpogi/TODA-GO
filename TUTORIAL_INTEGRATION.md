# Tutorial System Integration Guide

## Overview
A comprehensive onboarding tutorial system has been implemented for your TODA GO app. This system provides slide-based tutorials for both passengers and drivers, with the ability to show tutorials to new users and allow existing users to access them anytime via a help button.

## Files Created

### 1. `lib/screens/onboarding_screen.dart`
- Main onboarding screen with slide-based tutorial
- Separate content for passengers and drivers
- Beautiful UI with animations and progress indicators
- Persistent state management using SharedPreferences

### 2. `lib/widgets/tutorial_helper.dart`
- Helper class for easy integration
- Methods to check if tutorial should be shown
- Helper to create help buttons
- Wrapper widget for automatic onboarding

### 3. `pubspec.yaml` (Updated)
- Added `shared_preferences: ^2.2.2` dependency

## Integration Instructions

### Step 1: Install Dependencies
Run the following command to install the new dependency:
```bash
flutter pub get
```

### Step 2: Integrate into Passenger Screen

Add these imports to your `passenger_screen.dart`:
```dart
import '../widgets/tutorial_helper.dart';
import '../screens/onboarding_screen.dart';
```

Wrap your passenger screen build method:
```dart
@override
Widget build(BuildContext context) {
  return TutorialHelper.wrapWithOnboarding(
    userType: 'passenger',
    child: StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Your existing build logic here
        return _buildMainContent(); // or your existing content
      },
    ),
  );
}
```

Add help button to AppBar actions:
```dart
actions: [
  TutorialHelper.createHelpButton(context, 'passenger'),
  // Your existing action buttons
],
```

### Step 3: Integrate into Driver Screen

Similar to passenger screen, add these imports to your `driver_screen.dart`:
```dart
import '../widgets/tutorial_helper.dart';
import '../screens/onboarding_screen.dart';
```

Wrap your driver screen build method:
```dart
@override
Widget build(BuildContext context) {
  return TutorialHelper.wrapWithOnboarding(
    userType: 'driver',
    child: StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Your existing build logic here
        return _buildDriverScreen(); // or your existing content
      },
    ),
  );
}
```

Add help button to AppBar actions:
```dart
actions: [
  TutorialHelper.createHelpButton(context, 'driver'),
  // Your existing action buttons
],
```

## Tutorial Content

### Passenger Tutorial (5 slides):
1. **Welcome to TODA GO** - Introduction to the app
2. **Book Your Ride** - How to set pickup location and request rides
3. **Track Your Driver** - Real-time tracking features
4. **Chat & Rate** - Communication and rating system
5. **You're All Set!** - Final encouragement

### Driver Tutorial (5 slides):
1. **Welcome Driver!** - Introduction for drivers
2. **Go Online** - How to toggle online status
3. **Accept Requests** - Managing ride requests
4. **Navigate & Complete** - Using navigation and completing rides
5. **Earn & Grow** - Building reputation and earnings

## Features

### ✅ **For New Users:**
- Automatic tutorial display on first app launch
- Separate tutorials for passengers and drivers
- Beautiful slide-based interface with animations
- Progress indicators and navigation controls
- Persistent completion state

### ✅ **For Existing Users:**
- Help button (❓) in app bar for easy access
- Can replay tutorial anytime
- No disruption to existing functionality

### ✅ **Technical Features:**
- Uses SharedPreferences for state persistence
- Separate completion tracking for passenger/driver modes
- Smooth animations and transitions
- Responsive design
- Error handling and fallbacks

## Customization

### Modify Tutorial Content
Edit the `_getSlides()` method in `onboarding_screen.dart` to customize:
- Slide titles and descriptions
- Icons and colors
- Number of slides

### Styling
The tutorial uses your app's existing color scheme:
- Primary color: `Color(0xFF082FBD)` (TODA GO blue)
- Gradient backgrounds matching your app theme
- Consistent typography and spacing

## Testing

### Reset Tutorial State (for testing):
```dart
// Add this method to your debug menu or testing code
Future<void> resetTutorials() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('onboarding_completed_passenger');
  await prefs.remove('onboarding_completed_driver');
}
```

## Usage Examples

### Manual Tutorial Display:
```dart
// Show tutorial manually
await TutorialHelper.showTutorial(context, 'passenger');
```

### Check Tutorial Status:
```dart
// Check if user should see tutorial
bool shouldShow = await TutorialHelper.shouldShowOnboarding('passenger');
```

### Custom Help Button:
```dart
IconButton(
  icon: Icon(Icons.help_outline),
  onPressed: () => TutorialHelper.showTutorial(context, 'driver'),
)
```

## Notes

- The tutorial system is designed to be non-intrusive
- It maintains backward compatibility with existing code
- State is persisted across app restarts
- Works offline (no network required for tutorial display)
- Follows Material Design guidelines

## Troubleshooting

If you encounter issues:

1. **Dependencies**: Make sure to run `flutter pub get` after adding shared_preferences
2. **Imports**: Ensure all import statements are correct
3. **Context**: Make sure you have a valid BuildContext when calling tutorial methods
4. **State**: Use `setState()` when needed to refresh UI after tutorial completion

The tutorial system is now ready to help new users understand your TODA GO app efficiently!
