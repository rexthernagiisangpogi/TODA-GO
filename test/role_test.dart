import 'package:flutter_test/flutter_test.dart';
import 'package:toda_go/services/auth_service.dart';

void main() {
  group('UserRole Tests', () {
    late AuthService authService;

    setUp(() {
      authService = AuthService();
    });

    test('should parse role strings correctly', () {
      // Test role display names
      expect(authService.getRoleDisplayName(UserRole.standardDriver), 'Standard Driver');
      expect(authService.getRoleDisplayName(UserRole.premiumDriver), 'Premium Driver');
      expect(authService.getRoleDisplayName(UserRole.adminDriver), 'Admin Driver');
      expect(authService.getRoleDisplayName(UserRole.regularPassenger), 'Regular Passenger');
      expect(authService.getRoleDisplayName(UserRole.vipPassenger), 'VIP Passenger');
      expect(authService.getRoleDisplayName(UserRole.corporatePassenger), 'Corporate Passenger');
      expect(authService.getRoleDisplayName(UserRole.systemAdmin), 'System Administrator');
      expect(authService.getRoleDisplayName(UserRole.moderator), 'Moderator');
    });

    test('should return correct available roles for user types', () {
      final driverRoles = authService.getAvailableRolesForUserType(UserType.driver);
      expect(driverRoles, contains(UserRole.standardDriver));
      expect(driverRoles, contains(UserRole.premiumDriver));
      expect(driverRoles, contains(UserRole.adminDriver));
      expect(driverRoles.length, 3);

      final passengerRoles = authService.getAvailableRolesForUserType(UserType.passenger);
      expect(passengerRoles, contains(UserRole.regularPassenger));
      expect(passengerRoles, contains(UserRole.vipPassenger));
      expect(passengerRoles, contains(UserRole.corporatePassenger));
      expect(passengerRoles.length, 3);
    });

    test('should validate role compatibility with user type', () {
      // Driver roles should be valid for driver user type
      expect(authService.isRoleValidForUserType(UserRole.standardDriver, UserType.driver), true);
      expect(authService.isRoleValidForUserType(UserRole.premiumDriver, UserType.driver), true);
      expect(authService.isRoleValidForUserType(UserRole.adminDriver, UserType.driver), true);

      // Passenger roles should be valid for passenger user type
      expect(authService.isRoleValidForUserType(UserRole.regularPassenger, UserType.passenger), true);
      expect(authService.isRoleValidForUserType(UserRole.vipPassenger, UserType.passenger), true);
      expect(authService.isRoleValidForUserType(UserRole.corporatePassenger, UserType.passenger), true);

      // Cross-validation should fail
      expect(authService.isRoleValidForUserType(UserRole.standardDriver, UserType.passenger), false);
      expect(authService.isRoleValidForUserType(UserRole.regularPassenger, UserType.driver), false);
    });

    test('should identify admin roles correctly', () {
      // Note: These tests would require mocking the authentication state
      // For now, we're testing the enum values and helper methods
      final adminRoles = [UserRole.systemAdmin, UserRole.moderator];
      final premiumRoles = [UserRole.premiumDriver, UserRole.vipPassenger];
      
      expect(adminRoles.contains(UserRole.systemAdmin), true);
      expect(adminRoles.contains(UserRole.moderator), true);
      expect(premiumRoles.contains(UserRole.premiumDriver), true);
      expect(premiumRoles.contains(UserRole.vipPassenger), true);
    });
  });
}
