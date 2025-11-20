import 'package:flutter/material.dart';
import 'passenger_screen.dart';
import 'driver_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade50,
              Colors.grey.shade100,
            ],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo from assets
                _buildLogoFromAssets(),
                
                const SizedBox(height: 8),
                const Text(
                  "TODA GO",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 8, 47, 189),
                  ),
                ),
                const SizedBox(height: 40),
                const Text(
                  "Select your role to continue",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 40),
                _buildRoleButton(
                  context: context,
                  title: "Passenger",
                  icon: Icons.person,
                  color: Colors.blue,
                  onPressed: () async {
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PassengerScreen()),
                    );
                  },
                ),
                const SizedBox(height: 20),
                _buildDriverButton(
                  context: context,
                  title: "Driver",
                  onPressed: () async {
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DriverScreen()),
                    );
                  },
                ),
                const SizedBox(height: 60),
                const Text(
                  "Track your ride with ease",
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Logo from assets
  Widget _buildLogoFromAssets() {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: Image.asset(
          'assets/images/TODAGO.png', // Your logo path
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildLogoPlaceholder(); // Fallback if image not found
          },
        ),
      ),
    );
  }

  // Placeholder logo (fallback)
  Widget _buildLogoPlaceholder() {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 8, 47, 189),
        borderRadius: BorderRadius.circular(100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Image.asset(
        'assets/icons/TODA2.png',
        width: 90,
        height: 90,
        fit: BoxFit.contain,
        colorBlendMode: BlendMode.srcIn,
        color: Colors.white,
      ),
    );
  }

  // Custom driver button with asset icon
  Widget _buildDriverButton({
    required BuildContext context,
    required String title,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 80,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Custom asset icon for driver
            _buildDriverIcon(),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Driver icon from assets with fallback
  Widget _buildDriverIcon() {
    return SizedBox(
      width: 28,
      height: 28,
      child: Image.asset(
        'assets/icons/TODA2.png', // Your driver icon path
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Fallback to default icon if asset not found
          return Image.asset(
            'assets/icons/TODA2.png',
            width: 28,
            height: 28,
            fit: BoxFit.contain,
            color: Colors.white,
          );
        },
      ),
    );
  }

  // Original passenger button (unchanged)
  Widget _buildRoleButton({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 80,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}