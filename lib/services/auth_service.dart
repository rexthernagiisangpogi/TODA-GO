import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum UserType { driver, passenger }

enum UserRole { 
  // Driver roles
  standardDriver,
  premiumDriver,
  adminDriver,
  
  // Passenger roles
  regularPassenger,
  vipPassenger,
  corporatePassenger,
  
  // Admin roles
  systemAdmin,
  moderator
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  UserType? _currentUserType;
  UserRole? _currentUserRole;
  Map<String, dynamic>? _currentUserData;

  // Getters
  User? get currentUser => _auth.currentUser;
  UserType? get currentUserType => _currentUserType;
  UserRole? get currentUserRole => _currentUserRole;
  Map<String, dynamic>? get currentUserData => _currentUserData;
  bool get isLoggedIn => _auth.currentUser != null && _currentUserType != null;

  // Check if current user matches the required type
  bool isUserType(UserType requiredType) {
    return isLoggedIn && _currentUserType == requiredType;
  }

  // Wait for user type to become available (used right after registration)
  Future<UserType?> waitForUserType({int retries = 3, Duration delay = const Duration(milliseconds: 500)}) async {
    for (int i = 0; i < retries; i++) {
      final ok = await initializeUserData();
      if (ok && _currentUserType != null) {
        return _currentUserType;
      }
      await Future.delayed(delay);
    }
    return _currentUserType; // may be null
  }

  // Check if current user has the required role
  bool hasRole(UserRole requiredRole) {
    return isLoggedIn && _currentUserRole == requiredRole;
  }

  // Check if current user has any of the specified roles
  bool hasAnyRole(List<UserRole> roles) {
    return isLoggedIn && _currentUserRole != null && roles.contains(_currentUserRole);
  }

  // Check if user is admin (system admin or moderator)
  bool get isAdmin => hasAnyRole([UserRole.systemAdmin, UserRole.moderator]);

  // Check if user is premium (premium driver or VIP passenger)
  bool get isPremiumUser => hasAnyRole([UserRole.premiumDriver, UserRole.vipPassenger]);

  // Helper method to convert role string to UserRole enum
  UserRole? _parseUserRole(String? roleString) {
    if (roleString == null) return null;
    
    switch (roleString) {
      case 'standardDriver':
        return UserRole.standardDriver;
      case 'premiumDriver':
        return UserRole.premiumDriver;
      case 'adminDriver':
        return UserRole.adminDriver;
      case 'regularPassenger':
        return UserRole.regularPassenger;
      case 'vipPassenger':
        return UserRole.vipPassenger;
      case 'corporatePassenger':
        return UserRole.corporatePassenger;
      case 'systemAdmin':
        return UserRole.systemAdmin;
      case 'admin': // alias support for admin role
        return UserRole.systemAdmin;
      case 'moderator':
        return UserRole.moderator;
      default:
        return null;
    }
  }

  // Helper method to convert UserRole enum to string
  String _roleToString(UserRole role) {
    switch (role) {
      case UserRole.standardDriver:
        return 'standardDriver';
      case UserRole.premiumDriver:
        return 'premiumDriver';
      case UserRole.adminDriver:
        return 'adminDriver';
      case UserRole.regularPassenger:
        return 'regularPassenger';
      case UserRole.vipPassenger:
        return 'vipPassenger';
      case UserRole.corporatePassenger:
        return 'corporatePassenger';
      case UserRole.systemAdmin:
        return 'systemAdmin';
      case UserRole.moderator:
        return 'moderator';
    }
  }

  // Initialize user data from Firestore
  Future<bool> initializeUserData() async {
    final user = _auth.currentUser;
    if (user == null) {
      _currentUserType = null;
      _currentUserData = null;
      return false;
    }

    try {
      // Attempt to read the user document. If it doesn't exist immediately,
      // retry once after a short delay to avoid race conditions right after registration.
      var userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        await Future.delayed(const Duration(milliseconds: 500));
        userDoc = await _firestore.collection('users').doc(user.uid).get();
        if (!userDoc.exists) {
          // Do NOT sign out here; simply report uninitialized state.
          _currentUserType = null;
          _currentUserRole = null;
          _currentUserData = null;
          return false;
        }
      }

      _currentUserData = userDoc.data();
      final userTypeString = _currentUserData?['userType'] as String?;
      final userRoleString = _currentUserData?['role'] as String?;
      
      if (userTypeString == 'driver') {
        _currentUserType = UserType.driver;
      } else if (userTypeString == 'passenger') {
        _currentUserType = UserType.passenger;
      } else {
        // Invalid or missing userType; keep session, just mark as uninitialized.
        _currentUserType = null;
        _currentUserRole = null;
        return false;
      }

      // Parse user role - if not set, assign default role based on user type
      _currentUserRole = _parseUserRole(userRoleString);
      if (_currentUserRole == null) {
        // Assign default role based on user type
        if (_currentUserType == UserType.driver) {
          _currentUserRole = UserRole.standardDriver;
        } else if (_currentUserType == UserType.passenger) {
          _currentUserRole = UserRole.regularPassenger;
        }
        
        // Update Firestore with default role
        if (_currentUserRole != null) {
          await _firestore.collection('users').doc(user.uid).update({
            'role': _roleToString(_currentUserRole!),
          });
        }
      }

      return true;
    } catch (e) {
      // Do NOT sign out on initialization failure; allow UI to retry gracefully.
      _currentUserType = null;
      _currentUserRole = null;
      _currentUserData = null;
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
    UserRole? role,
  }) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await userCredential.user?.updateDisplayName(name);

      // Store driver data
      final driverRole = role ?? UserRole.standardDriver;
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'name': name,
        'email': email,
        'userType': 'driver',
        'role': _roleToString(driverRole),
        'licenseNumber': licenseNumber,
        'vehicleInfo': vehicleInfo,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Initialize user data
      await initializeUserData();
      return null; // Success
    } catch (e) {
      return _getFirebaseErrorMessage(e.toString());
    }
  }

  // Register as passenger
  Future<String?> registerPassenger({
    required String name,
    required String email,
    required String password,
    UserRole? role,
  }) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await userCredential.user?.updateDisplayName(name);

      // Store passenger data
      final passengerRole = role ?? UserRole.regularPassenger;
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'name': name,
        'email': email,
        'userType': 'passenger',
        'role': _roleToString(passengerRole),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Initialize user data
      await initializeUserData();
      return null; // Success
    } catch (e) {
      return _getFirebaseErrorMessage(e.toString());
    }
  }

  // Login with user type validation
  Future<String?> signIn({
    required String email,
    required String password,
    required UserType expectedUserType,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Initialize and validate user data
      final success = await initializeUserData();
      if (!success) {
        return "Account not found or invalid. Please register first.";
      }

      // Check if user type matches expected type
      if (_currentUserType != expectedUserType) {
        await signOut();
        final expectedTypeString = expectedUserType == UserType.driver ? 'driver' : 'passenger';
        final actualTypeString = _currentUserType == UserType.driver ? 'driver' : 'passenger';
        return "This account is registered as a $actualTypeString. Please use the $expectedTypeString screen or create a $expectedTypeString account.";
      }

      return null; // Success
    } catch (e) {
      return _getFirebaseErrorMessage(e.toString());
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    _currentUserType = null;
    _currentUserRole = null;
    _currentUserData = null;
  }

  // Validate user type for screen access
  Future<bool> validateUserTypeForScreen(UserType requiredType) async {
    if (_auth.currentUser == null) return true; // Allow access to login screen

    if (_currentUserType == null) {
      final success = await initializeUserData();
      if (!success) return true; // Allow access to login screen if data invalid
    }

    return _currentUserType == requiredType;
  }

  // Update user role (admin only functionality)
  Future<String?> updateUserRole(String userId, UserRole newRole) async {
    try {
      // Check if current user is admin
      if (!isAdmin) {
        return "Insufficient permissions. Only admins can update user roles.";
      }

      await _firestore.collection('users').doc(userId).update({
        'role': _roleToString(newRole),
        'roleUpdatedAt': FieldValue.serverTimestamp(),
      });

      // If updating current user's role, refresh the data
      if (_auth.currentUser?.uid == userId) {
        await initializeUserData();
      }

      return null; // Success
    } catch (e) {
      return "Failed to update user role: ${e.toString()}";
    }
  }

  // Get user role display name
  String getRoleDisplayName(UserRole role) {
    switch (role) {
      case UserRole.standardDriver:
        return 'Standard Driver';
      case UserRole.premiumDriver:
        return 'Premium Driver';
      case UserRole.adminDriver:
        return 'Admin Driver';
      case UserRole.regularPassenger:
        return 'Regular Passenger';
      case UserRole.vipPassenger:
        return 'VIP Passenger';
      case UserRole.corporatePassenger:
        return 'Corporate Passenger';
      case UserRole.systemAdmin:
        return 'System Administrator';
      case UserRole.moderator:
        return 'Moderator';
    }
  }

  // Get available roles for user type
  List<UserRole> getAvailableRolesForUserType(UserType userType) {
    switch (userType) {
      case UserType.driver:
        return [
          UserRole.standardDriver,
          UserRole.premiumDriver,
          UserRole.adminDriver,
        ];
      case UserType.passenger:
        return [
          UserRole.regularPassenger,
          UserRole.vipPassenger,
          UserRole.corporatePassenger,
        ];
    }
  }

  // Check if role is valid for user type
  bool isRoleValidForUserType(UserRole role, UserType userType) {
    return getAvailableRolesForUserType(userType).contains(role);
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
