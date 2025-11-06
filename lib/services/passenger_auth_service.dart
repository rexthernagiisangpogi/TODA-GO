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
        await signOut();
        return false;
      }

      final userData = userDoc.data()!;
      if (userData['userType'] != 'passenger') {
        await signOut();
        return false;
      }

      _currentPassengerData = userData;
      return true;
    } catch (e) {
      await signOut();
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
    
    try {
      // Create Firebase Auth user
      print('Step 1: Creating Firebase Auth user...');
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      print('Step 1 SUCCESS: User created with UID: ${credential.user?.uid}');
      
      if (credential.user == null) {
        print('ERROR: User is null after creation');
        return 'Account creation failed';
      }
      
      // Update display name
      print('Step 2: Setting display name...');
      await credential.user!.updateDisplayName(name);
      print('Step 2 SUCCESS: Display name set');
      
      // Create Firestore document
      print('Step 3: Creating Firestore document...');
      await FirebaseFirestore.instance.collection('users').doc(credential.user!.uid).set({
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
      
      if (e.toString().contains('email-already-in-use')) {
        return 'Email already registered. Try logging in instead.';
      }
      if (e.toString().contains('weak-password')) {
        return 'Password too weak. Use at least 6 characters.';
      }
      if (e.toString().contains('invalid-email')) {
        return 'Invalid email format.';
      }
      
      return 'Registration failed: $e';
    }
  }
  

  // Login as passenger
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Initialize and validate passenger data
      final success = await initializePassengerData();
      if (!success) {
        return "Account not found or not registered as a passenger. Please register as a passenger first.";
      }

      return null; // Success
    } catch (e) {
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
