import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  static const ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  const ChatService._internal();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> streamMessages({
    required String pickupId,
  }) {
    return _db
        .collection('pickups')
        .doc(pickupId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  Future<void> sendMessage({
    required String pickupId,
    required String text,
    String? senderType, // 'driver' | 'passenger'
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final now = FieldValue.serverTimestamp();

    await _db
        .collection('pickups')
        .doc(pickupId)
        .collection('messages')
        .add({
      'text': text.trim(),
      'senderId': user.uid,
      'senderType': senderType ?? 'unknown',
      'timestamp': now,
      'read': false,
    });

    // Optionally update lastMessage for quick previews
    await _db.collection('pickups').doc(pickupId).set({
      'lastMessage': text.trim(),
      'lastMessageAt': now,
    }, SetOptions(merge: true));
  }
}
