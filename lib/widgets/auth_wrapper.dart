import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../screens/home_screen.dart';
import '../screens/passenger_screen.dart';
import '../screens/driver_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: SizedBox.shrink(),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          // User is not logged in, show home screen
          return const HomeScreen();
        }

        // User is logged in, wait for userType and then redirect appropriately
        return FutureBuilder<UserType?>(
          future: () async {
            final resolved = await AuthService().waitForUserType(retries: 4, delay: const Duration(milliseconds: 400));
            if (resolved != null) return resolved;
            final current = AuthService().currentUserType;
            if (current != null) return current;
            try {
              final uid = user.uid;
              final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
              final data = snap.data();
              final typeStr = data?['userType'] as String?;
              if (typeStr == 'driver') return UserType.driver;
              if (typeStr == 'passenger') return UserType.passenger;
            } catch (_) {}
            return null;
          }(),
          builder: (context, userDataSnapshot) {
            if (userDataSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: SizedBox.shrink(),
              );
            }

            final userType = userDataSnapshot.data ?? AuthService().currentUserType;

            if (userType == UserType.driver) {
              return const DriverScreen();
            } else if (userType == UserType.passenger) {
              return const PassengerScreen();
            } else {
              // If still unknown, keep user in place by showing a minimal scaffold
              return const Scaffold(
                body: SizedBox.shrink(),
              );
            }
          },
        );
      },
    );
  }
}
