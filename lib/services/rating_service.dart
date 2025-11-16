import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RatingService {
  static const RatingService _instance = RatingService._internal();
  factory RatingService() => _instance;
  const RatingService._internal();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  /// Submit a rating for a completed ride (handles both new ratings and updates)
  Future<String?> submitRating({
    required String pickupId,
    required double rating,
    required String ratingType, // 'driver_rating' or 'passenger_rating'
    String? comment,
    String? ratedUserId,
    bool allowUpdate = false, // Allow updating existing ratings
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'User not authenticated';

      if (rating < 1 || rating > 5) return 'Rating must be between 1 and 5 stars';

      // Check if user has already rated this pickup
      final existingRating = await getUserRatingForPickup(pickupId, ratingType);
      
      if (existingRating != null) {
        if (allowUpdate) {
          // Update existing rating
          return await updateRating(
            ratingId: existingRating['id'],
            pickupId: pickupId,
            rating: rating,
            ratingType: ratingType,
            comment: comment,
            ratedUserId: ratedUserId,
          );
        } else {
          return 'You have already submitted a rating for this ride.';
        }
      }

      // Create new rating
      final ratingData = {
        'pickupId': pickupId,
        'raterId': user.uid,
        'ratedUserId': ratedUserId,
        'rating': rating,
        'comment': comment ?? '',
        'ratingType': ratingType,
        'timestamp': FieldValue.serverTimestamp(),
      };

      // Store the rating in the ratings collection
      await _firestore.collection('ratings').add(ratingData);

      // Update the pickup document with the rating
      await _firestore.collection('pickups').doc(pickupId).update({
        ratingType: rating,
        '${ratingType}_comment': comment ?? '',
        '${ratingType}_timestamp': FieldValue.serverTimestamp(),
      });

      // Update user's average rating if rating another user
      if (ratedUserId != null) {
        await _updateUserAverageRating(ratedUserId, ratingType);
      }

      return null; // Success
    } catch (e) {
      return 'Failed to submit rating: ${e.toString()}';
    }
  }

  /// Update user's average rating
  Future<void> _updateUserAverageRating(String userId, String ratingType) async {
    try {
      // Get all ratings for this user of this type
      final ratingsQuery = await _firestore
          .collection('ratings')
          .where('ratedUserId', isEqualTo: userId)
          .where('ratingType', isEqualTo: ratingType)
          .get();

      if (ratingsQuery.docs.isEmpty) return;

      // Calculate average rating
      double totalRating = 0;
      int count = 0;

      for (final doc in ratingsQuery.docs) {
        final data = doc.data();
        final rating = (data['rating'] as num?)?.toDouble() ?? 0;
        if (rating > 0) {
          totalRating += rating;
          count++;
        }
      }

      if (count > 0) {
        final averageRating = totalRating / count;
        
        // Update user document with average rating
        final ratingField = ratingType == 'driver_rating' ? 'averageDriverRating' : 'averagePassengerRating';
        final countField = ratingType == 'driver_rating' ? 'driverRatingCount' : 'passengerRatingCount';
        
        await _firestore.collection('users').doc(userId).update({
          ratingField: averageRating,
          countField: count,
        });
      }
    } catch (e) {
      print('Error updating average rating: $e');
    }
  }

  /// Get user's average rating
  Future<Map<String, dynamic>> getUserRating(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      
      if (!userDoc.exists) {
        return {
          'averageDriverRating': 0.0,
          'driverRatingCount': 0,
          'averagePassengerRating': 0.0,
          'passengerRatingCount': 0,
        };
      }

      final data = userDoc.data() as Map<String, dynamic>;
      return {
        'averageDriverRating': (data['averageDriverRating'] as num?)?.toDouble() ?? 0.0,
        'driverRatingCount': data['driverRatingCount'] ?? 0,
        'averagePassengerRating': (data['averagePassengerRating'] as num?)?.toDouble() ?? 0.0,
        'passengerRatingCount': data['passengerRatingCount'] ?? 0,
      };
    } catch (e) {
      return {
        'averageDriverRating': 0.0,
        'driverRatingCount': 0,
        'averagePassengerRating': 0.0,
        'passengerRatingCount': 0,
      };
    }
  }

  /// Check if user has already rated a specific pickup
  Future<bool> hasUserRated(String pickupId, String ratingType) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final query = await _firestore
          .collection('ratings')
          .where('pickupId', isEqualTo: pickupId)
          .where('raterId', isEqualTo: user.uid)
          .where('ratingType', isEqualTo: ratingType)
          .limit(1)
          .get();

      return query.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Get user's existing rating for a specific pickup
  Future<Map<String, dynamic>?> getUserRatingForPickup(String pickupId, String ratingType) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final query = await _firestore
          .collection('ratings')
          .where('pickupId', isEqualTo: pickupId)
          .where('raterId', isEqualTo: user.uid)
          .where('ratingType', isEqualTo: ratingType)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return null;

      final doc = query.docs.first;
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    } catch (e) {
      return null;
    }
  }

  /// Update an existing rating
  Future<String?> updateRating({
    required String ratingId,
    required String pickupId,
    required double rating,
    required String ratingType,
    String? comment,
    String? ratedUserId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'User not authenticated';

      if (rating < 1 || rating > 5) return 'Rating must be between 1 and 5 stars';

      final ratingData = {
        'rating': rating,
        'comment': comment ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Update the rating in the ratings collection
      await _firestore.collection('ratings').doc(ratingId).update(ratingData);

      // Update the pickup document with the new rating
      await _firestore.collection('pickups').doc(pickupId).update({
        ratingType: rating,
        '${ratingType}_comment': comment ?? '',
        '${ratingType}_timestamp': FieldValue.serverTimestamp(),
      });

      // Update user's average rating if rating another user
      if (ratedUserId != null) {
        await _updateUserAverageRating(ratedUserId, ratingType);
      }

      return null; // Success
    } catch (e) {
      return 'Failed to update rating: ${e.toString()}';
    }
  }

  /// Get ratings for a specific pickup
  Future<List<Map<String, dynamic>>> getPickupRatings(String pickupId) async {
    try {
      final query = await _firestore
          .collection('ratings')
          .where('pickupId', isEqualTo: pickupId)
          .orderBy('timestamp', descending: true)
          .get();

      return query.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get app's overall rating statistics
  Future<Map<String, dynamic>> getAppRatingStats() async {
    try {
      final ratingsQuery = await _firestore.collection('ratings').get();
      
      if (ratingsQuery.docs.isEmpty) {
        return {
          'averageRating': 0.0,
          'totalRatings': 0,
          'ratingDistribution': {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
        };
      }

      double totalRating = 0;
      int count = 0;
      Map<int, int> distribution = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};

      for (final doc in ratingsQuery.docs) {
        final data = doc.data();
        final rating = (data['rating'] as num?)?.toDouble() ?? 0;
        if (rating > 0) {
          totalRating += rating;
          count++;
          final roundedRating = rating.round();
          if (roundedRating >= 1 && roundedRating <= 5) {
            distribution[roundedRating] = (distribution[roundedRating] ?? 0) + 1;
          }
        }
      }

      return {
        'averageRating': count > 0 ? totalRating / count : 0.0,
        'totalRatings': count,
        'ratingDistribution': distribution,
      };
    } catch (e) {
      return {
        'averageRating': 0.0,
        'totalRatings': 0,
        'ratingDistribution': {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
      };
    }
  }
}
