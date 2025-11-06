import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: const Color(0xFF082FBD),
        foregroundColor: Colors.white,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Text(
          'This is a placeholder Privacy Policy for TODA GO.\n\n'
          '• We respect your privacy and are committed to protecting your personal data.\n'
          '• Location data is used to enable pickups and is not shared with third parties without consent.\n'
          '• Push notifications are used for ride updates; you can disable them in Settings.\n\n'
          'For the full legal text, replace this screen content with your official policy.',
          style: TextStyle(fontSize: 16, height: 1.4),
        ),
      ),
    );
  }
}
