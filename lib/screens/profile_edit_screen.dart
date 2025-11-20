import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _licenseController = TextEditingController();
  final _vehicleController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _isDriver = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
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
    if (mounted) {
      setState(() => _loading = false);
      _animationController.forward();
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> payload = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
      };
      
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



  @override
  void dispose() {
    _animationController.dispose();
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
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
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
                              child: _isDriver
                                  ? Image.asset(
                                      'assets/icons/TODA2.png',
                                      width: 32,
                                      height: 32,
                                      fit: BoxFit.contain,
                                      color: const Color(0xFF082FBD),
                                    )
                                  : const Icon(
                                      Icons.person_outline,
                                      size: 32,
                                      color: Color(0xFF082FBD),
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
                                          _isDriver
                                              ? SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: Image.asset(
                                                    'assets/icons/TODA2.png',
                                                    fit: BoxFit.contain,
                                                    color: Colors.green,
                                                  ),
                                                )
                                              : Icon(
                                                  Icons.person,
                                                  size: 16,
                                                  color: Colors.blue,
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
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Full Name',
                                  prefixIcon: Icon(Icons.person_outline),
                                  border: OutlineInputBorder(),
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
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Phone',
                                  prefixIcon: Icon(Icons.phone_outlined),
                                  border: OutlineInputBorder(),
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
                                      textInputAction: TextInputAction.next,
                                      decoration: const InputDecoration(
                                        labelText: "Driver's License Number",
                                        prefixIcon: Icon(Icons.badge_outlined),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _vehicleController,
                                      textCapitalization: TextCapitalization.sentences,
                                      textInputAction: TextInputAction.done,
                                      decoration: InputDecoration(
                                        labelText: 'Vehicle Information',
                                        prefixIcon: Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: Image.asset(
                                            'assets/icons/TODA2.png',
                                            width: 24,
                                            height: 24,
                                            fit: BoxFit.contain,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        border: const OutlineInputBorder(),
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 24),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _saving ? null : _save,
                                  icon: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: _saving
                                        ? const SizedBox(
                                            key: ValueKey('loading'),
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.save_outlined, key: ValueKey('icon')),
                                  ),
                                  label: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: Text(
                                      _saving ? 'Saving...' : 'Save Changes',
                                      key: ValueKey(_saving),
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF082FBD),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    elevation: _saving ? 0 : 2,
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
            ),
    );
  }
}
