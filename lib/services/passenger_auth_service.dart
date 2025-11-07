import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PassengerAuthService {
  static final PassengerAuthService _instance = PassengerAuthService._internal();
  factory PassengerAuthService() => _instance;
  PassengerAuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? _currentPassengerData;

  // Getters
  User? get currentUser => _auth.currentUser;
  Map<String, dynamic>? get currentPassengerData => _currentPassengerData;
  bool get isLoggedIn => _auth.currentUser != null && _currentPassengerData != null;
  
  // Check if current session is valid for passenger
  Future<bool> isValidPassengerSession() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return false;
      
      final userData = userDoc.data()!;
      return userData['userType'] == 'passenger';
    } catch (e) {
      return false;
    }
  }

  // Initialize passenger data from Firestore
  Future<bool> initializePassengerData() async {
    final user = _auth.currentUser;
    if (user == null) {
      _currentPassengerData = null;
      return false;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        _currentPassengerData = null;
        return false;
      }

      final userData = userDoc.data()!;
      if (userData['userType'] != 'passenger') {
        _currentPassengerData = null;
        return false;
      }

      _currentPassengerData = userData;
      return true;
    } catch (e) {
      _currentPassengerData = null;
      return false;
    }
  }

  // Register as passenger
  Future<String?> registerPassenger({
    required String name,
    required String email,
    required String password,
  }) async {
    print('=== PASSENGER REGISTRATION START ===');
    print('Name: $name');
    print('Email: $email');
    print('Password length: ${password.length}');
    
    // TEMPORARY: Development mode bypass for network issues
    if (kDebugMode && email == 'test@passenger.com' && password == 'test123') {
      print('=== DEVELOPMENT MODE: Using test credentials for registration ===');
      _currentPassengerData = {
        'name': name,
        'email': 'test@passenger.com',
        'userType': 'passenger',
        'role': 'regularPassenger',
        'uid': 'test-passenger-uid',
      };
      print('=== PASSENGER REGISTRATION COMPLETE (DEV MODE) ===');
      return null; // Success
    }
    
    try {
      // Create Firebase Auth user with retry logic for network issues
      print('Step 1: Creating Firebase Auth user...');
      UserCredential? credential;
      int retryCount = 0;
      const maxRetries = 3;
      
      while (credential == null && retryCount < maxRetries) {
        try {
          credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
        } catch (e) {
          retryCount++;
          print('Registration attempt $retryCount failed: $e');
          if (retryCount >= maxRetries) {
            rethrow;
          }
          await Future.delayed(Duration(seconds: retryCount * 2));
        }
      }
      
      print('Step 1 SUCCESS: User created with UID: ${credential?.user?.uid}');
      
      if (credential?.user == null) {
        print('ERROR: User is null after creation');
        return 'Account creation failed';
      }
      
      final user = credential!.user!;
      
      // Update display name
      print('Step 2: Setting display name...');
      await user.updateDisplayName(name);
      print('Step 2 SUCCESS: Display name set');
      
      // Create Firestore document
      print('Step 3: Creating Firestore document...');
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': name,
        'email': email,
        'userType': 'passenger',
        'role': 'regularPassenger',
        'createdAt': FieldValue.serverTimestamp(),
      });
      print('Step 3 SUCCESS: Firestore document created');
      
      // Set local state
      _currentPassengerData = {
        'name': name,
        'email': email,
        'userType': 'passenger',
        'role': 'regularPassenger',
      };
      
      print('=== PASSENGER REGISTRATION COMPLETE ===');
      return null;
      
    } catch (e) {
      print('=== REGISTRATION FAILED ===');
      print('Error: $e');
      print('Error type: ${e.runtimeType}');
      print('Error details: ${e.toString()}');
      
      // Sign out if user was created but Firestore failed
      try {
        await _auth.signOut();
      } catch (_) {}
      
      if (e.toString().contains('email-already-in-use')) {
        return 'Email already registered. Try logging in instead.';
      }
      if (e.toString().contains('weak-password')) {
        return 'Password too weak. Use at least 6 characters.';
      }
      if (e.toString().contains('invalid-email')) {
        return 'Invalid email format.';
      }
      if (e.toString().contains('network-request-failed')) {
        return 'Network error. Please check your internet connection.';
      }
      if (e.toString().contains('permission-denied')) {
        return 'Permission denied. Please check Firebase configuration.';
      }
      
      return 'Registration failed: ${e.toString()}';
    }
  }
  

  // Login as passenger
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    print('=== PASSENGER LOGIN START ===');
    print('Email: $email');
    print('Password length: ${password.length}');
    
    // TEMPORARY: Development mode bypass for network issues
    if (kDebugMode && email == 'test@passenger.com' && password == 'test123') {
      print('=== DEVELOPMENT MODE: Using test credentials ===');
      _currentPassengerData = {
        'name': 'Test Passenger',
        'email': 'test@passenger.com',
        'userType': 'passenger',
        'role': 'regularPassenger',
        'uid': 'test-passenger-uid',
      };
      print('=== PASSENGER LOGIN COMPLETE (DEV MODE) ===');
      return null; // Success
    }
    
    try {
      print('Step 1: Signing in with Firebase Auth...');
      
      // Add retry logic for sign-in
      int retryCount = 0;
      const maxRetries = 3;
      bool signInSuccess = false;
      
      while (!signInSuccess && retryCount < maxRetries) {
        try {
          await _auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
          signInSuccess = true;
        } catch (e) {
          retryCount++;
          print('Sign-in attempt $retryCount failed: $e');
          if (retryCount >= maxRetries) {
            rethrow;
          }
          await Future.delayed(Duration(seconds: retryCount * 2));
        }
      }
      
      print('Step 1 SUCCESS: Firebase Auth sign-in complete');

      // Fetch user doc and validate userType == 'passenger'
      final user = _auth.currentUser;
      if (user == null) {
        return 'Authentication failed. Please try again.';
      }

      print('Step 2: Fetching user document...');
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        print('Step 2 FAILED: User document does not exist');
        await signOut();
        return 'Account not found. Please register as a passenger.';
      }
      print('Step 2 SUCCESS: User document found');
      
      final data = doc.data() ?? {};
      print('Step 3: Validating user type...');
      print('User data: $data');
      if ((data['userType'] as String?) != 'passenger') {
        print('Step 3 FAILED: Wrong user type');
        await signOut();
        final actual = (data['userType'] as String?) ?? 'driver';
        return 'This account is registered as a $actual. Please use the correct screen or create a passenger account.';
      }
      print('Step 3 SUCCESS: User type validated');

      _currentPassengerData = data;
      print('=== PASSENGER LOGIN COMPLETE ===');
      return null; // Success
    } catch (e) {
      print('=== LOGIN FAILED ===');
      print('Error: $e');
      print('Error type: ${e.runtimeType}');
      return _getFirebaseErrorMessage(e.toString());
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    _currentPassengerData = null;
  }

  // Error message helper
  String _getFirebaseErrorMessage(String error) {
    if (error.contains('weak-password')) {
      return 'The password is too weak. Please choose a stronger password.';
    } else if (error.contains('email-already-in-use')) {
      return 'An account already exists with this email. Please try logging in instead.';
    } else if (error.contains('invalid-email')) {
      return 'Please enter a valid email address.';
    } else if (error.contains('user-not-found')) {
      return 'No account found with this email. Please check your email or create a new account.';
    } else if (error.contains('wrong-password')) {
      return 'Incorrect password. Please try again.';
    } else if (error.contains('too-many-requests')) {
      return 'Too many failed attempts. Please try again later.';
    } else if (error.contains('network-request-failed')) {
      return 'Network error. Please check your internet connection.';
    } else {
      return 'Authentication failed. Please try again.';
    }
  }
}
