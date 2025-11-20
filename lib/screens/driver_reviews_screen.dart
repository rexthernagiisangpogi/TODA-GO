import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/rating_display.dart';

class DriverReviewsScreen extends StatefulWidget {
  final String driverId;
  final String? driverName;

  const DriverReviewsScreen({super.key, required this.driverId, this.driverName});

  @override
  State<DriverReviewsScreen> createState() => _DriverReviewsScreenState();
}

class _DriverReviewsScreenState extends State<DriverReviewsScreen> {
  final Map<String, Future<String>> _passengerNameFutures = {};

  Future<String> _getPassengerName(String passengerId) {
    if (passengerId.isEmpty) return Future.value('Passenger');
    if (_passengerNameFutures.containsKey(passengerId)) {
      return _passengerNameFutures[passengerId]!;
    }
    final future = FirebaseFirestore.instance
        .collection('users')
        .doc(passengerId)
        .get()
        .then((doc) {
      final data = doc.data();
      final name = data?['name']?.toString().trim();
      if (name == null || name.isEmpty) return 'Passenger';
      return name;
    }).catchError((_) => 'Passenger');
    _passengerNameFutures[passengerId] = future;
    return future;
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.driverName == null || widget.driverName!.isEmpty
            ? 'Driver Reviews'
            : '${widget.driverName!} — Reviews'),
        backgroundColor: const Color(0xFF082FBD),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('ratings')
            .where('ratedUserId', isEqualTo: widget.driverId)
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
                  Icon(Icons.reviews_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text('No reviews yet', style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;
          double sum = 0.0;
          for (final d in docs) {
            final m = d.data() as Map<String, dynamic>;
            sum += (m['rating'] as num?)?.toDouble() ?? 0.0;
          }
          final count = docs.length;
          final avg = count == 0 ? 0.0 : (sum / count);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFF082FBD).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.star, color: Color(0xFF082FBD), size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Overall Rating',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                count == 1 ? '1 rating' : '$count ratings',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        RatingDisplay(
                          rating: avg,
                          ratingCount: count,
                          size: 22,
                          showCount: false,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: count,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
                    final comment = (data['comment'] as String?)?.trim() ?? '';
                    final ts = data['timestamp'] as Timestamp?;
                    final raterName = (data['raterName'] as String?)?.trim() ?? '';
                    final raterId = (data['raterId'] ?? '').toString();
                    final formattedDate = _formatDate(ts);

                    Widget nameWidget;
                    if (raterName.isNotEmpty) {
                      nameWidget = Text(
                        raterName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    } else if (raterId.isNotEmpty) {
                      nameWidget = FutureBuilder<String>(
                        future: _getPassengerName(raterId),
                        builder: (context, snapshot) {
                          final resolved = snapshot.data ?? 'Passenger';
                          return Text(
                            resolved,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        },
                      );
                    } else {
                      nameWidget = const Text(
                        'Passenger',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }

                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: const Color(0xFF082FBD).withOpacity(0.08),
                                  child: const Icon(Icons.person, color: Color(0xFF082FBD)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: nameWidget),
                                if (formattedDate.isNotEmpty)
                                  Text(
                                    formattedDate,
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            RatingDisplay(rating: rating, ratingCount: 0, size: 16, showCount: false),
                            if (comment.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(comment),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
