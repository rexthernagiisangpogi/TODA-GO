import 'package:flutter/material.dart';

class HowToUseScreen extends StatelessWidget {
  final String userType;

  const HowToUseScreen({super.key, required this.userType});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('How to use TODA GO'),
        backgroundColor: const Color(0xFF082FBD),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: userType == 'passenger' 
            ? _buildPassengerInstructions() 
            : _buildDriverInstructions(),
      ),
    );
  }

  List<Widget> _buildPassengerInstructions() {
    return [
      _buildHeader('Passenger Guide'),
      const SizedBox(height: 16),
      _buildSection(
        icon: Icons.map,
        title: '1. View Map',
        description: 'See your current location and nearby TODA drivers in real-time on the map.',
      ),
      _buildSection(
        icon: Icons.add_circle,
        title: '2. Request a Ride',
        description: 'Tap the Request button, select your TODA terminal, enter your pickup location, destination, and number of passengers. Then submit your request.',
      ),
      _buildSection(
        icon: Icons.search,
        title: '3. Wait for Driver',
        description: 'Your request will be sent to available TODA drivers. Wait for a driver to accept your ride request.',
      ),
      _buildSection(
        icon: Icons.person_pin_circle,
        title: '4. View Driver Profile',
        description: 'Once accepted, see your driver\'s profile picture, name, and real-time ratings. Tap on their profile to view full details including vehicle info and rating history.',
      ),
      _buildSection(
        icon: Icons.location_on,
        title: '5. Track Your Driver',
        description: 'Track your driver\'s location in real-time on the map as they arrive at your pickup location.',
      ),
      _buildSection(
        icon: Icons.check_circle,
        title: '6. Complete Ride',
        description: 'When you arrive at your destination, the driver will mark the ride as completed.',
      ),
      _buildSection(
        icon: Icons.star,
        title: '7. Rate Your Experience',
        description: 'After the ride, rate your driver (1-5 stars) and provide feedback to help maintain quality service.',
      ),
      _buildSection(
        icon: Icons.history,
        title: '8. View History',
        description: 'Check your past rides in the History tab. View ride details and ratings you\'ve given.',
      ),
      _buildSection(
        icon: Icons.person,
        title: '9. Manage Profile',
        description: 'Update your profile information, add a profile picture, and manage your account settings.',
      ),
      _buildSection(
        icon: Icons.cancel,
        title: '10. Cancel Ride',
        description: 'If needed, you can cancel a pending or accepted ride before the driver arrives.',
      ),
    ];
  }

  List<Widget> _buildDriverInstructions() {
    return [
      _buildHeader('Driver Guide'),
      const SizedBox(height: 16),
      _buildSection(
        icon: Icons.person,
        title: '1. Set Up Profile',
        description: 'Complete your profile with TODA affiliation, vehicle information, license details, and profile picture. Tap "Edit TODA" to select your TODA terminal.',
      ),
      _buildSection(
        icon: Icons.power_settings_new,
        title: '2. Go Online',
        description: 'Toggle your status to online to start receiving ride requests from passengers in your area.',
      ),
      _buildSection(
        icon: Icons.notifications,
        title: '3. Receive Requests',
        description: 'You\'ll receive ride requests showing passenger profile picture, name, pickup location, destination, and passenger count. Tap on passenger info to view their full profile.',
      ),
      _buildSection(
        icon: Icons.check_circle,
        title: '4. Accept Ride',
        description: 'Review the request details and tap Accept. The passenger will be notified immediately and can see your profile.',
      ),
      _buildSection(
        icon: Icons.location_on,
        title: '5. Navigate to Passenger',
        description: 'Use the map to navigate to the passenger\'s pickup location. Your location is shared in real-time with the passenger.',
      ),
      _buildSectionWithCustomIcon(
        title: '6. Complete Trip',
        description: 'Once the passenger is in your TODA tricycle, navigate to the destination and mark the ride as completed when you arrive.',
      ),
      _buildSection(
        icon: Icons.star,
        title: '7. Receive Ratings',
        description: 'After completing a ride, passengers will rate you. View your real-time ratings and rating history in your profile.',
      ),
      _buildSection(
        icon: Icons.history,
        title: '8. View History',
        description: 'Check your completed rides in the History tab. View ride details and track your earnings.',
      ),
      _buildSection(
        icon: Icons.trending_up,
        title: '9. Build Reputation',
        description: 'Maintain high ratings to build trust with passengers and grow your TODA business. View all your ratings in the Reviews tab.',
      ),
      _buildSection(
        icon: Icons.edit,
        title: '10. Update TODA Info',
        description: 'Keep your TODA affiliation, vehicle info, and license details up to date in your profile settings.',
      ),
      _buildSection(
        icon: Icons.cancel,
        title: '11. Decline Requests',
        description: 'If you cannot accept a ride request, decline it and it will be sent to other available TODA drivers.',
      ),
    ];
  }

  Widget _buildHeader(String title) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF082FBD), Color(0xFF3D64FF)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFF082FBD).withOpacity(0.1),
              child: Icon(icon, color: const Color(0xFF082FBD), size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF082FBD),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionWithCustomIcon({
    required String title,
    required String description,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFF082FBD).withOpacity(0.1),
              child: Image.asset(
                'assets/icons/TODA2.png',
                width: 24,
                height: 24,
                fit: BoxFit.contain,
                color: const Color(0xFF082FBD),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF082FBD),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
