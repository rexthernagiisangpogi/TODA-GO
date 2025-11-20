import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import '../services/rating_service.dart';

class RatingDialog extends StatefulWidget {
  final String pickupId;
  final String ratingType; // 'driver_rating' or 'passenger_rating'
  final String? ratedUserId;
  final String? ratedUserName;
  final VoidCallback? onRatingSubmitted;
  final bool allowUpdate; // Allow updating existing ratings

  const RatingDialog({
    super.key,
    required this.pickupId,
    required this.ratingType,
    this.ratedUserId,
    this.ratedUserName,
    this.onRatingSubmitted,
    this.allowUpdate = false,
  });

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  final RatingService _ratingService = RatingService();
  final TextEditingController _commentController = TextEditingController();
  
  double _rating = 5.0;
  bool _isSubmitting = false;
  bool _isLoading = true;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _loadExistingRating();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingRating() async {
    if (widget.allowUpdate) {
      final existingRating = await _ratingService.getUserRatingForPickup(
        widget.pickupId,
        widget.ratingType,
      );
      
      if (existingRating != null) {
        setState(() {
          _rating = (existingRating['rating'] as num?)?.toDouble() ?? 5.0;
          _commentController.text = existingRating['comment'] ?? '';
          _isUpdating = true;
        });
      }
    }
    
    setState(() {
      _isLoading = false;
    });
  }

  String get _dialogTitle {
    if (_isUpdating) {
      if (widget.ratingType == 'driver_rating') {
        return 'Update Driver Rating';
      } else {
        return 'Update Rating';
      }
    } else {
      if (widget.ratingType == 'driver_rating') {
        return 'Rate Your Driver';
      } else {
        return 'Rate Your Experience';
      }
    }
  }

  String get _dialogSubtitle {
    if (_isUpdating) {
      return 'Update your previous rating';
    } else {
      if (widget.ratingType == 'driver_rating' && widget.ratedUserName != null) {
        return 'How was your ride with ${widget.ratedUserName}?';
      } else if (widget.ratingType == 'passenger_rating' && widget.ratedUserName != null) {
        return 'How was your experience with ${widget.ratedUserName}?';
      } else {
        return 'How was your TODA GO experience?';
      }
    }
  }

  List<String> get _ratingLabels {
    switch (_rating.round()) {
      case 1:
        return ['Poor', 'Needs improvement'];
      case 2:
        return ['Fair', 'Could be better'];
      case 3:
        return ['Good', 'Average experience'];
      case 4:
        return ['Very Good', 'Great experience'];
      case 5:
        return ['Excellent', 'Outstanding service!'];
      default:
        return ['', ''];
    }
  }

  Color get _ratingColor {
    switch (_rating.round()) {
      case 1:
      case 2:
        return Colors.red;
      case 3:
        return Colors.orange;
      case 4:
      case 5:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Loading...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 24,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.grey.shade50,
            ],
          ),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF082FBD), Color(0xFF3D64FF)],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF082FBD).withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Image.asset(
                      'assets/icons/TODA2.png',
                      width: 26,
                      height: 26,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _dialogTitle,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF082FBD),
                        ),
                      ),
                      Text(
                        _dialogSubtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  color: Colors.grey.shade600,
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Rating Stars
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: RatingBar.builder(
                initialRating: _rating,
                minRating: 1,
                direction: Axis.horizontal,
                allowHalfRating: false,
                itemCount: 5,
                itemSize: 44,
                unratedColor: Colors.grey.shade300,
                itemPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                itemBuilder: (context, _) => const Icon(
                  Icons.star,
                  color: Color(0xFFFFC107),
                ),
                onRatingUpdate: (rating) {
                  setState(() {
                    _rating = rating;
                  });
                },
              ),
            ),
            const SizedBox(height: 16),

            // Rating Label
            Column(
              children: [
                Text(
                  _ratingLabels[0],
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: _ratingColor,
                  ),
                ),
                Text(
                  _ratingLabels[1],
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Comment Field
            TextField(
              controller: _commentController,
              maxLines: 3,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: 'Additional Comments (Optional)',
                hintText: 'Share your experience...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF082FBD),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                counterStyle: TextStyle(color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: const BorderSide(color: Color(0xFF082FBD)),
                    ),
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: Color(0xFF082FBD),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitRating,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF082FBD),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                          _isUpdating ? 'Update Rating' : 'Submit Rating',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitRating() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      final comment = _commentController.text.trim();
      
      final error = await _ratingService.submitRating(
        pickupId: widget.pickupId,
        rating: _rating,
        ratingType: widget.ratingType,
        comment: comment.isEmpty ? null : comment,
        ratedUserId: widget.ratedUserId,
        allowUpdate: widget.allowUpdate,
      );

      if (error != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        if (mounted) {
          Navigator.of(context).pop();
          final actionText = _isUpdating ? 'updated' : 'submitted';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rating $actionText successfully! ${_rating.round()} stars'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          widget.onRatingSubmitted?.call();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${_isUpdating ? 'update' : 'submit'} rating: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
}

/// Helper function to show rating dialog
Future<void> showRatingDialog({
  required BuildContext context,
  required String pickupId,
  required String ratingType,
  String? ratedUserId,
  String? ratedUserName,
  VoidCallback? onRatingSubmitted,
  bool allowUpdate = false,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return RatingDialog(
        pickupId: pickupId,
        ratingType: ratingType,
        ratedUserId: ratedUserId,
        ratedUserName: ratedUserName,
        onRatingSubmitted: onRatingSubmitted,
        allowUpdate: allowUpdate,
      );
    },
  );
}
