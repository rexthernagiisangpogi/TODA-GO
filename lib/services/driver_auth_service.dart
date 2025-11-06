import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DriverAuthService {
  static final DriverAuthService _instance = DriverAuthService._internal();
  factory DriverAuthService() => _instance;
  DriverAuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? _currentDriverData;

  // Getters
  User? get currentUser => _auth.currentUser;
  Map<String, dynamic>? get currentDriverData => _currentDriverData;
  bool get isLoggedIn => _auth.currentUser != null && _currentDriverData != null;
  
  // Check if current session is valid for driver
  Future<bool> isValidDriverSession() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return false;
      
      final userData = userDoc.data()!;
      return userData['userType'] == 'driver';
    } catch (e) {
      // Do not sign out here; just report invalid
      return false;
    }
  }

  // Initialize driver data from Firestore
  Future<bool> initializeDriverData() async {
    final user = _auth.currentUser;
    if (user == null) {
      _currentDriverData = null;
      return false;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        _currentDriverData = null;
        return false;
      }

      final userData = userDoc.data()!;
      if (userData['userType'] != 'driver') {
        _currentDriverData = null;
        return false;
      }

      _currentDriverData = userData;
      return true;
    } catch (e) {
      _currentDriverData = null;
      return false;
    }
  }

  // Register as driver
  Future<String?> registerDriver({
    required String name,
    required String email,
    required String password,
    required String licenseNumber,
    required String vehicleInfo,
    required String toda,
  }) async {
    try {
      print('Starting driver registration for: $email');
      
      // Create the user account
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      print('Firebase Auth user created: ${userCredential.user?.uid}');

      if (userCredential.user == null) {
        print('User credential is null');
        return 'Failed to create account. Please try again.';
      }

      final user = userCredential.user!;
      print('User UID: ${user.uid}');
      print('User email: ${user.email}');

      // Update display name
      await user.updateDisplayName(name);
      print('Display name updated to: $name');

      // Store driver data in Firestore
      final userData = {
        'name': name,
        'email': email,
        'userType': 'driver',
        'role': 'standardDriver',
        'licenseNumber': licenseNumber,
        'vehicleInfo': vehicleInfo,
        'toda': toda,
        'createdAt': FieldValue.serverTimestamp(),
      };
      
      print('Attempting to write to Firestore: ${user.uid}');
      await _firestore.collection('users').doc(user.uid).set(userData);
      print('Firestore document created successfully');

      // Set local data
      _currentDriverData = {
        'name': name,
        'email': email,
        'userType': 'driver',
        'role': 'standardDriver',
        'licenseNumber': licenseNumber,
        'vehicleInfo': vehicleInfo,
        'toda': toda,
      };
      
      print('Driver registration completed successfully');
      return null; // Success
    } on FirebaseAuthException catch (e) {
      print('FirebaseAuthException: ${e.code} - ${e.message}');
      return _getFirebaseAuthErrorMessage(e.code);
    } catch (e) {
      print('General registration error: ${e.toString()}');
      print('Error type: ${e.runtimeType}');
      return 'Registration failed: ${e.toString()}';
    }
  }
  
  // Specific Firebase Auth error handler
  String _getFirebaseAuthErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'email-already-in-use':
        return 'This email is already registered. Please use a different email or try logging in.';
      case 'weak-password':
        return 'Password is too weak. Please use at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'operation-not-allowed':
        return 'Email/password registration is not enabled. Please contact support.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      default:
        return 'Registration failed: $errorCode. Please try again.';
    }
  }

  // Login as driver
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Fetch user doc and validate userType == 'driver'
      final user = _auth.currentUser;
      if (user == null) {
        return 'Authentication failed. Please try again.';
      }

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        await signOut();
        return 'Account not found. Please register as a driver.';
      }
      final data = doc.data() ?? {};
      if ((data['userType'] as String?) != 'driver') {
        await signOut();
        final actual = (data['userType'] as String?) ?? 'passenger';
        return 'This account is registered as a $actual. Please use the correct screen or create a driver account.';
      }

      _currentDriverData = data;
      return null; // Success
    } catch (e) {
      return _getFirebaseErrorMessage(e.toString());
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    _currentDriverData = null;
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
