import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PassengerRatingsScreen extends StatefulWidget {
  final String passengerId;

  const PassengerRatingsScreen({super.key, required this.passengerId});

  @override
  State<PassengerRatingsScreen> createState() => _PassengerRatingsScreenState();
}

class _PassengerRatingsScreenState extends State<PassengerRatingsScreen> {
  final Map<String, Future<String>> _driverNameFutures = {};

  Stream<QuerySnapshot<Map<String, dynamic>>>? get _ratingsStream {
    if (widget.passengerId.isEmpty) return null;
    return FirebaseFirestore.instance
        .collection('ratings')
        .where('raterId', isEqualTo: widget.passengerId)
        .where('ratingType', isEqualTo: 'driver_rating')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snapshot, _) => snapshot.data() ?? {},
          toFirestore: (data, _) => data,
        )
        .snapshots();
  }

  Future<String> _getDriverName(String driverId) {
    if (driverId.isEmpty) {
      return Future.value('Driver');
    }
    if (_driverNameFutures.containsKey(driverId)) {
      return _driverNameFutures[driverId]!;
    }
    final future = FirebaseFirestore.instance
        .collection('users')
        .doc(driverId)
        .get()
        .then((doc) {
      final data = doc.data();
      final name = data?['name']?.toString().trim();
      if (name == null || name.isEmpty) {
        return 'Driver';
      }
      return name;
    }).catchError((_) => 'Driver');
    _driverNameFutures[driverId] = future;
    return future;
  }

  @override
  Widget build(BuildContext context) {
    final ratingsStream = _ratingsStream;
    if (ratingsStream == null) {
      return const Center(
        child: Text(
          'Sign in to see your driver ratings.',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ratingsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Unable to load your ratings right now.',
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.star_outline,
                  size: 72,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No driver ratings yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'After you rate a driver, the rating will appear here.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 16, bottom: 32),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final driverId = (data['ratedUserId'] ?? '').toString();
            final ratingValue = (data['rating'] as num?)?.toDouble() ?? 0.0;
            final comment = (data['comment'] as String?)?.trim() ?? '';
            final ts = data['timestamp'];
            DateTime? ratedAt;
            if (ts is Timestamp) {
              ratedAt = ts.toDate();
            }

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FutureBuilder<String>(
                            future: _getDriverName(driverId),
                            builder: (context, nameSnap) {
                              final name = nameSnap.data ?? 'Driver';
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (ratedAt != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Rated • ${_formatDate(ratedAt)}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF082FBD).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.star,
                                size: 16,
                                color: Color(0xFF082FBD),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                ratingValue.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF082FBD),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (comment.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          comment,
                          style: const TextStyle(fontSize: 14, height: 1.4),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
  }
}
