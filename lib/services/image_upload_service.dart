import 'dart:io';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

class ImageUploadService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  Future<String?> pickAndUploadProfileImage() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );

      if (image == null) return null;

      final file = File(image.path);
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      final dataUri = 'data:image/jpeg;base64,$base64String';

      await _firestore.collection('users').doc(user.uid).set({
        'profileImageUrl': dataUri,
      }, SetOptions(merge: true));

      return dataUri;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteProfileImage() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Delete from Storage
      try {
        final ref = _storage.ref().child('profile_images/${user.uid}.jpg');
        await ref.delete();
      } catch (_) {}

      // Remove from Firestore
      await _firestore.collection('users').doc(user.uid).update({
        'profileImageUrl': FieldValue.delete(),
      });
    } catch (e) {
      print('Error deleting image: $e');
    }
  }
}
