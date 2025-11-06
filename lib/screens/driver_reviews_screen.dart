import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/rating_display.dart';

class DriverReviewsScreen extends StatelessWidget {
  final String driverId;
  final String? driverName;

  const DriverReviewsScreen({super.key, required this.driverId, this.driverName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(driverName == null || driverName!.isEmpty
            ? 'Driver Reviews'
            : '${driverName!} — Reviews'),
        backgroundColor: const Color(0xFF082FBD),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('ratings')
            .where('ratedUserId', isEqualTo: driverId)
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
          // Compute overall average rating from the fetched docs
          double sum = 0.0;
          for (final d in docs) {
            final m = d.data() as Map<String, dynamic>;
            sum += (m['rating'] as num?)?.toDouble() ?? 0.0;
          }
          final count = docs.length;
          final avg = count == 0 ? 0.0 : (sum / count);

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: count + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.star, color: Color(0xFF082FBD)),
                        const SizedBox(width: 8),
                        RatingDisplay(rating: avg, ratingCount: count, size: 18, showCount: true),
                      ],
                    ),
                  ),
                );
              }

              final data = docs[index - 1].data() as Map<String, dynamic>;
              final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
              final comment = (data['comment'] as String?)?.trim() ?? '';
              final ts = data['timestamp'];
              String when = '';
              if (ts is Timestamp) {
                final dt = ts.toDate();
                when = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
              }

              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF082FBD).withOpacity(0.08),
                    child: const Icon(Icons.star, color: Color(0xFF082FBD)),
                  ),
                  title: Row(
                    children: [
                      RatingDisplay(rating: rating, ratingCount: 0, size: 16, showCount: false),
                      if (when.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(when, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ],
                  ),
                  subtitle: comment.isEmpty
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text(comment),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
