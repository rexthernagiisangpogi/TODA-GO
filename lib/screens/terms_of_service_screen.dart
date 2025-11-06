import 'package:flutter/material.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
        backgroundColor: const Color(0xFF082FBD),
        foregroundColor: Colors.white,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Text(
          'This is a placeholder Terms of Service for TODA GO.\n\n'
          '• By using the app, you agree to abide by local regulations and company policies.\n'
          '• Drivers and passengers must provide accurate information.\n'
          '• Service availability and features may change without notice.\n\n'
          'Replace this content with your official terms for production use.',
          style: TextStyle(fontSize: 16, height: 1.4),
        ),
      ),
    );
  }
}
