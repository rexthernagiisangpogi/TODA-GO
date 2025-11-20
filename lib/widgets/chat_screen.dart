import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../services/chat_service.dart';
import '../services/unread_message_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatScreen extends StatefulWidget {
  final String pickupId;
  final String title;
  final String senderType; // 'driver' | 'passenger'

  const ChatScreen({
    super.key,
    required this.pickupId,
    required this.senderType,
    this.title = 'Chat',
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isRideCompleted = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _messagesSubscription;

  @override
  void initState() {
    super.initState();
    _checkRideStatus();
    _scrollToBottom();
    UnreadMessageService().markAsRead(widget.pickupId);
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    // Scroll to bottom after a short delay to ensure list is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _checkRideStatus() async {
    final pickupDoc = await FirebaseFirestore.instance
        .collection('pickups')
        .doc(widget.pickupId)
        .get();
    
    if (pickupDoc.exists) {
      final data = pickupDoc.data();
      final status = data?['status'] as String?;
      if (mounted) {
        setState(() {
          _isRideCompleted = status == 'completed';
        });
      }
    }
    
    // Listen for status changes
    FirebaseFirestore.instance
        .collection('pickups')
        .doc(widget.pickupId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data();
        final status = data?['status'] as String?;
        setState(() {
          _isRideCompleted = status == 'completed';
        });
      }
    });
  }

  Future<void> _send() async {
    if (_isRideCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ride completed. Chat is now read-only.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    // Clear input immediately for better UX
    _messageController.clear();
    
    try {
      await _chatService.sendMessage(
        pickupId: widget.pickupId,
        text: text,
        senderType: widget.senderType,
      );
      
      // Scroll to bottom after sending
      await Future.delayed(const Duration(milliseconds: 100));
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        // Restore message text
        _messageController.text = text;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFF082FBD),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _chatService.streamMessages(pickupId: widget.pickupId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF082FBD)),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading messages',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start the conversation!',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Auto-scroll to bottom when new messages arrive
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final text = (data['text'] ?? '').toString();
                    final senderId = (data['senderId'] ?? '').toString();
                    final senderType = (data['senderType'] ?? '').toString();
                    final timestamp = data['timestamp'] as Timestamp?;
                    final isMe = senderId == currentUserId;

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFF082FBD) : Colors.grey.shade200,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: Radius.circular(isMe ? 12 : 2),
                            bottomRight: Radius.circular(isMe ? 2 : 12),
                          ),
                          border: isMe ? null : Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMe)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  senderType.isEmpty ? 'Passenger' : _capitalize(senderType),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            Text(
                              text,
                              style: TextStyle(
                                color: isMe ? Colors.white : Colors.black87,
                                fontSize: 14,
                              ),
                            ),
                            if (timestamp != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _formatTime(timestamp.toDate()),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isMe ? Colors.white70 : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: _isRideCompleted
                  ? Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline, size: 18, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          Text(
                            'Ride completed. Chat is now read-only.',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: InputDecoration(
                              hintText: 'Type a message...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _send,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF082FBD),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text('Send'),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }
}
