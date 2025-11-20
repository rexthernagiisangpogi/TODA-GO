import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../services/passenger_auth_service.dart';
import 'settings_screen.dart';
import 'passenger_ratings_screen.dart';
import '../widgets/chat_screen.dart';
import '../widgets/tutorial_helper.dart';
import '../services/notification_service.dart';
import '../services/rating_service.dart';
import '../services/image_upload_service.dart';
import '../services/unread_message_service.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'dart:convert';

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
  // Registration field errors
  bool _nameError = false;
  bool _phoneError = false;

  // Floating sheet state
  bool _showRideAcceptedSheet = false;
  bool _showRatingInSheet = false; // Show rating dialog in the floating sheet
  String? _driverName;
  String? _driverIdForRating;
  String? _completedPickupId; // Store pickupId for rating
  StreamSubscription<DocumentSnapshot>? _activePickupSubscription;
  Set<String> _ratedPickupIds = {}; // Track which pickups have been rated to avoid duplicate dialogs

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
    // Listen for active pickup changes
    _listenToActivePickup();
  }

  void _listenToActivePickup() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Listen for any active pickups for this passenger that are on the way
    FirebaseFirestore.instance
        .collection('pickups')
        .where('passengerId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'onTheWay')
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final pickupDoc = snapshot.docs.first;
        final pickupData = pickupDoc.data();
        final driverId = pickupData['driverId'] as String?;
        final status = pickupData['status'] as String?;
        
        if (driverId != null && status == 'onTheWay') {
          setState(() {
            _activePickupId = pickupDoc.id;
            _hasActiveRide = true;
            _showRideAcceptedSheet = true;
            _showRatingInSheet = false; // Don't show rating when ride is accepted
            _driverIdForRating = driverId;
          });
          
          // Start listening to this specific pickup for status changes
          _listenToSpecificPickup(pickupDoc.id);
          
          // Fetch driver name
          FirebaseFirestore.instance
              .collection('users')
              .doc(driverId)
              .get()
              .then((driverDoc) {
            if (mounted && driverDoc.exists) {
              final driverData = driverDoc.data();
              setState(() {
                _driverName = driverData?['name'] ?? 'Driver';
              });
            }
          });
        }
      } else {
        // No active onTheWay pickup, reset active ride flags and hide sheet only if not showing rating
        if (_hasActiveRide || (_showRideAcceptedSheet && !_showRatingInSheet)) {
          setState(() {
            if (_hasActiveRide) {
              _hasActiveRide = false;
              _activePickupId = null;
            }
            if (!_showRatingInSheet) {
              _showRideAcceptedSheet = false;
              _driverName = null;
              _driverIdForRating = null;
            }
          });
        }
      }
    });
    
    // Also listen for completed rides to show rating immediately
    FirebaseFirestore.instance
        .collection('pickups')
        .where('passengerId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'completed')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.docs.isNotEmpty) {
        final pickupDoc = snapshot.docs.first;
        final pickupId = pickupDoc.id;
        final pickupData = pickupDoc.data();
        final driverId = pickupData['driverId'] as String?;
        
        // Check if we haven't already shown rating for this pickup AND user hasn't rated it yet
        if (!_ratedPickupIds.contains(pickupId) && driverId != null && driverId.isNotEmpty) {
          // Check if user has already rated this pickup
          final hasRated = await RatingService().hasUserRated(pickupId, 'driver_rating');
          if (hasRated) {
            print('Completed ride listener: User has already rated pickup $pickupId, skipping');
            _ratedPickupIds.add(pickupId);
            return;
          }
          
          print('Completed ride listener: Found completed ride $pickupId');
          _ratedPickupIds.add(pickupId);
          
          // Fetch driver name if not already set
          if (_driverName == null) {
            FirebaseFirestore.instance
                .collection('users')
                .doc(driverId)
                .get()
                .then((driverDoc) {
              if (mounted && driverDoc.exists) {
                final driverData = driverDoc.data();
                setState(() {
                  _driverName = driverData?['name'] ?? 'Driver';
                  _showRideAcceptedSheet = true;
                  _showRatingInSheet = true;
                  _hasActiveRide = false;
                  _driverIdForRating = driverId;
                  _completedPickupId = pickupId;
                  _activePickupId = pickupId; // Keep pickup ID for sheet display
                });
                print('Completed ride listener: Showing rating sheet');
              }
            });
          } else {
            setState(() {
              _showRideAcceptedSheet = true;
              _showRatingInSheet = true;
              _hasActiveRide = false;
              _driverIdForRating = driverId;
              _completedPickupId = pickupId;
              _activePickupId = pickupId; // Keep pickup ID for sheet display
            });
            print('Completed ride listener: Showing rating sheet');
          }
        }
      }
    });
  }

  void _listenToSpecificPickup(String pickupId) {
    // Cancel previous subscription if any
    _activePickupSubscription?.cancel();
    
    // Listen to the specific pickup document for status changes
    _activePickupSubscription = FirebaseFirestore.instance
        .collection('pickups')
        .doc(pickupId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists) return;
      
      final currentPickupId = snapshot.id; // Use snapshot.id, not function parameter
      final pickupData = snapshot.data();
      final status = pickupData?['status'] as String?;
      final driverId = pickupData?['driverId'] as String?;
      
      // Show sheet when driver accepts and status is onTheWay
      if (driverId != null && status == 'onTheWay') {
        setState(() {
          _showRideAcceptedSheet = true;
          _showRatingInSheet = false; // Don't show rating when ride is accepted
          _hasActiveRide = true;
          _driverIdForRating = driverId;
          _activePickupId = currentPickupId;
        });
        
        // Fetch driver name
        FirebaseFirestore.instance
            .collection('users')
            .doc(driverId)
            .get()
            .then((driverDoc) {
          if (mounted && driverDoc.exists) {
            final driverData = driverDoc.data();
            setState(() {
              _driverName = driverData?['name'] ?? 'Driver';
            });
          }
        });
      } else if (status != null && status.toString().toLowerCase() == 'completed') {
        print('Listener: Ride completed detected! pickupId: $currentPickupId, driverId: $driverId');
        
        // Transform sheet to show rating instead of hiding it
        final driverIdToRate = driverId ?? _driverIdForRating;
        
        print('Listener: driverIdToRate: $driverIdToRate, currentPickupId: $currentPickupId');
        
        // Prevent showing rating multiple times for the same pickup
        if (_ratedPickupIds.contains(currentPickupId)) {
          print('Listener: Already processed this pickup, skipping');
          return;
        }
        
        // Check if user has already rated this pickup
        final hasRated = await RatingService().hasUserRated(currentPickupId, 'driver_rating');
        if (hasRated) {
          print('Listener: User has already rated pickup $currentPickupId, skipping');
          _ratedPickupIds.add(currentPickupId);
          return;
        }
        
        // Ensure we have all required data
        if (!mounted || driverIdToRate == null || driverIdToRate.isEmpty || currentPickupId.isEmpty) {
          print('Listener: Missing required data - mounted: $mounted, driverIdToRate: $driverIdToRate, currentPickupId: $currentPickupId');
          return;
        }
        
        // Mark as being processed immediately to prevent duplicate dialogs
        _ratedPickupIds.add(currentPickupId);
        
        // Transform the floating sheet to show rating
        setState(() {
          _showRideAcceptedSheet = true; // Keep sheet visible
          _showRatingInSheet = true; // Show rating content
          _hasActiveRide = false;
          _driverIdForRating = driverIdToRate;
          _completedPickupId = currentPickupId;
          _activePickupId = currentPickupId; // Keep pickup ID for sheet display
        });
        
        print('Listener: Transformed sheet to show rating');
      } else if (status == 'cancelled' || status == 'canceled') {
        // Hide sheet when ride is cancelled
        setState(() {
          _showRideAcceptedSheet = false;
          _hasActiveRide = false;
          _driverName = null;
          _driverIdForRating = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _passengerCountController.dispose();
    _destinationController.dispose();
    _activePickupSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return TutorialHelper.wrapWithOnboarding(
      userType: 'passenger',
      child: user == null ? _buildAuthForm() : _buildMainContent(),
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
                                            _buildInfoItem(null, 'Vehicle', vehicle, customIcon: Image.asset(
                                              'assets/icons/TODA2.png',
                                              width: 20,
                                              height: 20,
                                              fit: BoxFit.contain,
                                              color: Colors.grey.shade600,
                                            )),
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

  /// Build floating sheet that shows when ride is accepted
  Widget _buildRideAcceptedSheet() {
    // If ride is completed, show rating content in the sheet
    if (_showRatingInSheet && _completedPickupId != null && _driverIdForRating != null) {
      return _buildRatingSheet();
    }
    
    // Otherwise show the normal ride accepted sheet
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header with icon and title
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Ride Accepted!',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF082FBD),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Driver is on the way',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Driver information - tappable
                if (_driverIdForRating != null)
                  FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('users').doc(_driverIdForRating).get(),
                    builder: (context, snapshot) {
                      String driverName = _driverName ?? 'Driver';
                      String? profileImageUrl;
                      if (snapshot.hasData && snapshot.data!.exists) {
                        final driverData = snapshot.data!.data() as Map<String, dynamic>?;
                        driverName = driverData?['name'] ?? driverName;
                        profileImageUrl = driverData?['profileImageUrl'] as String?;
                      }
                      
                      return InkWell(
                        onTap: () => _showDriverProfile(_driverIdForRating!),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF082FBD).withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF082FBD).withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: const Color(0xFF082FBD).withOpacity(0.1),
                                backgroundImage: profileImageUrl != null
                                    ? (profileImageUrl.startsWith('data:image/')
                                        ? MemoryImage(base64Decode(profileImageUrl.split(',')[1]))
                                        : NetworkImage(profileImageUrl) as ImageProvider)
                                    : null,
                                child: profileImageUrl == null
                                    ? Image.asset(
                                        'assets/icons/TODA2.png',
                                        width: 24,
                                        height: 24,
                                        fit: BoxFit.contain,
                                        color: const Color(0xFF082FBD),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Your Driver',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      driverName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Color(0xFF082FBD),
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 16),
                // Chat button
                SizedBox(
                  width: double.infinity,
                  child: StreamBuilder<int>(
                    stream: _activePickupId != null ? UnreadMessageService().getUnreadCount(_activePickupId!) : Stream.value(0),
                    builder: (context, snapshot) {
                      final unreadCount = snapshot.data ?? 0;
                      return ElevatedButton.icon(
                        onPressed: _activePickupId != null
                            ? () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      pickupId: _activePickupId!,
                                      title: 'Chat with Driver',
                                      senderType: 'passenger',
                                    ),
                                  ),
                                );
                              }
                            : null,
                        icon: unreadCount > 0
                            ? Badge(
                                label: Text('$unreadCount'),
                                child: const Icon(Icons.chat_bubble_outline),
                              )
                            : const Icon(Icons.chat_bubble_outline),
                        label: const Text(
                          'Open Chat',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF082FBD),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build rating sheet that replaces the ride accepted sheet when ride is completed
  Widget _buildRatingSheet() {
    return _RatingSheetWidget(
      pickupId: _completedPickupId!,
      driverId: _driverIdForRating!,
      driverName: _driverName ?? 'Driver',
      onRatingSubmitted: () {
        // Hide sheet after rating is submitted
        setState(() {
          _showRideAcceptedSheet = false;
          _showRatingInSheet = false;
          _driverName = null;
          _driverIdForRating = null;
          _completedPickupId = null;
          _activePickupId = null;
          _hasActiveRide = false;
        });
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

  void _showDriverProfile(String driverId) async {
    final driverDoc = await FirebaseFirestore.instance.collection('users').doc(driverId).get();
    if (!driverDoc.exists || !mounted) return;
    
    final driverData = driverDoc.data() as Map<String, dynamic>;
    final name = driverData['name'] ?? 'Driver';
    final email = driverData['email'] ?? '';
    final phone = driverData['phone'] ?? '';
    final licenseNumber = driverData['licenseNumber'] ?? '';
    final vehicleInfo = driverData['vehicleInfo'] ?? '';
    final toda = driverData['toda'] ?? '';
    final profileImageUrl = driverData['profileImageUrl'] as String?;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
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
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: const Color(0xFF082FBD).withOpacity(0.1),
                    backgroundImage: profileImageUrl != null
                        ? (profileImageUrl.startsWith('data:image/')
                            ? MemoryImage(base64Decode(profileImageUrl.split(',')[1]))
                            : NetworkImage(profileImageUrl) as ImageProvider)
                        : null,
                    child: profileImageUrl == null
                        ? const Icon(Icons.person, color: Color(0xFF082FBD), size: 50)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    name,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/icons/TODA2.png',
                          width: 16,
                          height: 16,
                          fit: BoxFit.contain,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 6),
                        const Text('Driver', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('ratings')
                        .where('ratedUserId', isEqualTo: driverId)
                        .where('ratingType', isEqualTo: 'driver_rating')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF082FBD).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF082FBD).withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 24),
                              const SizedBox(width: 8),
                              const Text(
                                'N/A',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF082FBD),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '(No ratings yet)',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF082FBD).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF082FBD).withOpacity(0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Loading ratings...',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      
                      double avg = 0.0;
                      int count = 0;
                      
                      if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                        final docs = snapshot.data!.docs;
                        double sum = 0;
                        for (final doc in docs) {
                          final data = doc.data() as Map<String, dynamic>;
                          sum += (data['rating'] as num?)?.toDouble() ?? 0.0;
                        }
                        count = docs.length;
                        avg = count == 0 ? 0.0 : sum / count;
                      }
                      
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF082FBD).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF082FBD).withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              count > 0 ? avg.toStringAsFixed(1) : 'N/A',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF082FBD),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              count > 0 ? '($count ${count == 1 ? 'rating' : 'ratings'})' : '(No ratings yet)',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    if (email.isNotEmpty) _buildProfileItem(Icons.email_outlined, 'Email', email),
                    if (phone.isNotEmpty) ...[const SizedBox(height: 12), _buildProfileItem(Icons.phone_outlined, 'Phone', phone)],
                    if (licenseNumber.isNotEmpty) ...[const SizedBox(height: 12), _buildProfileItem(Icons.badge_outlined, 'License', licenseNumber)],
                    if (vehicleInfo.isNotEmpty) ...[const SizedBox(height: 12), _buildProfileItem(null, 'Vehicle', vehicleInfo, customIcon: Image.asset(
                      'assets/icons/TODA2.png',
                      width: 20,
                      height: 20,
                      fit: BoxFit.contain,
                      color: Colors.grey.shade600,
                    ))],
                    if (toda.isNotEmpty) ...[const SizedBox(height: 12), _buildProfileItem(Icons.apartment_outlined, 'TODA', toda)],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileItem(IconData? icon, String label, String value, {Widget? customIcon}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        customIcon ?? Icon(icon, color: Colors.grey.shade600, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
          _currentTabIndex == 4
              ? 'Passenger Profile'
              : _currentTabIndex == 3
                  ? 'My Ratings'
                  : _currentTabIndex == 2
                      ? 'Ride History'
                      : 'Passenger Dashboard',
        ),
        backgroundColor: const Color(0xFF082FBD),
        foregroundColor: Colors.white,
        actions: [
          TutorialHelper.createHelpButton(context, 'passenger'),
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
      body: _currentTabIndex == 4
          ? _buildPassengerProfileContent()
          : _currentTabIndex == 3
              ? PassengerRatingsScreen(
                  passengerId: FirebaseAuth.instance.currentUser?.uid ?? '',
                )
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
          // Floating sheet for ride accepted notification
          if (_showRideAcceptedSheet)
            _buildRideAcceptedSheet(),
          // Cancel and Complete buttons (shown when ride is active)
          if (_hasActiveRide && !_showRideAcceptedSheet)
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
            icon: Icon(Icons.star_outline),
            label: 'Ratings',
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
                              // Current Location Input
                              TextField(
                                controller: _destinationController,
                                textInputAction: TextInputAction.next,
                                onChanged: (_) => setSheetState(() {}),
                                decoration: InputDecoration(
                                  hintText: 'Enter current location',
                                  hintStyle: TextStyle(color: Colors.grey.shade500),
                                  prefixIcon: const Icon(
                                    Icons.place,
                                    color: Color(0xFF082FBD),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
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
                                    vertical: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Passenger count
                              Builder(
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
        _passengerCountController.clear();
        _destinationController.clear();
        _hasActiveRide = true;
        _activePickupId = docRef.id;
      });
      
      // Start listening to this specific pickup for status changes
      _listenToSpecificPickup(docRef.id);

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
                              
                              // Notify drivers that this ride was cancelled
                              try {
                                final NotificationService notificationService = NotificationService();
                                await notificationService.enqueueDriverNotificationForToda(
                                  toda: _selectedToda ?? '',
                                  pickupId: pickupId,
                                  title: 'Ride Cancelled',
                                  body: 'A passenger has cancelled their ride request',
                                  data: {
                                    'type': 'ride_cancelled',
                                    'pickupId': pickupId,
                                  },
                                );
                              } catch (_) {
                                // Ignore notification errors
                              }
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
                  final profileImageUrl = userData?['profileImageUrl'] as String?;

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
                              Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 32,
                                    backgroundColor: const Color(0xFF082FBD).withOpacity(0.12),
                                    backgroundImage: profileImageUrl != null
                                        ? (profileImageUrl.startsWith('data:image/')
                                            ? MemoryImage(base64Decode(profileImageUrl.split(',')[1]))
                                            : NetworkImage(profileImageUrl) as ImageProvider)
                                        : null,
                                    child: profileImageUrl == null ? const Icon(Icons.person_outline, color: Color(0xFF082FBD), size: 32) : null,
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: () async {
                                        try {
                                          final imageService = ImageUploadService();
                                          final result = await imageService.pickAndUploadProfileImage();
                                          if (result != null && mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Profile picture updated!'), backgroundColor: Colors.green),
                                            );
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Failed to upload: $e'), backgroundColor: Colors.red),
                                            );
                                          }
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF082FBD),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 2),
                                        ),
                                        child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
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

            return docs.isEmpty
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
                        final cancelReason = (pickup['cancelReason'] ?? '').toString().trim();

                        return KeyedSubtree(
                          key: ValueKey(doc.id),
                          child: Card(
                            elevation: 3,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                _showRideDetails(pickup, doc.id);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(status),
                                            borderRadius: BorderRadius.circular(24),
                                            boxShadow: [
                                              BoxShadow(
                                                color: _getStatusColor(status).withOpacity(0.15),
                                                blurRadius: 8,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Center(
                                            child: Text(
                                              count.toString(),
                                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                toda,
                                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: _getStatusColor(status).withOpacity(0.08),
                                                      borderRadius: BorderRadius.circular(12),
                                                      border: Border.all(color: _getStatusColor(status), width: 1),
                                                    ),
                                                    child: Text(
                                                      status.toUpperCase(),
                                                      style: TextStyle(color: _getStatusColor(status), fontSize: 12, fontWeight: FontWeight.w600),
                                                    ),
                                                  ),
                                                  if (driverId.isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    FutureBuilder<DocumentSnapshot>(
                                                      future: FirebaseFirestore.instance.collection('users').doc(driverId).get(),
                                                      builder: (context, driverSnapshot) {
                                                        String driverName = 'Unknown';
                                                        if (driverSnapshot.hasData && driverSnapshot.data!.exists) {
                                                          final driverData = driverSnapshot.data!.data() as Map<String, dynamic>?;
                                                          driverName = driverData?['name'] ?? 'Unknown';
                                                        }
                                                        return Text(
                                                          'Driver: $driverName',
                                                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        );
                                                      },
                                                    ),
                                                  ],
                                                  if (status.toString().toLowerCase().startsWith('cancel') && cancelReason.isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text('Reason: $cancelReason', style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (timestamp != null) ...[
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                                          const SizedBox(width: 4),
                                          Text(_formatTimestamp(timestamp), style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                        ],
                                      ),
                                    ],
                                    // Chat button for completed rides
                                    if (status.toString().toLowerCase() == 'completed' && driverId.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => ChatScreen(
                                                  pickupId: doc.id,
                                                  title: 'Chat History',
                                                  senderType: 'passenger',
                                                ),
                                              ),
                                            );
                                          },
                                          icon: const Icon(Icons.chat_bubble_outline, size: 18),
                                          label: const Text('View Chat History'),
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: Color(0xFF082FBD)),
                                            foregroundColor: const Color(0xFF082FBD),
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
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
                          onChanged: (_) {
                            if (_nameError) {
                              setState(() {
                                _nameError = false;
                              });
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: const Icon(Icons.person),
                            border: const OutlineInputBorder(),
                            enabledBorder: _nameError
                                ? OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.red.shade300),
                                    borderRadius: BorderRadius.circular(12),
                                  )
                                : null,
                            focusedBorder: _nameError
                                ? OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.red.shade400, width: 2),
                                    borderRadius: BorderRadius.circular(12),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          onChanged: (_) {
                            if (_phoneError) {
                              setState(() {
                                _phoneError = false;
                              });
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'Phone Number',
                            prefixIcon: const Icon(Icons.phone_outlined),
                            border: const OutlineInputBorder(),
                            enabledBorder: _phoneError
                                ? OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.red.shade300),
                                    borderRadius: BorderRadius.circular(12),
                                  )
                                : null,
                            focusedBorder: _phoneError
                                ? OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.red.shade400, width: 2),
                                    borderRadius: BorderRadius.circular(12),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: _emailController,
                        onChanged: (_) {
                          if (_emailError) {
                            setState(() {
                              _emailError = false;
                              _errorMessage = '';
                            });
                          }
                        },
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
                        onChanged: (_) {
                          if (_passwordError) {
                            setState(() {
                              _passwordError = false;
                              _errorMessage = '';
                            });
                          }
                        },
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

    // Clear previous errors
    setState(() {
      _nameError = false;
      _phoneError = false;
      _emailError = false;
      _passwordError = false;
      _errorMessage = '';
    });

    // Validation - set error flags for empty/invalid fields
    bool hasError = false;
    if (name.isEmpty || name.length < 2) {
      setState(() {
        _nameError = true;
      });
      hasError = true;
    }
    if (phone.isEmpty) {
      setState(() {
        _phoneError = true;
      });
      hasError = true;
    }
    if (email.isEmpty) {
      setState(() {
        _emailError = true;
      });
      hasError = true;
    } else {
      final emailRegex = RegExp(r'^\S+@\S+\.\S+$');
      if (!emailRegex.hasMatch(email)) {
        setState(() {
          _emailError = true;
        });
        hasError = true;
      }
    }
    if (password.isEmpty || password.length < 6) {
      setState(() {
        _passwordError = true;
      });
      hasError = true;
    }
    if (hasError) {
      setState(() {
        _errorMessage = 'Please fill in all required fields correctly';
      });
      return;
    }

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
      
      // Registration successful, navigate to dashboard
      if (mounted) {
        setState(() {
          _isRegistering = false;
          _currentTabIndex = 0;
        });
        _showMessage("Registration successful! Welcome to TODA GO.");
        _clearForm();
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

    // Clear previous errors
    setState(() {
      _errorMessage = '';
      _emailError = false;
      _passwordError = false;
    });

    // Validation - set error flags for empty/invalid fields
    bool hasError = false;
    if (email.isEmpty) {
      setState(() {
        _emailError = true;
        _errorMessage = 'Please enter your email address';
      });
      hasError = true;
    } else {
      final emailRegex = RegExp(r'^\S+@\S+\.\S+$');
      if (!emailRegex.hasMatch(email)) {
        setState(() {
          _emailError = true;
          _errorMessage = 'Incorrect Email';
        });
        hasError = true;
      }
    }
    if (password.isEmpty) {
      setState(() {
        _passwordError = true;
        if (!hasError) {
          _errorMessage = 'Please enter your password';
        }
      });
      return;
    }
    if (hasError) return;

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
        final passwordError =
            lower.contains('wrong-password') || lower.contains('wrong password') || lower.contains('incorrect password');
        if (passwordError) {
          setState(() {
            _passwordError = true;
            _errorMessage = 'Incorrect Password';
          });
        } else if (lower.contains('invalid-email') || lower.contains('user-not-found') || lower.contains('incorrect email')) {
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
      final passwordError =
          msg.contains('wrong-password') || msg.contains('wrong password') || msg.contains('incorrect password');
      if (passwordError) {
        setState(() {
          _passwordError = true;
          _errorMessage = 'Incorrect Password';
        });
      } else if (msg.contains('invalid-email') || msg.contains('user-not-found') || msg.contains('incorrect email')) {
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

/// Inline rating widget for the floating sheet
class _RatingSheetWidget extends StatefulWidget {
  final String pickupId;
  final String driverId;
  final String driverName;
  final VoidCallback onRatingSubmitted;

  const _RatingSheetWidget({
    required this.pickupId,
    required this.driverId,
    required this.driverName,
    required this.onRatingSubmitted,
  });

  @override
  State<_RatingSheetWidget> createState() => _RatingSheetWidgetState();
}

class _RatingSheetWidgetState extends State<_RatingSheetWidget> {
  final RatingService _ratingService = RatingService();
  final TextEditingController _commentController = TextEditingController();
  double _rating = 5.0;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final error = await _ratingService.submitRating(
        pickupId: widget.pickupId,
        rating: _rating,
        ratingType: 'driver_rating',
        comment: _commentController.text.trim().isEmpty 
            ? null 
            : _commentController.text.trim(),
        ratedUserId: widget.driverId,
      );

      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
        setState(() {
          _isSubmitting = false;
        });
      } else if (mounted) {
        widget.onRatingSubmitted();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit rating: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFF082FBD).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.star,
                        color: Color(0xFF082FBD),
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Rate Your Driver',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF082FBD),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'How was your ride with ${widget.driverName}?',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Star rating
                Center(
                  child: RatingBar.builder(
                    initialRating: _rating,
                    minRating: 1,
                    direction: Axis.horizontal,
                    allowHalfRating: false,
                    itemCount: 5,
                    itemSize: 50,
                    itemPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                    itemBuilder: (context, _) => const Icon(
                      Icons.star,
                      color: Colors.amber,
                    ),
                    onRatingUpdate: (rating) {
                      setState(() {
                        _rating = rating;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // Rating label
                Center(
                  child: Text(
                    _getRatingLabel(_rating),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _getRatingColor(_rating),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Comment field
                TextField(
                  controller: _commentController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Optional: Share your experience...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
                const SizedBox(height: 24),
                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitRating,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF082FBD),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Submit Rating',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getRatingLabel(double rating) {
    switch (rating.round()) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent';
      default:
        return '';
    }
  }

  Color _getRatingColor(double rating) {
    switch (rating.round()) {
      case 1:
      case 2:
        return Colors.red;
      case 3:
        return Colors.orange;
      case 4:
      case 5:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
