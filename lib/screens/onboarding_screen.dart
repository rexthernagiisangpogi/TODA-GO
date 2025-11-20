import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  final String userType; // 'passenger' or 'driver'
  final VoidCallback onComplete;

  const OnboardingScreen({
    super.key,
    required this.userType,
    required this.onComplete,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late List<OnboardingSlide> _slides;

  @override
  void initState() {
    super.initState();
    _slides = _getSlides();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<OnboardingSlide> _getSlides() {
    if (widget.userType == 'passenger') {
      return [
        OnboardingSlide(
          title: 'Welcome to TODA GO',
          description: 'Your reliable TODA tricycle booking app for convenient and safe transportation',
          icon: Icons.waving_hand,
          color: const Color(0xFF082FBD),
        ),
        OnboardingSlide(
          title: 'Book Your Ride',
          description: 'Tap on the map to set your pickup location and request a TODA tricycle driver',
          icon: Icons.location_on,
          color: const Color(0xFF3D64FF),
        ),
        OnboardingSlide(
          title: 'Meet Your Driver',
          description: 'View your driver\'s profile, photo, and real-time ratings. Track their location as they arrive',
          icon: Icons.person_pin_circle,
          color: const Color(0xFF5B7CFF),
          useCustomIcon: true,
        ),
        OnboardingSlide(
          title: 'Safe & Connected',
          description: 'See driver details before your ride. Rate your experience to help maintain quality service',
          icon: Icons.star_outline,
          color: const Color(0xFF7A94FF),
        ),
        OnboardingSlide(
          title: 'You\'re All Set!',
          description: 'Start booking rides with verified TODA drivers and enjoy convenient transportation',
          icon: Icons.check_circle,
          color: const Color(0xFF4CAF50),
        ),
      ];
    } else {
      return [
        OnboardingSlide(
          title: 'Welcome TODA Driver!',
          description: 'Join TODA GO and start earning by providing safe tricycle rides to passengers',
          icon: Icons.waving_hand,
          color: const Color(0xFF082FBD),
        ),
        OnboardingSlide(
          title: 'Set Up Your Profile',
          description: 'Add your TODA affiliation, vehicle info, and license details. Your profile helps passengers trust you',
          icon: Icons.badge_outlined,
          color: const Color(0xFF3D64FF),
          useCustomIcon: true,
        ),
        OnboardingSlide(
          title: 'Go Online & Accept',
          description: 'Toggle online to receive ride requests. View passenger details and location before accepting',
          icon: Icons.power_settings_new,
          color: const Color(0xFF5B7CFF),
        ),
        OnboardingSlide(
          title: 'Complete Rides',
          description: 'Navigate to pickup location, complete the ride safely, and receive your payment',
          icon: Icons.navigation,
          color: const Color(0xFF7A94FF),
        ),
        OnboardingSlide(
          title: 'Build Your Reputation',
          description: 'Earn ratings from passengers. View your rating history and grow your TODA business',
          icon: Icons.trending_up,
          color: const Color(0xFF4CAF50),
        ),
      ];
    }
  }

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
        child: SafeArea(
          child: Column(
            children: [
              // Skip button
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 60), // Spacer
                    Text(
                      'Tutorial',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    TextButton(
                      onPressed: _completeOnboarding,
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Page indicator
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _slides.length,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentPage == index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? const Color(0xFF082FBD)
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
              
              // Slides
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  itemCount: _slides.length,
                  itemBuilder: (context, index) {
                    return _buildSlide(_slides[index]);
                  },
                ),
              ),
              
              // Navigation buttons
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Previous button
                    _currentPage > 0
                        ? OutlinedButton(
                            onPressed: _previousPage,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF082FBD)),
                              foregroundColor: const Color(0xFF082FBD),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                            ),
                            child: const Text('Previous'),
                          )
                        : const SizedBox(width: 80),
                    
                    // Next/Get Started button
                    ElevatedButton(
                      onPressed: _currentPage == _slides.length - 1
                          ? _completeOnboarding
                          : _nextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF082FBD),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        elevation: 4,
                      ),
                      child: Text(
                        _currentPage == _slides.length - 1
                            ? 'Get Started'
                            : 'Next',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlide(OnboardingSlide slide) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: slide.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(60),
              border: Border.all(
                color: slide.color.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: slide.useCustomIcon
                ? Image.asset(
                    'assets/icons/TODA2.png',
                    width: 60,
                    height: 60,
                    fit: BoxFit.contain,
                    color: slide.color,
                  )
                : Icon(
                    slide.icon,
                    size: 60,
                    color: slide.color,
                  ),
          ),
          
          const SizedBox(height: 40),
          
          // Title
          Text(
            slide.title,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: slide.color,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 20),
          
          // Description
          Text(
            slide.description,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _completeOnboarding() async {
    // Mark onboarding as completed for this user type
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed_${widget.userType}', true);
    
    widget.onComplete();
  }
}

class OnboardingSlide {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final bool useCustomIcon;

  OnboardingSlide({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.useCustomIcon = false,
  });
}

// Helper class to manage onboarding state
class OnboardingManager {
  static const String _passengerKey = 'onboarding_completed_passenger';
  static const String _driverKey = 'onboarding_completed_driver';

  static Future<bool> hasCompletedOnboarding(String userType) async {
    final prefs = await SharedPreferences.getInstance();
    final key = userType == 'passenger' ? _passengerKey : _driverKey;
    return prefs.getBool(key) ?? false;
  }

  static Future<void> markOnboardingCompleted(String userType) async {
    final prefs = await SharedPreferences.getInstance();
    final key = userType == 'passenger' ? _passengerKey : _driverKey;
    await prefs.setBool(key, true);
  }

  static Future<void> resetOnboarding(String userType) async {
    final prefs = await SharedPreferences.getInstance();
    final key = userType == 'passenger' ? _passengerKey : _driverKey;
    await prefs.remove(key);
  }

  static Future<void> resetAllOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_passengerKey);
    await prefs.remove(_driverKey);
  }
}
