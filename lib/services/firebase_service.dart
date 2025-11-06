import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> addPickup({
    required String driverId,
    required String passengerId,
    required String destination,
    required String color,
    required int count,
  }) async {
    await _db.collection('pickups').add({
      'driverId': driverId,
      'passengerId': passengerId,
      'destination': destination,
      'color': color,
      'count': count,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
