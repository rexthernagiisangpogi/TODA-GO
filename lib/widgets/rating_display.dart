import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

class RatingDisplay extends StatelessWidget {
  final double rating;
  final int ratingCount;
  final double size;
  final bool showCount;
  final Color? color;

  const RatingDisplay({
    super.key,
    required this.rating,
    this.ratingCount = 0,
    this.size = 16,
    this.showCount = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (rating <= 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_border,
            size: size,
            color: Colors.grey.shade400,
          ),
          if (showCount) ...[
            const SizedBox(width: 4),
            Text(
              'No ratings yet',
              style: TextStyle(
                fontSize: size * 0.75,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RatingBarIndicator(
          rating: rating,
          itemBuilder: (context, index) => Icon(
            Icons.star,
            color: color ?? Colors.amber,
          ),
          itemCount: 5,
          itemSize: size,
          direction: Axis.horizontal,
        ),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
            fontSize: size * 0.75,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        if (showCount && ratingCount > 0) ...[
          Text(
            ' (${ratingCount})',
            style: TextStyle(
              fontSize: size * 0.7,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ],
    );
  }
}

class CompactRatingDisplay extends StatelessWidget {
  final double rating;
  final int ratingCount;

  const CompactRatingDisplay({
    super.key,
    required this.rating,
    this.ratingCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (rating <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_border,
              size: 14,
              color: Colors.grey.shade400,
            ),
            const SizedBox(width: 4),
            Text(
              'New',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    Color badgeColor;
    if (rating >= 4.5) {
      badgeColor = Colors.green;
    } else if (rating >= 4.0) {
      badgeColor = Colors.lightGreen;
    } else if (rating >= 3.5) {
      badgeColor = Colors.orange;
    } else {
      badgeColor = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star,
            size: 14,
            color: badgeColor,
          ),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 12,
              color: badgeColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (ratingCount > 0) ...[
            Text(
              ' (${ratingCount})',
              style: TextStyle(
                fontSize: 10,
                color: badgeColor.withOpacity(0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
