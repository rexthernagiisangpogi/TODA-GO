import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/push_notification_service.dart';
import '../services/location_service.dart';
import 'profile_edit_screen.dart';
import 'change_email_screen.dart';
import 'change_password_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_of_service_screen.dart';
import 'how_to_use_screen.dart';
import '../l10n/app_localizations.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Local UI state (placeholders; hook up to real settings later)
  bool _pushNotifications = true;
  bool _vibrationAlerts = true;
  bool _locationServices = true;
  String _userType = 'passenger';

  // Styled circular icon badge for consistent leading/secondary visuals
  Widget _iconBadge(IconData icon) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: const Color(0xFF082FBD).withOpacity(0.12),
      child: Icon(icon, color: const Color(0xFF082FBD), size: 20),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data();
    final settings = (data?['settings'] as Map<String, dynamic>?) ?? {};

    setState(() {
      _pushNotifications = (settings['pushNotifications'] as bool?) ?? _pushNotifications;
      _vibrationAlerts = (settings['vibrationAlerts'] as bool?) ?? _vibrationAlerts;
      _locationServices = (settings['locationServices'] as bool?) ?? _locationServices;
      _userType = (data?['userType'] as String?) ?? 'passenger';
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    await userRef.set({
      'settings': {key: value}
    }, SetOptions(merge: true));
  }


  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(l.t('settings_title')),
        backgroundColor: const Color(0xFF082FBD),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade50,
              Colors.white,
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
          _sectionHeader(l.t('account')),
          Card(
            elevation: 3,
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: _iconBadge(Icons.person_outline),
                  title: Text(l.t('profile')),
                  subtitle: Text(l.t('profile_desc')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileEditScreen()),
                    );
                  },
                ),

          const SizedBox(height: 16),
          // Language selection moved to About section

                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: _iconBadge(Icons.email_outlined),
                  title: Text(l.t('change_email')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ChangeEmailScreen()),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: _iconBadge(Icons.lock_outline),
                  title: Text(l.t('change_password')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          _sectionHeader(l.t('notifications_privacy')),
          Card(
            elevation: 3,
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  value: _pushNotifications,
                  onChanged: (v) async {
                    setState(() => _pushNotifications = v);
                    await _saveSetting('pushNotifications', v);
                    final user = FirebaseAuth.instance.currentUser;
                    if (v) {
                      // Enable push: initialize messaging and sync token
                      await PushNotificationService.initialize();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("${l.t('push_notifications')}: ON")),
                      );
                    } else {
                      // Disable push: delete token and remove from user profile
                      try {
                        await FirebaseMessaging.instance.deleteToken();
                      } catch (_) {}
                      if (user != null) {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .set({'fcmToken': FieldValue.delete()}, SetOptions(merge: true));
                      }
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("${l.t('push_notifications')}: OFF")),
                      );
                    }
                  },
                  secondary: _iconBadge(Icons.notifications_outlined),
                  title: Text(l.t('push_notifications')),
                  subtitle: Text(l.t('push_notifications_desc')),
                  activeColor: const Color(0xFF082FBD),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  value: _vibrationAlerts,
                  onChanged: (v) async {
                    setState(() => _vibrationAlerts = v);
                    await _saveSetting('vibrationAlerts', v);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("${l.t('vibration_alerts')}: ${v ? 'ON' : 'OFF'}")),
                    );
                  },
                  secondary: _iconBadge(Icons.vibration),
                  title: Text(l.t('vibration_alerts')),
                  subtitle: Text(l.t('vibration_alerts_desc')),
                  activeColor: const Color(0xFF082FBD),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  value: _locationServices,
                  onChanged: (v) async {
                    setState(() => _locationServices = v);
                    await _saveSetting('locationServices', v);
                    if (v) {
                      // Prompt for permission by trying to fetch location once
                      try {
                        await LocationService().getCurrentLocation();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("${l.t('location_services')}: ON")),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("${l.t('location_services')}: $e")),
                        );
                      }
                    } else {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("${l.t('location_services')}: OFF")),
                      );
                    }
                  },
                  secondary: _iconBadge(Icons.location_on_outlined),
                  title: Text(l.t('location_services')),
                  subtitle: Text(l.t('location_services_desc')),
                  activeColor: const Color(0xFF082FBD),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: _iconBadge(Icons.privacy_tip_outlined),
                  title: Text(l.t('privacy_policy')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: _iconBadge(Icons.description_outlined),
                  title: Text(l.t('terms_of_service')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TermsOfServiceScreen()),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          _sectionHeader(l.t('about')),
          Card(
            elevation: 3,
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: _iconBadge(Icons.help_outline),
                  title: const Text('How to use TODA GO'),
                  subtitle: const Text('Learn how to use all features'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => HowToUseScreen(userType: _userType),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: _iconBadge(Icons.info_outline),
                  title: Text(l.t('app_version')),
                  subtitle: const Text('1.0.0'),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: _iconBadge(Icons.support_agent),
                  title: Text(l.t('contact_support')),
                  subtitle: const Text('support@todago.app'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            height: 24,
            width: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF082FBD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF082FBD),
            ),
          ),
        ],
      ),
    );
  }
}
