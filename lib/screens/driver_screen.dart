import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../services/driver_auth_service.dart';
import '../services/vibration_service.dart';
import '../widgets/rating_dialog.dart';
import '../widgets/auth_wrapper.dart';
import 'settings_screen.dart';
import '../widgets/chat_screen.dart';
import '../services/notification_service.dart';
import '../l10n/app_localizations.dart';

enum MapMode { normal, satellite, hybrid }

class DriverScreen extends StatefulWidget {
  static const String routeName = '/driver';

  const DriverScreen({super.key});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  static const String _mapTilerKey = 'dLSnXdAyPtOhZ6BaILyI';
  final DriverAuthService _driverAuthService = DriverAuthService();
  final VibrationService _vibrationService = VibrationService();
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _licenseController = TextEditingController();
  final TextEditingController _vehicleController = TextEditingController();
  
  // OCR & Image capture state
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _licenseImage;
  bool _isOcrProcessing = false;
  String? _ocrError;
  String? _uploadedLicenseImageUrl;
  
  // Login error message shown inline for login only
  String _loginError = '';
  bool _emailError = false;
  bool _passwordError = false;
  
  // Shared TODA options
  final List<String> _todaOptions = const [
    'NATODA',
    'CARNATODA',
    'ALTODA',
    'LAPNATODA',
    'Culaba',
    'Cabucgayan',
    'Maripipi',
    'Biliran',
  ];

  // TODA type selection (nullable; require explicit selection)
  String? _selectedToda;
  
  // Settings
  bool _vibrationEnabled = true;
  StreamSubscription<DocumentSnapshot>? _settingsSub;
  StreamSubscription<DocumentSnapshot>? _driverTodaSub;
  StreamSubscription<User?>? _authSub;

  // Bottom navigation: 0 = Map, 1 = History, 2 = Profile
  int _currentTabIndex = 0;

  bool _isRegistering = false;
  bool _showNewPassengerNotification = false;
  String? _lastKnownPickupId;
  String? _driverToda;
  bool _passwordObscured = true;
  
  // Philippine driver's license regex: e.g., N12-34-567890 (letter + 2-2-6 digits)
  final RegExp _phLicenseRegex = RegExp(r'[A-Z]\d{2}-\d{2}-\d{6}');

  // Naval, Biliran coordinates (aligned with PassengerScreen)
  static const LatLng _navalCenter = LatLng(11.56179, 124.420000);
  static final LatLngBounds _navalBounds = LatLngBounds(
    const LatLng(11.48, 124.35), // Southwest corner (slightly more west)
    const LatLng(11.66, 124.50), // Northeast corner (expanded further east only)
  );

  @override
  void initState() {
    super.initState();
    _listenToPickupUpdates();
    _listenToUserSettings();
    _listenToDriverToda();
    // Initialize FCM for driver
    NotificationService().initialize(context: context);
    // Force dashboard when authenticated
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      if (user != null) {
        setState(() {
          _isRegistering = false;
          _currentTabIndex = 0;
        });
      }
    });
  }

  Future<void> _markArrived(String pickupId) async {
    final user = _driverAuthService.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('pickups').doc(pickupId).update({
      'status': 'arrived',
      'driverId': user.uid,
    });

    _showMessage("Marked as Arrived!");

    // Notify passenger that driver has arrived
    try {
      await NotificationService().enqueuePassengerNotificationForPickup(
        pickupId: pickupId,
        title: 'Driver has arrived',
        body: 'Your driver has arrived at your location.',
        data: {
          'type': 'arrived',
          'pickupId': pickupId,
        },
      );
    } catch (_) {}
  }

  /// Build list of ratings given by passengers to this driver
  Widget _buildDriverRatingsContent() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('ratings')
                  .where('ratedUserId', isEqualTo: user.uid)
                  .where('ratingType', isEqualTo: 'driver_rating')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: SizedBox.shrink());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_border, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          'No ratings yet',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: snapshot.data!.docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
                    final comment = (data['comment'] as String?)?.trim() ?? '';
                    final pickupId = (data['pickupId'] ?? '').toString();
                    final ts = data['timestamp'];
                    String when = '';
                    if (ts is Timestamp) {
                      final dt = ts.toDate();
                      when = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                    }

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF082FBD).withOpacity(0.1),
                        child: const Icon(Icons.star, color: Color(0xFF082FBD)),
                      ),
                      title: Row(
                        children: [
                          Icon(Icons.star, color: Colors.amber.shade700, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (when.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text('• $when', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          ],
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (comment.isNotEmpty) Text(comment),
                          if (pickupId.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                '#$pickupId',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Show dialog to edit driver's TODA and update Firestore
  Future<void> _showEditTodaDialog({String? currentToda}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String? tempToda = currentToda;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit TODA'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'TODA',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: tempToda,
                    isExpanded: true,
                    hint: const Text('Select a TODA'),
                    items: _todaOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) {
                      setState(() {
                        tempToda = v;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (tempToda == null || tempToda!.isEmpty) {
                  _showError('Please select a TODA');
                  return;
                }
                try {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .update({'toda': tempToda});
                  if (mounted) {
                    Navigator.of(context).pop();
                    _showMessage('TODA updated to $tempToda');
                  }
                } catch (e) {
                  _showError('Failed to update TODA: $e');
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // Build driver profile content reused by sheet and full-screen
  Widget _buildDriverProfileContent() {
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Information
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .snapshots()
                    .handleError((_) {}),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox.shrink();
                  }

                  final userData = snapshot.data!.data() as Map<String, dynamic>?;
                  final name = (userData?['name'] ?? 'Driver').toString();
                  final phone = (userData?['phone'] ?? 'Not provided').toString();
                  final email = (userData?['email'] ?? user.email)?.toString() ?? '';
                  final licenseNumber = (userData?['licenseNumber'] ?? 'Not provided').toString();
                  final vehicleInfo = (userData?['vehicleInfo'] ?? 'Not provided').toString();
                  final toda = userData?['toda'] as String?;

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
                                child: const Icon(Icons.person, color: Color(0xFF082FBD), size: 32),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name.isNotEmpty ? name : 'Driver',
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 4),
                                    if (email.isNotEmpty)
                                      Text(
                                        email,
                                        style: TextStyle(color: Colors.black.withOpacity(0.6)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.local_taxi, size: 16, color: Colors.green),
                                                SizedBox(width: 6),
                                                Text('Driver', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
                                              ],
                                            ),
                                          ),
                                          if (toda != null && toda.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF082FBD).withOpacity(0.10),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Image.asset('assets/icons/TODA2.png', width: 16, height: 16, color: const Color(0xFF082FBD)),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    toda,
                                                    style: const TextStyle(color: Color(0xFF082FBD), fontWeight: FontWeight.w600),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
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
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Personal Information',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 12),
                              _buildInfoItem(Icons.person_outline, 'Name', name),
                              const SizedBox(height: 12),
                              _buildInfoItem(Icons.email_outlined, 'Email', email),
                              if (phone != 'Not provided') ...[
                                const SizedBox(height: 12),
                                _buildInfoItem(Icons.phone_outlined, 'Phone', phone),
                              ],
                              const SizedBox(height: 12),
                              _buildInfoItem(Icons.badge_outlined, 'License', licenseNumber),
                              const SizedBox(height: 12),
                              _buildInfoItem(Icons.directions_car_outlined, 'Vehicle', vehicleInfo),
                              const SizedBox(height: 12),
                              // Driver TODA with edit action
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Icon(Icons.apartment_outlined, color: Colors.black54),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'TODA',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.black54,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          toda == null || toda.isEmpty ? 'Not set' : toda,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _showEditTodaDialog(currentToda: toda),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Edit'),
                                  ),
                                ],
                              ),
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

  

  

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _licenseController.dispose();
    _vehicleController.dispose();
    _settingsSub?.cancel();
    _driverTodaSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  // Capture driver's license image using camera
  Future<void> _captureLicenseImage() async {
    setState(() {
      _ocrError = null;
    });
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        requestFullMetadata: false,
        imageQuality: 85,
      );
      if (image == null) {
        if (!mounted) return;
        setState(() {
          _ocrError = 'No image captured. Please try again.';
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _licenseImage = image;
        _isOcrProcessing = true;
      });

      await _runOcrOnImage(image);

      if (!mounted) return;
      setState(() {
        _isOcrProcessing = false;
      });

      // Optionally upload to Firebase Storage if user is logged in
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final url = await _uploadLicenseImage(File(image.path), user.uid);
          if (!mounted) return;
          setState(() {
            _uploadedLicenseImageUrl = url;
          });
          // Save URL under user profile for convenience
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            {
              'licenseImageUrl': url,
            },
            SetOptions(merge: true),
          );
        } catch (e) {
          // Ignore upload errors to keep OCR usable
        }
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _ocrError = e.code == 'camera_access_denied'
            ? 'Camera access denied. Please enable camera permissions.'
            : 'Failed to open camera. (${e.message ?? e.code})';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocrError = 'Unexpected error: $e';
      });
    }
  }

  Future<void> _runOcrOnImage(XFile image) async {
    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final fullText = recognizedText.text.toUpperCase();
      final extracted = _extractPhLicense(fullText);

      if (extracted != null) {
        if (!mounted) return;
        setState(() {
          _licenseController.text = extracted;
          _ocrError = null;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _ocrError = 'Could not detect a valid Philippine driver\'s license number. Please retake the photo.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocrError = 'Failed to process image. Please try again.';
      });
    }
  }

  // Extract and normalize PH license number. Accepts with or without hyphens.
  String? _extractPhLicense(String text) {
    // 1) Try strict pattern with hyphens
    final match = _phLicenseRegex.firstMatch(text);
    if (match != null) return match.group(0);

    // 2) Try compact form e.g., N1234567890 or N12 34 567890
    final compact = RegExp(r'[A-Z]\s*\d{2}\s*\d{2}\s*\d{6}').firstMatch(text);
    if (compact != null) {
      final raw = compact.group(0)!.replaceAll(RegExp(r'\s+'), '');
      // Ensure format N12-34-567890
      final normalized = raw.substring(0, 1) +
          raw.substring(1, 3) + '-' +
          raw.substring(3, 5) + '-' +
          raw.substring(5, 11);
      return normalized;
    }
    return null;
  }

  Future<String> _uploadLicenseImage(File file, String uid) async {
    final ref = FirebaseStorage.instance
        .ref()
        .child('drivers')
        .child(uid)
        .child('license')
        .child('license_${DateTime.now().millisecondsSinceEpoch}.jpg');
    final task = await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return await task.ref.getDownloadURL();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Avoid flashing a loading screen on first entry; show the login form instead
          return _buildLoginScreen();
        }

        final user = snapshot.data;
        if (user == null) {
          return _buildLoginScreen();
        }

        // Validate that the logged-in user is a driver before showing dashboard
        return FutureBuilder<bool>(
          future: () async {
            // 1) If sign-in already set local driver data, accept immediately
            if (_driverAuthService.currentDriverData != null) {
              return true;
            }
            // 2) Retry a few times to allow Firestore write/propagation
            for (int i = 0; i < 4; i++) {
              final ok = await _driverAuthService.initializeDriverData();
              if (ok) return true;
              await Future.delayed(const Duration(milliseconds: 300));
            }
            // 3) Fallback to a lightweight validity check
            return await _driverAuthService.isValidDriverSession();
          }(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: Text('Loading...')),
              );
            }
            final isValidDriver = snap.data == true;
            return _buildDriverScreen(user, isValidDriver);
          },
        );
      },
    );
  }

  Widget _buildDriverScreen(User? user, bool isValidDriver) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: null,
        title: Text(
          _currentTabIndex == 3
              ? l.t('driver_profile')
              : _currentTabIndex == 2
                  ? l.t('ratings')
                  : _currentTabIndex == 1
                      ? l.t('ride_history')
                      : l.t('driver_dashboard'),
        ),
        backgroundColor: const Color(0xFF082FBD),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: l.t('settings_title'),
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
      body: (user != null && isValidDriver)
          ? (_currentTabIndex == 3
              ? _buildDriverProfileContent()
              : _currentTabIndex == 2
                  ? _buildDriverRatingsContent()
                  : _currentTabIndex == 1
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 0),
                          child: _buildPickupHistoryContent(),
                        )
                      : _buildMapView())
          : (user != null
              // If authenticated but validation hasn't confirmed driver yet, keep a calm loading state
              ? const Center(child: Text('Loading...'))
              : _buildAuthForm()),
      bottomNavigationBar: (user != null && isValidDriver)
          ? BottomNavigationBar(
              currentIndex: _currentTabIndex,
              onTap: (index) {
                setState(() {
                  _currentTabIndex = index;
                });
              },
              showSelectedLabels: true,
              showUnselectedLabels: true,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: const Color(0xFF082FBD),
              unselectedItemColor: Colors.grey,
              selectedIconTheme: const IconThemeData(size: 28),
              unselectedIconTheme: const IconThemeData(size: 22),
              selectedFontSize: 14,
              unselectedFontSize: 12,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
              items: [
                BottomNavigationBarItem(
                  icon: const Icon(Icons.map_outlined),
                  label: l.t('map'),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.history),
                  label: l.t('history'),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.star),
                  label: l.t('ratings'),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.person_outline),
                  label: l.t('profile_nav'),
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildLoginScreen() {
    return _buildAuthForm();
  }

  void _listenToPickupUpdates() {
    // Listen for new pickup requests
    FirebaseFirestore.instance
        .collection('pickups')
        .where('status', isEqualTo: 'waiting')
        .snapshots()
        .listen(
          (snapshot) {
            _checkForNewPassengers(snapshot.docs);
          },
          onError: (error) {
            // Silently ignore permission or connectivity errors to avoid crashing the UI
          },
        );
  }

  void _listenToUserSettings() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _settingsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen(
          (doc) {
            final data = doc.data();
            final settings = (data?['settings'] as Map<String, dynamic>?) ?? {};
            final vib = settings['vibrationAlerts'] as bool?;
            if (vib != null && vib != _vibrationEnabled && mounted) {
              setState(() => _vibrationEnabled = vib);
            }
          },
          onError: (error) {
            // Ignore permission errors; settings will remain at defaults
          },
        );
  }

  // Listen to driver's TODA selection from their user profile
  void _listenToDriverToda() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _driverTodaSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen(
          (doc) {
            final data = doc.data();
            final toda = data != null ? data['toda'] as String? : null;
            if (!mounted) return;
            if (toda != _driverToda) {
              setState(() {
                _driverToda = toda;
              });
              // Subscribe driver to TODA topic for new ride request notifications
              if (toda != null && toda.isNotEmpty) {
                NotificationService().subscribeToTodaTopic(toda);
              }
            }
          },
          onError: (error) {
            // Ignore; TODA topic subscription is optional for initial login
          },
        );
  }


  /// Show logout confirmation dialog
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
      await _driverAuthService.signOut();
      if (mounted) {
        // Navigate back to AuthWrapper so it can route to HomeScreen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthWrapper()),
          (route) => false,
        );
      }
    }
  }

  /// Registration & Login form
  Widget _buildAuthForm() {
    return Container(
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isRegistering ? 'Create Driver Account' : 'Driver Login',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF082FBD),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isRegistering 
                        ? 'Join TODA GO as a driver'
                        : 'Sign in to start accepting rides',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (_isRegistering) ...[
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: "Full Name",
                        prefixIcon: Icon(Icons.person_outline),
                        hintText: "Enter your full name",
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: "Phone Number",
                        prefixIcon: Icon(Icons.phone_outlined),
                        hintText: "Enter your phone number",
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: "Email Address",
                      prefixIcon: const Icon(Icons.email_outlined),
                      hintText: "Enter your email address",
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
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _passwordObscured,
                    decoration: InputDecoration(
                      labelText: "Password",
                      prefixIcon: const Icon(Icons.lock_outline),
                      hintText: _isRegistering 
                          ? "Create a password (min. 6 characters)"
                          : "Enter your password",
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
                  if (!_isRegistering && _loginError.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        _loginError,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                  if (_isRegistering) ...[
                    const SizedBox(height: 12),
                    // Read-only display for driver's license number (auto-filled via OCR)
                    Visibility(
                      visible: _licenseController.text.isNotEmpty,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: "Driver's License Number",
                          prefixIcon: Icon(Icons.credit_card),
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          _licenseController.text.isNotEmpty
                              ? _licenseController.text
                              : 'Capture to auto-fill',
                          style: TextStyle(
                            color: _licenseController.text.isNotEmpty ? Colors.black87 : Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Visibility(
                      visible: _licenseController.text.isNotEmpty,
                      child: const SizedBox(height: 12),
                    ),
                    // capture button moved below TODA selector
                    if (_licenseImage != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 16/9,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(_licenseImage!.path),
                                fit: BoxFit.cover,
                              ),
                              if (_isOcrProcessing)
                                Container(
                                  color: Colors.black.withOpacity(0.3),
                                  child: const Center(
                                    child: CircularProgressIndicator(color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (_uploadedLicenseImageUrl != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.cloud_done, size: 18, color: Colors.green),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'License photo uploaded securely',
                                style: TextStyle(color: Colors.green.shade700, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: _vehicleController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: "Tricycle Number",
                        prefixIcon: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Image.asset(
                            'assets/icons/TODA2.png',
                            width: 24,
                            height: 24,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: "TODA",
                        prefixIcon: Icon(Icons.apartment_outlined),
                        border: OutlineInputBorder(),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedToda,
                          isDense: true,
                          isExpanded: true,
                          hint: const Text('Select a TODA'),
                          items: [
                            'NATODA',
                            'CARNATODA',
                            'ALTODA',
                            'LAPNATODA',
                            'Culaba',
                            'Cabucgayan',
                            'Maripipi',
                            'Biliran',
                          ].map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedToda = newValue;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isOcrProcessing ? null : _captureLicenseImage,
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: Text(_isOcrProcessing ? 'Processing...' : 'Capture Driver\'s License'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_ocrError != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _ocrError!,
                                style: TextStyle(color: Colors.red.shade700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isRegistering ? _register : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF082FBD),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _isRegistering ? "Create Driver Account" : "Sign In",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _isRegistering 
                            ? "Already have an account? " 
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
                            _clearForm();
                          });
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          _isRegistering ? "Sign In" : "Create Account",
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
    );
  }

  /// Leaflet Map with pickups from Firestore
  Widget _buildMapView() {
    // Require driver's TODA to filter pickups. If not yet loaded, show a light placeholder.
    if (_driverToda == null || _driverToda!.isEmpty) {
      return const Center(child: SizedBox.shrink());
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('pickups')
          .where('toda', isEqualTo: _driverToda)
          .snapshots()
          .handleError((_) {}),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Error loading pickups'));
        }
        if (!snapshot.hasData) {
          return const Center(child: SizedBox.shrink());
        }

        final pickups = snapshot.data!.docs;

        return Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: _navalCenter,
                initialZoom: 14,
                minZoom: 10,
                maxZoom: 22,
                cameraConstraint: CameraConstraint.contain(bounds: _navalBounds),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://api.maptiler.com/maps/hybrid/256/{z}/{x}/{y}.jpg?key=${_mapTilerKey}',
                  userAgentPackageName: 'com.example.toda_go',
                  tileProvider: NetworkTileProvider(),
                  maxNativeZoom: 22,
                ),
                MarkerLayer(
                  markers: pickups.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final dynamic rawLocation = data['location'];
                    double lat = 0.0;
                    double lng = 0.0;
                    if (rawLocation is GeoPoint) {
                      lat = rawLocation.latitude;
                      lng = rawLocation.longitude;
                    } else if (rawLocation is Map<String, dynamic>) {
                      lat = (rawLocation['lat'] as num?)?.toDouble() ?? 0.0;
                      lng = (rawLocation['lng'] as num?)?.toDouble() ?? 0.0;
                    }
                    if (lat == 0.0 && lng == 0.0) {
                      return Marker(point: const LatLng(0, 0), child: const SizedBox());
                    }
                    final status = data['status'] ?? 'waiting';
                    return Marker(
                      point: LatLng(lat, lng),
                      width: 50,
                      height: 50,
                      child: GestureDetector(
                        onTap: () => _showPassengerInfo(doc),
                        child: Icon(
                          Icons.person_pin_circle,
                          size: 40,
                          color: _statusColor(status),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            if (_showNewPassengerNotification)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.9),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_active, color: Colors.white, size: 24),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'New Passenger!',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _dismissNotification,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Pickup history content for history tab (enhanced UI only; logic preserved)
  Widget _buildPickupHistoryContent() {
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
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('pickups')
            .where('driverId', isEqualTo: user.uid)
            .orderBy('timestamp', descending: true)
            .snapshots()
            .handleError((_) {}),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 40, color: Colors.red.shade400),
                    const SizedBox(height: 12),
                    const Text('Error loading history', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('Please check your connection and try again', style: TextStyle(color: Colors.grey.shade600)),
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

          final data = snapshot.data?.docs ?? [];
          if (data.isEmpty) {
            return ListView(
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
                      const Text('No pickups yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text('Your completed rides will appear here', style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                const SizedBox(height: 160),
              ],
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {});
              await Future.delayed(const Duration(milliseconds: 500));
            },
            color: const Color(0xFF082FBD),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: data.length,
              itemBuilder: (context, index) {
                final pickup = data[index];
                final pickupData = pickup.data() as Map<String, dynamic>;
                final passengerCount = pickupData['count'] ?? 0;
                final toda = pickupData['toda'] ?? 'Unknown TODA';
                final status = pickupData['status'] ?? 'waiting';
                final timestamp = (pickupData['timestamp'] as Timestamp?)?.toDate();
                final passengerId = pickupData['passengerId'] ?? '';
                final cancelReason = (pickupData['cancelReason'] ?? '').toString().trim();

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      _showRideDetails(pickupData, pickup.id);
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
                                  color: _statusColor(status),
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _statusColor(status).withOpacity(0.15),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    passengerCount.toString(),
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
                                            color: _statusColor(status).withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: _statusColor(status), width: 1),
                                          ),
                                          child: Text(
                                            status.toUpperCase(),
                                            style: TextStyle(color: _statusColor(status), fontSize: 12, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                        if (passengerId.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          FutureBuilder<DocumentSnapshot>(
                                            future: FirebaseFirestore.instance.collection('users').doc(passengerId).get(),
                                            builder: (context, passengerSnapshot) {
                                              String passengerName = 'Unknown';
                                              if (passengerSnapshot.hasData && passengerSnapshot.data!.exists) {
                                                final userData = passengerSnapshot.data!.data() as Map<String, dynamic>?;
                                                passengerName = userData?['name'] ?? 'Unknown';
                                              }
                                              return Text(
                                                'Passenger: $passengerName',
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
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Show full ride information when a history item is tapped (Driver view)
  void _showRideDetails(Map<String, dynamic> pickup, String pickupId) {
    final String status = (pickup['status'] ?? 'unknown').toString();
    final String toda = (pickup['toda'] ?? 'Unknown').toString();
    final int count = (pickup['count'] ?? 0) is int
        ? pickup['count'] as int
        : int.tryParse(pickup['count']?.toString() ?? '0') ?? 0;
    final String passengerId = (pickup['passengerId'] ?? '').toString();
    final String cancelReason = (pickup['cancelReason'] ?? '').toString().trim();
    final String paymentMethod = (pickup['paymentMethod'] ?? 'cash').toString();
    final String paymentStatus = (pickup['paymentStatus'] ?? (paymentMethod == 'gcash' ? 'pending' : 'cash')).toString();
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
                                        color: _statusColor(status).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: _statusColor(status)),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: TextStyle(
                                          color: _statusColor(status),
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
                                _buildInfoItem(Icons.payment, 'Payment',
                                  paymentMethod.toLowerCase() == 'gcash'
                                      ? 'GCash (${paymentStatus.toUpperCase()})'
                                      : 'Cash'),
                                const SizedBox(height: 8),
                                _buildInfoItem(Icons.access_time, 'Requested', fullDate),
                                if (location != null) ...[
                                  const SizedBox(height: 8),
                                  _buildInfoItem(
                                    Icons.location_on_outlined,
                                    'Location',
                                    'Lat: ${location.latitude.toStringAsFixed(5)}, Lng: ${location.longitude.toStringAsFixed(5)}',
                                  ),
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
                        // Passenger section
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Passenger',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 8),
                                if (passengerId.isEmpty)
                                  Text('Unknown', style: TextStyle(color: Colors.grey.shade600))
                                else
                                  FutureBuilder<DocumentSnapshot>(
                                    future: FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(passengerId)
                                        .get(),
                                    builder: (context, snap) {
                                      if (snap.connectionState == ConnectionState.waiting) {
                                        return const Padding(
                                          padding: EdgeInsets.symmetric(vertical: 8),
                                          child: SizedBox.shrink(),
                                        );
                                      }
                                      String name = 'Unknown';
                                      String email = '';
                                      String phone = '';
                                      if (snap.hasData && snap.data!.exists) {
                                        final d = snap.data!.data() as Map<String, dynamic>?;
                                        name = d?['name'] ?? 'Unknown';
                                        email = (d?['email'] ?? '').toString();
                                        phone = (d?['phone'] ?? '').toString();
                                      }
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _buildInfoItem(Icons.person_outline, 'Name', name),
                                          if (email.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            _buildInfoItem(Icons.email_outlined, 'Email', email),
                                          ],
                                          if (phone.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            _buildInfoItem(Icons.phone_outlined, 'Phone', phone),
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

  /// Firebase Auth Register
  Future<void> _register() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final phone = _phoneController.text.trim();
    final license = _licenseController.text.trim();
    final vehicle = _vehicleController.text.trim();

    // Validation
    if (name.isEmpty) {
      _showError("Please enter your full name");
      return;
    }
    if (name.length < 2) {
      _showError("Please enter a valid name");
      return;
    }
    if (email.isEmpty) {
      _showError("Please enter your email address");
      return;
    }
    if (!_isValidEmail(email)) {
      _showError("Please enter a valid email address");
      return;
    }
    if (password.isEmpty) {
      _showError("Please enter a password");
      return;
    }
    if (password.length < 6) {
      _showError("Password must be at least 6 characters long");
      return;
    }
    if (license.isEmpty) {
      _showError("Please enter your driver's license number");
      return;
    }
    if (vehicle.isEmpty) {
      _showError("Please enter your vehicle information");
      return;
    }
    if (_selectedToda == null || _selectedToda!.isEmpty) {
      _showError("Please select a TODA");
      return;
    }

    try {
      // Register using AuthService
      final error = await _driverAuthService.registerDriver(
        name: name,
        email: email,
        password: password,
        licenseNumber: license,
        vehicleInfo: vehicle,
        toda: _selectedToda!,
      );

      if (error != null) {
        _showError(error);
        return;
      }
      // Save phone number if provided
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && phone.isNotEmpty) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            {'phone': phone},
            SetOptions(merge: true),
          );
        }
      } catch (_) {}
      
      // Ensure we land on the dashboard immediately
      if (mounted) {
        setState(() {
          _isRegistering = false;
          _currentTabIndex = 0;
        });
        _showMessage("Driver account created successfully! Welcome to TODA GO, $name!");
        _clearForm();
        // Hard navigate to DriverScreen to avoid being stuck in any sheet/context
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DriverScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      _showError(_getFirebaseErrorMessage(e.toString()));
    }
  }

  /// Firebase Auth Login
  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // Clear any previous inline error on new attempt
    if (_loginError.isNotEmpty || _emailError || _passwordError) {
      setState(() {
        _loginError = '';
        _emailError = false;
        _passwordError = false;
      });
    }

    // Validation
    if (email.isEmpty) {
      _showError("Please enter your email address");
      return;
    }
    if (!_isValidEmail(email)) {
      if (mounted) {
        setState(() {
          _emailError = true;
          _loginError = 'Incorrect Email';
        });
      }
      return;
    }
    if (password.isEmpty) {
      _showError("Please enter your password");
      return;
    }

    try {
      final error = await _driverAuthService.signIn(
        email: email,
        password: password,
      );
      
      if (error != null) {
        final lower = error.toLowerCase();
        if (lower.contains('wrong-password')) {
          if (mounted) {
            setState(() {
              _passwordError = true;
              _loginError = 'Incorrect Password';
            });
          }
        } else if (lower.contains('invalid-email') || lower.contains('user-not-found')) {
          if (mounted) {
            setState(() {
              _emailError = true;
              _loginError = 'Incorrect Email';
            });
          }
        } else {
          _showError(error);
        }
        return;
      }
      
      if (mounted) {
        setState(() {
          _isRegistering = false;
          _currentTabIndex = 0;
        });
        _showMessage("Welcome back, driver!");
        _clearForm();
        // Ensure we are on the Driver dashboard and clear any previous routes
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DriverScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('wrong-password')) {
        if (mounted) {
          setState(() {
            _passwordError = true;
            _loginError = 'Incorrect Password';
          });
        }
      } else if (msg.contains('invalid-email') || msg.contains('user-not-found')) {
        if (mounted) {
          setState(() {
            _emailError = true;
            _loginError = 'Incorrect Email';
          });
        }
      } else {
        _showError(_getFirebaseErrorMessage(e.toString()));
      }
    }
  }

  /// Check for new passengers and show notification
  void _checkForNewPassengers(List<QueryDocumentSnapshot> pickups) {
    if (pickups.isEmpty) return;
    
    // Find the most recent waiting pickup
    final waitingPickups = pickups.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data['status'] == 'waiting';
    }).toList();
    
    if (waitingPickups.isNotEmpty) {
      final mostRecentPickup = waitingPickups.first;
      final pickupId = mostRecentPickup.id;
      final pickupData = mostRecentPickup.data() as Map<String, dynamic>;
      final passengerCount = pickupData['count'] ?? 1;
      
      // Check if this is a new pickup we haven't seen before
      if (_lastKnownPickupId != null && _lastKnownPickupId != pickupId) {
        // This is a new pickup, show notification and vibrate after build is complete
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _showNewPassengerNotification = true;
            });
            
            // Trigger vibration based on passenger count
            _triggerNewPassengerVibration(passengerCount);
            
            // Auto-hide notification after 5 seconds
            Future.delayed(const Duration(seconds: 5), () {
              if (mounted) {
                setState(() {
                  _showNewPassengerNotification = false;
                });
              }
            });
          }
        });
      }
      
      // Update the last known pickup ID
      _lastKnownPickupId = pickupId;
    }
  }

  /// Trigger vibration for new passenger notification
  void _triggerNewPassengerVibration(int passengerCount) {
    if (!_vibrationEnabled) return;
    if (passengerCount > 3) {
      // Multiple passengers - use urgent vibration pattern
      _vibrationService.vibrateForUrgentNotification();
    } else {
      // Regular new passenger vibration
      _vibrationService.vibrateForNewPassenger();
    }
  }

  /// Dismiss the new passenger notification
  void _dismissNotification() {
    setState(() {
      _showNewPassengerNotification = false;
    });
  }

  /// Show passenger information in bottom sheet
  void _showPassengerInfo(QueryDocumentSnapshot pickupDoc) {
    final data = pickupDoc.data() as Map<String, dynamic>;
    final toda = data['toda'] ?? 'Unknown TODA';
    final passengerCount = data['count'] ?? 0;
    final status = data['status'] ?? 'waiting';
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final passengerId = data['passengerId'] ?? '';
    final String paymentMethod = (data['paymentMethod'] ?? 'cash').toString();
    final String paymentStatus = (data['paymentStatus'] ?? (paymentMethod == 'gcash' ? 'pending' : 'cash')).toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return FutureBuilder<DocumentSnapshot?>(
          future: passengerId.isNotEmpty 
              ? FirebaseFirestore.instance.collection('users').doc(passengerId).get()
              : Future.value(null),
          builder: (context, passengerSnapshot) {
            String passengerName = 'Unknown Passenger';
            if (passengerSnapshot.hasData && passengerSnapshot.data!.exists) {
              final passengerData = passengerSnapshot.data!.data() as Map<String, dynamic>?;
              passengerName = passengerData?['name'] ?? 'Unknown Passenger';
            }

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
                minHeight: MediaQuery.of(context).size.height * 0.4,
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
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: _statusColor(status),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Passenger Request',
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
                          _buildInfoItem(Icons.person_outline, 'Passenger', passengerName),
                          const SizedBox(height: 20),
                          _buildInfoItem(null, 'TODA', toda, customIcon: Image.asset(
                            'assets/icons/TODA2.png',
                            width: 20,
                            height: 20,
                            color: Colors.grey.shade600,
                          )),
                          const SizedBox(height: 20),
                          _buildInfoItem(Icons.people_outline, 'Passenger Count', '$passengerCount passenger${passengerCount > 1 ? 's' : ''}'),
                          const SizedBox(height: 20),
                          _buildInfoItem(Icons.info_outline, 'Status', status.toUpperCase()),
                          const SizedBox(height: 20),
                          _buildInfoItem(Icons.payment, 'Payment',
                            paymentMethod.toLowerCase() == 'gcash'
                                ? 'GCash (${paymentStatus.toUpperCase()})'
                                : 'Cash'),
                          if (timestamp != null) ...[
                            const SizedBox(height: 20),
                            _buildInfoItem(Icons.access_time, 'Requested', _formatTimestamp(timestamp)),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                Navigator.of(context).pop();
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      pickupId: pickupDoc.id,
                                      senderType: 'driver',
                                      title: 'Passenger Chat',
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
                          ),
                          const SizedBox(height: 32),
                          if (status == 'waiting') ...[
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _markOnTheWay(pickupDoc.id);
                                },
                                icon: const Icon(Icons.directions_car),
                                label: const Text('Accept Ride'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                              ),
                            ),
                          ],
                          if (status == 'onTheWay') ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _markArrived(pickupDoc.id);
                                },
                                icon: const Icon(Icons.location_on_outlined, color: Color(0xFF082FBD)),
                                label: const Text('Mark Arrived'),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF082FBD)),
                                  foregroundColor: const Color(0xFF082FBD),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _completeRide(pickupDoc.id, passengerId, passengerName);
                                },
                                icon: const Icon(Icons.check_circle),
                                label: const Text('Complete Ride'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                              ),
                            ),
                          ],
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
      },
    );
  }

  /// Build info item for passenger details
  Widget _buildInfoItem(IconData? icon, String label, String value, {Widget? customIcon}) {
    return Row(
      children: [
        customIcon ?? Icon(
          icon!,
          color: Colors.grey.shade600,
          size: 20,
        ),
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

  Future<void> _markOnTheWay(String pickupId) async {
    final user = _driverAuthService.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('pickups').doc(pickupId).update({
      'status': 'onTheWay',
      'driverId': user.uid,
    });

    _showMessage("Marked as On The Way!");

    // Notify passenger that driver is on the way
    try {
      await NotificationService().enqueuePassengerNotificationForPickup(
        pickupId: pickupId,
        title: 'Driver is on the way',
        body: 'Your driver is heading to your location.',
        data: {
          'type': 'on_the_way',
          'pickupId': pickupId,
        },
      );
      // Optional: subscribe driver to pickup topic for per-ride updates
      await NotificationService().subscribeToPickupTopic(pickupId);
    } catch (_) {}
  }

  Future<void> _completeRide(String pickupId, String passengerId, String passengerName) async {
    try {
      // Update pickup status to completed
      await FirebaseFirestore.instance.collection('pickups').doc(pickupId).update({
        'status': 'completed',
      });

      _showMessage("Ride completed successfully!");

      // Notify passenger that ride is completed
      try {
        await NotificationService().enqueuePassengerNotificationForPickup(
          pickupId: pickupId,
          title: 'Ride completed',
          body: 'Thanks for riding with TODA GO!',
          data: {
            'type': 'completed',
            'pickupId': pickupId,
          },
        );
      } catch (_) {}

      // Show rating dialog for the passenger
      if (mounted) {
        await showRatingDialog(
          context: context,
          pickupId: pickupId,
          ratingType: 'passenger_rating',
          ratedUserId: passengerId.isNotEmpty ? passengerId : null,
          ratedUserName: passengerName.isNotEmpty ? passengerName : null,
          onRatingSubmitted: () {
            // Optional: Add any post-rating logic here
          },
        );
      }
    } catch (e) {
      _showError("Failed to complete ride: $e");
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Format timestamp for display
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
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

  /// Status -> Color
  Color _statusColor(String status) {
    switch (status) {
      case 'waiting':
        return Colors.red;
      case 'onTheWay':
        return Colors.orange;
      case 'arrived':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  /// Validation and utility methods
  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  void _clearForm() {
    _nameController.clear();
    _emailController.clear();
    _passwordController.clear();
    _phoneController.clear();
    _licenseController.clear();
    _vehicleController.clear();
    _selectedToda = null; // Reset selection
  }

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
}
