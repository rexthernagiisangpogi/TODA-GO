import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'dart:convert';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _licenseController = TextEditingController();
  final _vehicleController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _isDriver = false;
  
  // Profile picture variables
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _selectedImage;
  String? _currentProfilePictureUrl;
  bool _uploadingImage = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data() ?? {};
    final userType = (data['userType'] as String?)?.toLowerCase();
    _isDriver = userType == 'driver' || userType == 'adminDriver' || userType == 'standardDriver' || userType == 'premiumDriver';
    _nameController.text = (data['name'] as String?) ?? '';
    _phoneController.text = (data['phone'] as String?) ?? '';
    _licenseController.text = (data['licenseNumber'] as String?) ?? '';
    _vehicleController.text = (data['vehicleInfo'] as String?) ?? '';
    _currentProfilePictureUrl = (data['profilePictureUrl'] as String?);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      // Upload profile picture if selected
      String? profilePictureUrl = await _uploadProfilePicture();
      
      final Map<String, dynamic> payload = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
      };
      
      // Add profile picture URL if available
      if (profilePictureUrl != null) {
        payload['profilePictureUrl'] = profilePictureUrl;
      }
      
      if (_isDriver) {
        payload['licenseNumber'] = _licenseController.text.trim();
        payload['vehicleInfo'] = _vehicleController.text.trim();
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(payload, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update profile: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );
      if (image != null) {
        setState(() {
          _selectedImage = image;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  Future<String?> _uploadProfilePicture() async {
    if (_selectedImage == null) return _currentProfilePictureUrl;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not authenticated')),
        );
      }
      return null;
    }

    setState(() => _uploadingImage = true);
    
    try {
      print('Starting profile picture upload for user: ${user.uid}');
      
      // Try Firebase Storage first
      try {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('profile_pictures/${user.uid}.jpg');
        
        print('Storage reference created: ${storageRef.fullPath}');
        
        final metadata = SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'userId': user.uid,
            'uploadedAt': DateTime.now().toIso8601String(),
          },
        );
        
        final uploadTask = storageRef.putFile(File(_selectedImage!.path), metadata);
        final snapshot = await uploadTask;
        final downloadUrl = await snapshot.ref.getDownloadURL();
        
        print('Firebase Storage upload successful. Download URL: $downloadUrl');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile picture updated successfully!')),
          );
        }
        
        return downloadUrl;
      } catch (storageError) {
        print('Firebase Storage failed, trying Firestore fallback: $storageError');
        
        // Fallback: Store as base64 in Firestore (for development)
        final imageFile = File(_selectedImage!.path);
        final imageBytes = await imageFile.readAsBytes();
        final base64String = base64Encode(imageBytes);
        
        // Store base64 string with data URI prefix
        final dataUri = 'data:image/jpeg;base64,$base64String';
        
        print('Using Firestore fallback for profile picture storage');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile picture updated (using fallback storage)!')),
          );
        }
        
        return dataUri;
      }
    } catch (e) {
      print('General upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload image: $e')),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  ImageProvider? _getProfileImage() {
    // Priority 1: Show selected image (preview)
    if (_selectedImage != null) {
      return FileImage(File(_selectedImage!.path));
    }
    
    // Priority 2: Show existing profile picture
    if (_currentProfilePictureUrl != null) {
      // Check if it's a base64 data URI
      if (_currentProfilePictureUrl!.startsWith('data:image/')) {
        try {
          // Extract base64 data from data URI
          final base64Data = _currentProfilePictureUrl!.split(',')[1];
          final bytes = base64Decode(base64Data);
          return MemoryImage(bytes);
        } catch (e) {
          print('Error decoding base64 image: $e');
          return null;
        }
      } else {
        // Regular network image URL
        return NetworkImage(_currentProfilePictureUrl!);
      }
    }
    
    // Priority 3: No image available
    return null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _licenseController.dispose();
    _vehicleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFF082FBD),
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF082FBD), Color(0xFF3D64FF)],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFE8F0FF), Colors.white],
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: _pickImage,
                              child: Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 32,
                                    backgroundColor: const Color(0xFF082FBD).withOpacity(0.12),
                                    backgroundImage: _getProfileImage(),
                                    child: (_selectedImage == null && _currentProfilePictureUrl == null)
                                        ? Icon(
                                            _isDriver ? Icons.directions_car_filled : Icons.person_outline,
                                            size: 32,
                                            color: const Color(0xFF082FBD),
                                          )
                                        : null,
                                  ),
                                  if (_uploadingImage)
                                    Positioned.fill(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.5),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Center(
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF082FBD),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _nameController.text.isNotEmpty ? _nameController.text : 'Your Profile',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
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
                                        color: (_isDriver ? Colors.green : Colors.blue).withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _isDriver ? Icons.local_taxi : Icons.person,
                                            size: 16,
                                            color: _isDriver ? Colors.green : Colors.blue,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _isDriver ? 'Driver' : 'Passenger',
                                            style: TextStyle(
                                              color: _isDriver ? Colors.green : Colors.blue,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
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
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  labelText: 'Full Name',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Name is required';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Phone',
                                  prefixIcon: Icon(Icons.phone_outlined),
                                ),
                              ),
                              if (_isDriver)
                                Column(
                                  children: [
                                    const SizedBox(height: 16),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Row(
                                        children: const [
                                          Icon(Icons.drive_eta_outlined, size: 18, color: Color(0xFF082FBD)),
                                          SizedBox(width: 6),
                                          Text(
                                            'Driver Details',
                                            style: TextStyle(fontWeight: FontWeight.w700),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _licenseController,
                                      textCapitalization: TextCapitalization.characters,
                                      decoration: const InputDecoration(
                                        labelText: "Driver's License Number",
                                        prefixIcon: Icon(Icons.badge_outlined),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _vehicleController,
                                      textCapitalization: TextCapitalization.sentences,
                                      decoration: const InputDecoration(
                                        labelText: 'Vehicle Information',
                                        prefixIcon: Icon(Icons.directions_car_outlined),
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _saving ? null : _save,
                                  icon: _saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.save_outlined),
                                  label: Text(_saving ? 'Saving...' : 'Save Changes'),
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
              ),
            ),
    );
  }
}
