import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UnreadMessageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<int> getUnreadCount(String pickupId) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return Stream.value(0);

    return _firestore
        .collection('pickups')
        .doc(pickupId)
        .collection('messages')
        .where('senderId', isNotEqualTo: userId)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Future<void> markAsRead(String pickupId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final messages = await _firestore
        .collection('pickups')
        .doc(pickupId)
        .collection('messages')
        .where('senderId', isNotEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();

    final batch = _firestore.batch();
    for (var doc in messages.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }
}
