import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../services/passenger_auth_service.dart';
import 'settings_screen.dart';
import 'driver_reviews_screen.dart';
import '../widgets/rating_dialog.dart';
import '../widgets/chat_screen.dart';
import '../services/notification_service.dart';
import '../widgets/rating_display.dart';

class PassengerScreen extends StatefulWidget {
  static const String routeName = '/passenger';

  const PassengerScreen({super.key});

  @override
  State<PassengerScreen> createState() => _PassengerScreenState();
}

class _PassengerScreenState extends State<PassengerScreen> {
  static const String _mapTilerKey = 'dLSnXdAyPtOhZ6BaILyI';
  final PassengerAuthService _passengerAuthService = PassengerAuthService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passengerCountController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  String? _selectedToda;
  bool _isRegistering = false;
  String _errorMessage = '';
  bool _hasActiveRide = false;
  String? _activePickupId;
  bool _emailError = false;
  bool _passwordError = false;
  bool _passwordObscured = true;
  String? _selectedPaymentMethod;

  // Bottom navigation: 0 = Map, 1 = Request, 2 = History, 3 = Profile
  int _currentTabIndex = 0;

  LatLng? _currentLocation;
  
  // Naval, Biliran coordinates and bounds
  static const LatLng _navalCenter = LatLng(11.56179, 124.420000);
  static final LatLngBounds _navalBounds = LatLngBounds(
    const LatLng(11.48, 124.35), // Southwest corner (slightly more west)
    const LatLng(11.66, 124.50), // Northeast corner (expanded further east only)
  );

  final List<String> _todaOptions = [
    'NATODA',
    'CARNATODA',
    'ALTODA',
    'LAPNATODA',
    'Culaba',
    'Cabucgayan',
    'Maripipi',
    'Biliran',
  ];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    // Initialize FCM for passenger
    NotificationService().initialize(context: context);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _passengerCountController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Avoid flashing a loading screen on first entry; show the auth form instead
          return _buildAuthForm();
        }

        final user = snapshot.data;
        if (user == null) {
          return _buildAuthForm();
        }

        // Validate that the logged-in user is a passenger before showing dashboard
        return FutureBuilder<bool>(
          future: _passengerAuthService.initializePassengerData(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: Text('Loading...')),
              );
            }
            final isValidPassenger = snap.data == true;
            if (!isValidPassenger) {
              // If not a passenger, fall back to auth form on this screen
              return _buildAuthForm();
            }
            return _buildMainContent();
          },
        );
      },
    );
  }

  // Show full ride information when a history item is tapped
  void _showRideDetails(Map<String, dynamic> pickup, String pickupId) {
    final String status = (pickup['status'] ?? 'unknown').toString();
    final String toda = (pickup['toda'] ?? 'Unknown').toString();
    final int count = (pickup['count'] ?? 0) is int
        ? pickup['count'] as int
        : int.tryParse(pickup['count']?.toString() ?? '0') ?? 0;
    final String driverId = (pickup['driverId'] ?? '').toString();
    final String cancelReason = (pickup['cancelReason'] ?? '').toString().trim();
    final Timestamp? ts = pickup['timestamp'] as Timestamp?;
    // Support both GeoPoint and Map {latitude/longitude}
    GeoPoint? location;
    final dynamic rawLoc = pickup['location'];
    if (rawLoc is GeoPoint) {
      location = rawLoc;
    } else if (rawLoc is Map<String, dynamic>) {
      final lat = rawLoc['latitude'] ?? rawLoc['lat'];
      final lng = rawLoc['longitude'] ?? rawLoc['lng'];
      if (lat is num && lng is num) {
        location = GeoPoint(lat.toDouble(), lng.toDouble());
      }
    }

    String fullDate = '—';
    if (ts != null) {
      final dt = ts.toDate();
      fullDate = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
            minHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long, color: Color(0xFF082FBD), size: 30),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Ride Details',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF082FBD),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),
              ),
              // Content
              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(status).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: _getStatusColor(status)),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: TextStyle(
                                          color: _getStatusColor(status),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '#$pickupId',
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _buildInfoItem(Icons.place_outlined, 'TODA', toda),
                                const SizedBox(height: 8),
                                _buildInfoItem(Icons.people_alt_outlined, 'Passengers', '$count'),
                                const SizedBox(height: 8),
                                _buildInfoItem(Icons.access_time, 'Requested', fullDate),
                                if (location != null) ...[
                                  const SizedBox(height: 8),
                                  _buildInfoItem(Icons.location_on_outlined, 'Location',
                                      'Lat: ${location.latitude.toStringAsFixed(5)}, Lng: ${location.longitude.toStringAsFixed(5)}'),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (status.toLowerCase().startsWith('cancel') && cancelReason.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Cancellation',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.cancel_outlined, color: Colors.red),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          cancelReason,
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        // Driver section
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Driver',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 8),
                                if (driverId.isEmpty)
                                  Text('Not yet assigned', style: TextStyle(color: Colors.grey.shade600))
                                else
                                  FutureBuilder<DocumentSnapshot>(
                                    future: FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(driverId)
                                        .get(),
                                    builder: (context, snap) {
                                      if (snap.connectionState == ConnectionState.waiting) {
                                        return const Padding(
                                          padding: EdgeInsets.symmetric(vertical: 8),
                                          child: SizedBox.shrink(),
                                        );
                                      }
                                      String driverName = 'Unknown';
                                      String email = '';
                                      String vehicle = '';
                                      if (snap.hasData && snap.data!.exists) {
                                        final d = snap.data!.data() as Map<String, dynamic>?;
                                        driverName = d?['name'] ?? 'Unknown';
                                        email = (d?['email'] ?? '').toString();
                                        vehicle = (d?['vehicleInfo'] ?? '').toString();
                                      }
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _buildInfoItem(Icons.person_outline, 'Name', driverName),
                                          if (email.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            _buildInfoItem(Icons.email_outlined, 'Email', email),
                                          ],
                                          if (vehicle.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            _buildInfoItem(Icons.directions_bike_outlined, 'Vehicle', vehicle),
                                          ],
                                        ],
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Quick actions
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: pickupId));
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Ride ID copied')),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.copy, color: Color(0xFF082FBD)),
                                label: const Text('Copy ID'),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF082FBD)),
                                  foregroundColor: const Color(0xFF082FBD),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: location == null
                                    ? null
                                    : () async {
                                        final loc = location!; // safe: button disabled when location is null
                                        final txt = '${loc.latitude.toStringAsFixed(6)},${loc.longitude.toStringAsFixed(6)}';
                                        await Clipboard.setData(ClipboardData(text: txt));
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Location copied')),
                                          );
                                        }
                                      },
                                icon: const Icon(Icons.location_on, color: Color(0xFF082FBD)),
                                label: const Text('Copy Location'),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF082FBD)),
                                  foregroundColor: const Color(0xFF082FBD),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: driverId.isEmpty
                                ? null
                                : () async {
                                    Navigator.of(context).pop();
                                    await _showDriverPublicProfile(driverId: driverId, pickupId: pickupId);
                                  },
                            icon: const Icon(Icons.person, color: Colors.white),
                            label: const Text('View Driver Profile'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF082FBD),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  void _showLogoutDialog() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.red),
            SizedBox(width: 12),
            Text('Logout'),
          ],
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await _logout();
    }
  }

  Widget _buildMainContent() {
    return Scaffold(
      appBar: AppBar(
        leading: null,
        title: Text(
          _currentTabIndex == 3
              ? 'Passenger Profile'
              : _currentTabIndex == 2
                  ? 'Ride History'
                  : 'Passenger Dashboard',
        ),
        backgroundColor: const Color(0xFF082FBD),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: _currentTabIndex == 3
          ? _buildPassengerProfileContent()
          : _currentTabIndex == 2
              ? _buildPassengerHistoryContent()
              : Stack(
        children: [
          // Full screen map
          FlutterMap(
            options: MapOptions(
              initialCenter: _currentLocation ?? _navalCenter,
              initialZoom: 13.0,
              maxZoom: 22,
              cameraConstraint: CameraConstraint.contain(
                bounds: _navalBounds,
              ),
            ),
            children: [
              // MapTiler hybrid (imagery + labels) as sole base layer
              TileLayer(
                urlTemplate: 'https://api.maptiler.com/maps/hybrid/256/{z}/{x}/{y}.jpg?key=${_mapTilerKey}',
                userAgentPackageName: 'com.example.toda_go',
                tileProvider: NetworkTileProvider(),
                maxNativeZoom: 22,
              ),
              if (_currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentLocation!,
                      child: Stack(
                        alignment: Alignment.center,
                        children: const [
                          Icon(
                            Icons.location_on,
                            color: Colors.white,
                            size: 40,
                          ),
                          Icon(
                            Icons.location_on,
                            color: Color(0xFF082FBD),
                            size: 34,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              // (Attribution widget removed per request)
            ],
          ),
          // Floating "My Location" button
          Positioned(
            top: 16,
            right: 16,
            child: FloatingActionButton.small(
              onPressed: _getCurrentLocation,
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF082FBD),
              child: const Icon(Icons.my_location),
            ),
          ),
          // (Removed map style toggle FAB; hybrid is always on)
          // Cancel and Complete buttons (shown when ride is active)
          if (_hasActiveRide)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _cancelRide,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel Ride',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        onTap: (index) {
          if (index == 1) {
            // Request a Ride opens bottom sheet, keep current tab unchanged
            _showRequestRideBottomSheet();
            return;
          }
          setState(() {
            _currentTabIndex = index;
          });
        },
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF082FBD),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(
              AssetImage('assets/icons/TODA2.png'),
              size: 24,
            ),
            label: 'Request',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  void _showRequestRideBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return Wrap(
              children: [
                AnimatedPadding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Handle bar for drag
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(top: 12, bottom: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Header
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF082FBD), Color(0xFF3D64FF)],
                          ),
                        ),
                        child: const ListTile(
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          title: Text('Request Ride', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                          subtitle: Text('Fill in the details below', style: TextStyle(color: Colors.white70)),
                        ),
                      ),
                      // Form Card
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                              // Left-aligned title matching input alignment
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Ride Details',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF082FBD),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // TODA Terminal Dropdown (moved down)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 4)),
                                  ],
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: Image.asset(
                                          'assets/icons/TODA2.png',
                                          fit: BoxFit.contain,
                                          color: const Color(0xFF082FBD),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: DropdownButton<String>(
                                          value: _selectedToda,
                                          hint: const Text('Select TODA'),
                                          isExpanded: true,
                                          items: _todaOptions.map((String toda) {
                                            return DropdownMenuItem<String>(
                                              value: toda,
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 12,
                                                    height: 12,
                                                    decoration: BoxDecoration(
                                                      color: _getTodaColor(toda),
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Text(toda),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (String? newValue) {
                                            setSheetState(() {
                                              _selectedToda = newValue;
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Destination Input
                              TextField(
                                controller: _destinationController,
                                textInputAction: TextInputAction.next,
                                onChanged: (_) => setSheetState(() {}),
                                decoration: InputDecoration(
                                  hintText: 'Enter destination',
                                  prefixIcon: const Icon(
                                    Icons.place,
                                    color: Color(0xFF082FBD),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFF082FBD), width: 2),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Passenger count and Payment method side-by-side
                              Row(
                                children: [
                                  Expanded(
                                    child: Builder(
                                      builder: (context) {
                                        final text = _passengerCountController.text.trim();
                                        final parsed = int.tryParse(text);
                                        final overLimit = parsed != null && parsed > 7;
                                        return TextField(
                                          controller: _passengerCountController,
                                          keyboardType: TextInputType.number,
                                          onChanged: (_) => setSheetState(() {}),
                                          style: TextStyle(
                                            color: overLimit ? Colors.red : Colors.black,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: 'Enter number of passengers',
                                            prefixIcon: const Icon(
                                              Icons.people,
                                              color: Color(0xFF082FBD),
                                            ),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(color: overLimit ? Colors.red : Colors.grey.shade300),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(color: overLimit ? Colors.red : Colors.grey.shade300),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(color: overLimit ? Colors.red : Color(0xFF082FBD), width: 2),
                                            ),
                                            contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 10,
                                            ),
                                            helperText: overLimit ? 'Maximum allowed is 7 passengers' : null,
                                            helperStyle: const TextStyle(color: Colors.red),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey.shade300),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 4)),
                                        ],
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: Row(
                                          children: [
                                            const Icon(Icons.attach_money, color: Color(0xFF082FBD)),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: DropdownButton<String>(
                                                value: _selectedPaymentMethod,
                                                hint: const Text('Select payment method'),
                                                isExpanded: true,
                                                items: const [
                                                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                                                  DropdownMenuItem(value: 'gcash', child: Text('GCash')),
                                                ],
                                                onChanged: (String? v) {
                                                  setSheetState(() {
                                                    _selectedPaymentMethod = v;
                                                  });
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Action Buttons Row
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        side: const BorderSide(color: Color(0xFF082FBD)),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: const Text(
                                        'Cancel',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF082FBD),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: (_selectedToda != null &&
                                                 _selectedPaymentMethod != null &&
                                                 _passengerCountController.text.trim().isNotEmpty &&
                                                 _destinationController.text.trim().isNotEmpty &&
                                                 _currentLocation != null &&
                                                 (int.tryParse(_passengerCountController.text.trim()) ?? 0) > 0 &&
                                                 (int.tryParse(_passengerCountController.text.trim()) ?? 0) <= 7)
                                          ? () async {
                                              await _requestPickup();
                                              if (mounted) {
                                                Navigator.of(context).pop();
                                              }
                                            }
                                          : null,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF082FBD),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: const Text(
                                        'Request Pickup',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              ],
                            ),
                            // Close inner Padding inside Card
                          ),
                          // Close Card
                        ),
                        // Close outer Padding wrapping Card
                      ),
                      // Close children of main Column, then the Column itself
                    ],
                  ),
                  // Close Container
                ),
                // Close AnimatedPadding
              ),
            ],
          );
          },
        );
      },
    );
  }

  Color _getTodaColor(String toda) {
    switch (toda) {
      case 'NATODA':
        return Colors.blue;
      case 'CARNATODA':
        return Colors.green;
      case 'ALTODA':
        return Colors.orange;
      case 'LAPNATODA':
        return Colors.purple;
      case 'Culaba':
        return Colors.red;
      case 'Cabucgayan':
        return Colors.teal;
      case 'Maripipi':
        return Colors.indigo;
      case 'Biliran':
        return Colors.brown;
      default:
        return Colors.grey;
    }
  }

  Future<void> _requestPickup() async {
    if (_selectedToda == null || _passengerCountController.text.trim().isEmpty || _destinationController.text.trim().isEmpty) {
      return;
    }

    // Validate passenger count
    final passengerCountText = _passengerCountController.text.trim();
    final passengerCount = int.tryParse(passengerCountText);
    
    if (passengerCount == null || passengerCount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid number of passengers'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Enforce hard limit of 7 passengers
    if (passengerCount > 7) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maximum 7 passengers allowed'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (passengerCount > 20) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maximum 20 passengers allowed'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final destinationText = _destinationController.text.trim();
      final docRef = await FirebaseFirestore.instance.collection('pickups').add({
        'passengerId': user.uid,
        'passengerEmail': user.email,
        'toda': _selectedToda,
        'count': passengerCount,
        'destination': destinationText,
        'location': _currentLocation != null 
            ? GeoPoint(_currentLocation!.latitude, _currentLocation!.longitude)
            : GeoPoint(_navalCenter.latitude, _navalCenter.longitude),
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'waiting',
        'paymentMethod': _selectedPaymentMethod,
        'paymentStatus': _selectedPaymentMethod == 'gcash' ? 'pending' : 'cash',
      });

      // Subscribe passenger to pickup topic and enqueue driver notification for TODA
      try {
        await NotificationService().subscribeToPickupTopic(docRef.id);
        if (_selectedToda != null) {
          await NotificationService().enqueueDriverNotificationForToda(
            toda: _selectedToda!,
            pickupId: docRef.id,
            title: 'New Ride Request',
            body: 'Passenger requested a ride (${passengerCount} pax) - $_selectedToda',
            data: {
              'type': 'new_pickup',
              'pickupId': docRef.id,
              'toda': _selectedToda!,
            },
          );
        }
      } catch (_) {}

      setState(() {
        _selectedToda = null;
        _selectedPaymentMethod = null;
        _passengerCountController.clear();
        _destinationController.clear();
        _hasActiveRide = true;
        _activePickupId = docRef.id;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pickup request submitted!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting request: $e')),
        );
      }
    }
  }

  void _cancelRide() {
    final TextEditingController reasonController = TextEditingController();
    bool isSubmitting = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Cancel Ride'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Please tell us why you are cancelling:'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    maxLength: 200,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Type your reason (required)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setStateDialog(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Back'),
                ),
                TextButton(
                  onPressed: (reasonController.text.trim().isEmpty || isSubmitting)
                      ? null
                      : () async {
                          setStateDialog(() => isSubmitting = true);
                          final pickupId = _activePickupId;
                          final reason = reasonController.text.trim();
                          try {
                            if (pickupId != null) {
                              await FirebaseFirestore.instance
                                  .collection('pickups')
                                  .doc(pickupId)
                                  .update({
                                'status': 'cancelled',
                                'cancelReason': reason,
                                'cancelledAt': FieldValue.serverTimestamp(),
                                'cancelledBy': FirebaseAuth.instance.currentUser?.uid,
                              });
                            }
                          } catch (_) {
                            // ignore update errors
                          }
                          if (mounted) {
                            setState(() {
                              _hasActiveRide = false;
                              _activePickupId = null;
                            });
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Ride cancelled'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Build passenger profile content
  Widget _buildPassengerProfileContent() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE8F0FF), Colors.white],
        ),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            children: [
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox.shrink();
                  }

                  final userData = snapshot.data!.data() as Map<String, dynamic>?;
                  final name = (userData?['name'] ?? 'Passenger') as String;
                  final phone = (userData?['phone'] ?? 'Not provided') as String;
                  final email = (userData?['email'] ?? user.email) as String?;

                  return Column(
                    children: [
                      // Header card with avatar and role chip
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 32,
                                backgroundColor: const Color(0xFF082FBD).withOpacity(0.12),
                                child: const Icon(Icons.person_outline, color: Color(0xFF082FBD), size: 32),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name.isNotEmpty ? name : 'Passenger',
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 4),
                                    if (email != null && email.isNotEmpty)
                                      Text(
                                        email,
                                        style: TextStyle(color: Colors.black.withOpacity(0.6)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.person, size: 16, color: Colors.blue),
                                            SizedBox(width: 6),
                                            Text('Passenger', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600)),
                                          ],
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

                      const SizedBox(height: 16),

                      // Info card
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Personal Information',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 12),
                              _buildInfoItem(Icons.person_outline, 'Name', name),
                              const SizedBox(height: 8),
                              _buildInfoItem(Icons.email_outlined, 'Email', email ?? 'Not provided'),
                              const SizedBox(height: 12),
                              _buildInfoItem(Icons.phone_outlined, 'Phone', phone),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 24),

              // Logout button inside Profile
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showLogoutDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDriverPublicProfile({required String driverId, required String pickupId}) async {
    Map<String, dynamic>? d;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(driverId).get();
      if (snap.exists) {
        d = snap.data();
      }
    } catch (_) {}

    final driverName = (d?['name']?.toString() ?? 'Unknown');
    final email = (d?['email']?.toString() ?? '');
    final vehicle = (d?['vehicleInfo']?.toString() ?? '');
    final toda = (d?['toda']?.toString() ?? '');
    final double avgDriverRating = (d?['averageDriverRating'] is num)
        ? (d?['averageDriverRating'] as num).toDouble()
        : 0.0;
    final int driverRatingCount = (d?['driverRatingCount'] is num)
        ? (d?['driverRatingCount'] as num).toInt()
        : 0;

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
            minHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    const Icon(Icons.person, color: Color(0xFF082FBD), size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Driver Profile',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF082FBD),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (avgDriverRating > 0) ...[
                                  RatingDisplay(
                                    rating: avgDriverRating,
                                    ratingCount: driverRatingCount,
                                    size: 18,
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                _buildInfoItem(Icons.person_outline, 'Name', driverName),
                                if (email.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  _buildInfoItem(Icons.email_outlined, 'Email', email),
                                ],
                                if (vehicle.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  _buildInfoItem(Icons.directions_bike_outlined, 'Vehicle', vehicle),
                                ],
                                const SizedBox(height: 12),
                                Card(
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Recent Reviews',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 12),
                                        FutureBuilder<QuerySnapshot>(
                                          future: FirebaseFirestore.instance
                                              .collection('ratings')
                                              .where('ratedUserId', isEqualTo: driverId)
                                              .where('ratingType', isEqualTo: 'driver_rating')
                                              .orderBy('timestamp', descending: true)
                                              .limit(5)
                                              .get(),
                                          builder: (context, snap) {
                                            if (snap.connectionState == ConnectionState.waiting) {
                                              return const SizedBox.shrink();
                                            }
                                            if (!snap.hasData || snap.data!.docs.isEmpty) {
                                              return Text(
                                                'No reviews yet',
                                                style: TextStyle(color: Colors.grey.shade600),
                                              );
                                            }
                                            final items = snap.data!.docs.map((doc) {
                                              final data = doc.data() as Map<String, dynamic>;
                                              final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
                                              final comment = (data['comment'] as String?)?.trim() ?? '';
                                              final ts = data['timestamp'];
                                              String when = '';
                                              if (ts is Timestamp) {
                                                final dt = ts.toDate();
                                                when = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                                              }
                                              return Container(
                                                margin: const EdgeInsets.symmetric(vertical: 6),
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade50,
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(color: Colors.grey.shade200),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        RatingDisplay(rating: rating, ratingCount: 0, size: 16, showCount: false),
                                                        const Spacer(),
                                                        if (when.isNotEmpty)
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                            decoration: BoxDecoration(
                                                              color: Colors.grey.shade100,
                                                              borderRadius: BorderRadius.circular(10),
                                                              border: Border.all(color: Colors.grey.shade300),
                                                            ),
                                                            child: Text(
                                                              when,
                                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    if (comment.isNotEmpty)
                                                      Padding(
                                                        padding: const EdgeInsets.only(top: 8),
                                                        child: Text(
                                                          comment,
                                                          style: const TextStyle(fontSize: 14, height: 1.4),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              );
                                            }).toList();
                                            return Column(children: items);
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton(
                                            onPressed: () async {
                                              Navigator.of(context).pop();
                                              await Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => DriverReviewsScreen(
                                                    driverId: driverId,
                                                    driverName: driverName,
                                                  ),
                                                ),
                                              );
                                            },
                                            child: const Text('See all reviews'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (toda.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  _buildInfoItem(null, 'TODA', toda, customIcon: Image.asset(
                                    'assets/icons/TODA2.png',
                                    width: 20,
                                    height: 20,
                                    color: Colors.grey.shade600,
                                  )),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                pickupId: pickupId,
                                senderType: 'passenger',
                                title: 'Driver Chat',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF082FBD)),
                        label: const Text('Open Chat'),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF082FBD)),
                          foregroundColor: const Color(0xFF082FBD),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                    onPressed: () async {
                      await showRatingDialog(
                        context: context,
                        pickupId: pickupId,
                        ratingType: 'driver_rating',
                        ratedUserId: driverId,
                        ratedUserName: driverName,
                      );
                    },
                    icon: const Icon(Icons.star, color: Colors.white),
                    label: const Text('Rate Driver'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF082FBD),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build info item similar to driver's design
  Widget _buildInfoItem(IconData? icon, String label, String value, {Widget? customIcon}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        customIcon ?? Icon(
          icon,
          size: 20,
          color: Colors.grey.shade600,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Passenger history content reused by both sheet and full-screen
  Widget _buildPassengerHistoryContent() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: SizedBox.shrink());
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE8F0FF), Colors.white],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('pickups')
              .where('passengerId', isEqualTo: user.uid)
              .limit(50)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              final err = snapshot.error?.toString() ?? 'Unknown error';
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
                      const SizedBox(height: 8),
                      const Text('Error loading history'),
                      const SizedBox(height: 4),
                      Text(
                        err,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => setState(() {}),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF082FBD),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: SizedBox.shrink());
            }

            final rawDocs = snapshot.data?.docs ?? [];
            final docs = List<QueryDocumentSnapshot>.from(rawDocs);
            docs.sort((a, b) {
              final am = (a.data() as Map<String, dynamic>?) ?? const {};
              final bm = (b.data() as Map<String, dynamic>?) ?? const {};
              final at = am['timestamp'];
              final bt = bm['timestamp'];
              if (at is Timestamp && bt is Timestamp) {
                return bt.compareTo(at);
              } else if (at is Timestamp) {
                return -1;
              } else if (bt is Timestamp) {
                return 1;
              } else {
                return 0;
              }
            });
            if (docs.length > 50) {
              docs.removeRange(50, docs.length);
            }

            return RefreshIndicator(
              color: const Color(0xFF082FBD),
              onRefresh: () async {
                setState(() {});
                await Future.delayed(const Duration(milliseconds: 250));
              },
              child: docs.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                      children: [
                        const SizedBox(height: 160),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: const Color(0xFF082FBD).withOpacity(0.08),
                                child: const Icon(Icons.history, size: 36, color: Color(0xFF082FBD)),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No ride history yet',
                                style: TextStyle(fontSize: 18, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Your completed rides will appear here',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 160),
                      ],
                    )
                  : ListView.separated(
                      key: const PageStorageKey('passenger_history'),
                      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                      padding: const EdgeInsets.only(top: 12, bottom: 12),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final pickup = doc.data() as Map<String, dynamic>;
                        final timestamp = pickup['timestamp'] as Timestamp?;
                        final status = (pickup['status'] ?? 'unknown').toString();
                        final toda = (pickup['toda'] ?? 'Unknown').toString();
                        final count = (pickup['count'] ?? 0) as int;
                        final driverId = (pickup['driverId'] ?? '').toString();

                        final timestampText = timestamp != null ? _formatTimestamp(timestamp) : '—';

                        return KeyedSubtree(
                          key: ValueKey(doc.id),
                          child: Card(
                            elevation: 3,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                _showRideDetails(pickup, doc.id);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  leading: CircleAvatar(
                                    radius: 22,
                                    backgroundColor: _getStatusColor(status).withOpacity(0.12),
                                    child: Icon(
                                      _getStatusIcon(status),
                                      color: _getStatusColor(status),
                                      size: 22,
                                    ),
                                  ),
                                  title: Text(
                                    toda,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('$count passenger${count != 1 ? 's' : ''}'),
                                      if (driverId.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        FutureBuilder<DocumentSnapshot>(
                                          future: FirebaseFirestore.instance
                                              .collection('users')
                                              .doc(driverId)
                                              .get(),
                                          builder: (context, driverSnapshot) {
                                            String driverName = 'Unknown';
                                            String vehicleInfo = '';
                                            if (driverSnapshot.hasData && driverSnapshot.data!.exists) {
                                              final driverData = driverSnapshot.data!.data() as Map<String, dynamic>?;
                                              driverName = driverData?['name'] ?? 'Unknown';
                                              vehicleInfo = (driverData?['vehicleInfo'] ?? '').toString();
                                            }
                                            final details = vehicleInfo.isNotEmpty
                                                ? 'Driver: $driverName • $vehicleInfo'
                                                : 'Driver: $driverName';
                                            return Text(
                                              details,
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            );
                                          },
                                        ),
                                      ] else ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Driver: Not yet assigned',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                      Text(
                                        timestampText,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(status).withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: _getStatusColor(status), width: 1),
                                    ),
                                    child: Text(
                                      status.toUpperCase(),
                                      style: TextStyle(
                                        color: _getStatusColor(status),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            );
          },
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    final s = status.toLowerCase();
    switch (s) {
      case 'waiting':
      case 'pending':
        return Colors.orange;
      case 'on_the_way':
      case 'ontheway':
      case 'onway':
      case 'onTheWay': // defensive, in case raw values leak through
      case 'accepted':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'cancelled':
      case 'canceled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    final s = status.toLowerCase();
    switch (s) {
      case 'waiting':
      case 'pending':
        return Icons.schedule;
      case 'on_the_way':
      case 'ontheway':
      case 'onway':
      case 'onTheWay':
      case 'accepted':
        return Icons.directions_bike; // indicates in transit
      case 'completed':
        return Icons.done_all;
      case 'cancelled':
      case 'canceled':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  String _formatTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final date = timestamp.toDate();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  Widget _buildAuthForm() {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'TODA GO',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF082FBD),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isRegistering ? 'Create Passenger Account' : 'Passenger Login',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 32),
                      if (_isRegistering) ...[
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone Number',
                            prefixIcon: Icon(Icons.phone_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.email),
                          border: const OutlineInputBorder(),
                          enabledBorder: _emailError
                              ? OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.red.shade300),
                                  borderRadius: BorderRadius.circular(12),
                                )
                              : null,
                          focusedBorder: _emailError
                              ? OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.red.shade400, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                )
                              : null,
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: _passwordObscured,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _passwordObscured ? 'Show password' : 'Hide password',
                            icon: Icon(_passwordObscured ? Icons.visibility_off : Icons.visibility),
                            onPressed: () {
                              setState(() {
                                _passwordObscured = !_passwordObscured;
                              });
                            },
                          ),
                          enabledBorder: _passwordError
                              ? OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.red.shade300),
                                  borderRadius: BorderRadius.circular(12),
                                )
                              : null,
                          focusedBorder: _passwordError
                              ? OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.red.shade400, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                )
                              : null,
                        ),
                      ),
                      if (!_isRegistering)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _forgotPassword,
                            child: const Text('Forgot password?'),
                          ),
                        ),
                      if (_errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(
                            _errorMessage,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _handleAuth,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF082FBD),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            _isRegistering ? 'Create Account' : 'Sign In',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _isRegistering
                                ? 'Already have an account? '
                                : "Don't have an account? ",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _isRegistering = !_isRegistering;
                                _errorMessage = '';
                              });
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              _isRegistering ? 'Sign In' : 'Create Account',
                              style: const TextStyle(
                                color: Color(0xFF082FBD),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleAuth() async {
    if (_isRegistering) {
      await _register();
    } else {
      await _login();
    }
  }

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in all fields';
      });
      return;
    }

    setState(() {
      _errorMessage = '';
    });

    try {
      final error = await _passengerAuthService.registerPassenger(
        name: name,
        email: email,
        password: password,
      );
      
      if (error != null) {
        setState(() {
          _errorMessage = error;
        });
        return;
      }
      
      // Registration successful, add phone number if provided
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && phone.isNotEmpty) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            {'phone': phone},
            SetOptions(merge: true),
          );
        }
      } catch (_) {}
      
      if (mounted) {
        setState(() {
          _isRegistering = false;
          _currentTabIndex = 0;
        });
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PassengerScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (_errorMessage.isNotEmpty || _emailError || _passwordError) {
      setState(() {
        _errorMessage = '';
        _emailError = false;
        _passwordError = false;
      });
    }

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in all fields';
      });
      return;
    }

    final emailRegex = RegExp(r'^\S+@\S+\.\S+$');
    if (!emailRegex.hasMatch(email)) {
      setState(() {
        _emailError = true;
        _errorMessage = 'Incorrect Email';
      });
      return;
    }

    setState(() {
      _errorMessage = '';
    });

    try {
      final error = await _passengerAuthService.signIn(
        email: email,
        password: password,
      );
      
      if (error != null) {
        final lower = error.toLowerCase();
        if (lower.contains('wrong-password')) {
          setState(() {
            _passwordError = true;
            _errorMessage = 'Incorrect Password';
          });
        } else if (lower.contains('invalid-email') || lower.contains('user-not-found')) {
          setState(() {
            _emailError = true;
            _errorMessage = 'Incorrect Email';
          });
        } else {
          setState(() {
            _errorMessage = error;
          });
        }
        return;
      }
      
      // Login successful - clear form and navigate
      if (mounted) {
        setState(() {
          _isRegistering = false;
          _currentTabIndex = 0;
        });
        _clearForm();
        // Navigate to passenger dashboard
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const PassengerScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('wrong-password')) {
        setState(() {
          _passwordError = true;
          _errorMessage = 'Incorrect Password';
        });
      } else if (msg.contains('invalid-email') || msg.contains('user-not-found')) {
        setState(() {
          _emailError = true;
          _errorMessage = 'Incorrect Email';
        });
      } else {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _forgotPassword() async {
    String email = _emailController.text.trim();
    final emailRegex = RegExp(r'^\S+@\S+\.\S+$');

    if (!emailRegex.hasMatch(email)) {
      final controller = TextEditingController(text: email);
      final entered = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Reset password'),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(controller.text.trim()),
                child: const Text('Send'),
              ),
            ],
          );
        },
      );
      if (entered == null || entered.isEmpty) return;
      email = entered;
      if (!emailRegex.hasMatch(email)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter a valid email.')),
          );
        }
        return;
      }
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reset link sent. Check your email.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Failed to send reset email';
      final code = e.code.toLowerCase();
      if (code == 'user-not-found') message = 'No account found for that email.';
      if (code == 'invalid-email') message = 'Please enter a valid email.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong. Please try again.')),
        );
      }
    }
  }

  void _clearForm() {
    _nameController.clear();
    _emailController.clear();
    _passwordController.clear();
    _phoneController.clear();
    _passengerCountController.clear();
    _destinationController.clear();
    _selectedToda = null; // Reset selection
  }
}
