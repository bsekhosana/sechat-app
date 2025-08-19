import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/se_socket_service.dart';
import '../../chat/providers/chat_list_provider.dart';
import '../../chat/models/chat_conversation.dart';

/// Queue Statistics screen for viewing and managing message queues
class QueueStatisticsScreen extends StatefulWidget {
  const QueueStatisticsScreen({super.key});

  @override
  State<QueueStatisticsScreen> createState() => _QueueStatisticsScreenState();
}

class _QueueStatisticsScreenState extends State<QueueStatisticsScreen> {
  Map<String, dynamic> _queueStats = {};
  List<Map<String, dynamic>> _queuedMessages = [];
  bool _isLoading = true;
  final SeSocketService _socketService = SeSocketService();

  @override
  void initState() {
    super.initState();
    _loadQueueStatistics();
    _setupQueueStatsListener();
  }

  void _setupQueueStatsListener() {
    // Listen for queue statistics responses
    _socketService.on('queue_statistics_response', (data) {
      if (mounted) {
        setState(() {
          _queueStats = Map<String, dynamic>.from(data);
        });
        print('🔌 QueueStats: Received queue statistics: $data');
      }
    });

    // Listen for queue status responses
    _socketService.on('queue_status_response', (data) {
      if (mounted) {
        print('🔌 QueueStats: Received queue status: $data');
        // Add to queued messages list if it has queued events
        final hasQueuedEvents = data['hasQueuedEvents'] as bool? ?? false;
        if (hasQueuedEvents) {
          final recipientId = data['recipientId'] as String? ?? '';
          final queuedEventCount = data['queuedEventCount'] as int? ?? 0;
          final lastQueuedAt = data['lastQueuedAt'] as String? ?? '';

          // Check if this conversation is already in the list
          final existingIndex = _queuedMessages.indexWhere(
            (msg) => msg['recipientId'] == recipientId,
          );

          if (existingIndex != -1) {
            // Update existing entry
            setState(() {
              _queuedMessages[existingIndex] = {
                'recipientId': recipientId,
                'eventCount': queuedEventCount,
                'lastQueuedAt': lastQueuedAt,
                'type': 'conversation',
              };
            });
          } else {
            // Add new entry
            setState(() {
              _queuedMessages.add({
                'recipientId': recipientId,
                'eventCount': queuedEventCount,
                'lastQueuedAt': lastQueuedAt,
                'type': 'conversation',
              });
            });
          }
        } else {
          // Remove from list if no queued events
          final recipientId = data['recipientId'] as String? ?? '';
          if (recipientId.isNotEmpty) {
            setState(() {
              _queuedMessages.removeWhere(
                (msg) => msg['recipientId'] == recipientId,
              );
            });
          }
        }
      }
    });

    // Listen for queue cleared events
    _socketService.on('queue_cleared', (data) {
      if (mounted) {
        final recipientId = data['recipientId'] as String? ?? '';
        if (recipientId.isNotEmpty) {
          setState(() {
            _queuedMessages.removeWhere(
              (msg) => msg['recipientId'] == recipientId,
            );
          });
          print('🔌 QueueStats: Queue cleared for $recipientId');
        }
      }
    });
  }

  Future<void> _loadQueueStatistics() async {
    try {
      setState(() {
        _isLoading = true;
        _queueStats = {};
        _queuedMessages = [];
      });

      // Request queue statistics from server
      await _socketService.getQueueStatistics();

      // Load conversations and check their queue status
      await _loadConversationQueueStatus();

      // Set loading to false after a delay to allow server responses
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('🔌 QueueStats: Error loading queue statistics: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadConversationQueueStatus() async {
    try {
      // Get conversations from the chat provider
      final chatListProvider =
          Provider.of<ChatListProvider>(context, listen: false);
      final conversations = chatListProvider.conversations;

      print(
          '🔌 QueueStats: Found ${conversations.length} conversations to check queue status');

      for (final conversation in conversations) {
        // Get the recipient ID (the other participant in the conversation)
        final currentUserId = _socketService.currentSessionId;
        final recipientId = conversation.participant1Id == currentUserId
            ? conversation.participant2Id
            : conversation.participant1Id;

        if (recipientId.isNotEmpty) {
          print(
              '🔌 QueueStats: Checking queue status for conversation with $recipientId');
          await _socketService.checkQueueStatus(recipientId);
        }
      }
    } catch (e) {
      print('🔌 QueueStats: Error loading conversation queue status: $e');
    }
  }

  Future<void> _clearAllQueues() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Clear All Queues',
          style: TextStyle(color: Colors.black),
        ),
        content: const Text(
          'This will permanently delete all queued messages and events. This action cannot be undone.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Clear All',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Emit clear all queues event
        _socketService.emit('clear_all_queues', {
          'sessionId': _socketService.currentSessionId,
          'timestamp': DateTime.now().toIso8601String(),
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All queues cleared successfully'),
            backgroundColor: Colors.green,
          ),
        );

        // Reload statistics
        _loadQueueStatistics();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing queues: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _clearConversationQueue(String recipientId) async {
    try {
      _socketService.emit('clear_conversation_queue', {
        'recipientId': recipientId,
        'sessionId': _socketService.currentSessionId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Queue cleared for conversation'),
          backgroundColor: Colors.green,
        ),
      );

      // Remove from local list
      setState(() {
        _queuedMessages.removeWhere((msg) => msg['recipientId'] == recipientId);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error clearing conversation queue: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showQueueDetails(Map<String, dynamic> message) {
    final recipientId = message['recipientId'] as String? ?? '';
    final eventCount = message['eventCount'] as int? ?? 0;
    final lastQueuedAt = message['lastQueuedAt'] as String? ?? '';

    // Get conversation display name
    String displayName = 'Unknown User';
    try {
      final chatListProvider =
          Provider.of<ChatListProvider>(context, listen: false);
      final conversation = chatListProvider.conversations.firstWhere(
        (conv) =>
            conv.participant1Id == recipientId ||
            conv.participant2Id == recipientId,
        orElse: () => ChatConversation(
          participant1Id: '',
          participant2Id: '',
        ),
      );

      if (conversation.id.isNotEmpty) {
        final currentUserId = _socketService.currentSessionId;
        displayName = conversation.getDisplayName(currentUserId ?? '');
      }
    } catch (e) {
      print('🔌 QueueStats: Error getting conversation name: $e');
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Queue Details for $displayName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Recipient ID', recipientId),
            _buildDetailRow('Display Name', displayName),
            _buildDetailRow('Queued Events', '$eventCount'),
            _buildDetailRow('Last Queued', _formatDateTime(lastQueuedAt)),
            _buildDetailRow('Queue Type', 'Conversation Messages'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return 'Unknown';
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Queue Statistics',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadQueueStatistics,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFFF6B35),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.queue,
                            color: const Color(0xFFFF6B35),
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Message Queue Statistics',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF6B35),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Overall Statistics
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Overall Statistics',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh, size: 20),
                                onPressed: _loadQueueStatistics,
                                tooltip: 'Refresh stats',
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildStatItem(
                            'Total Queued Events',
                            '${_queueStats['totalQueuedEvents'] ?? 0}',
                            Icons.inbox,
                          ),
                          _buildStatItem(
                            'Pending Deliveries',
                            '${_queueStats['pendingDeliveries'] ?? 0}',
                            Icons.pending,
                          ),
                          _buildStatItem(
                            'Successful Deliveries',
                            '${_queueStats['successfulDeliveries'] ?? 0}',
                            Icons.check_circle,
                          ),
                          _buildStatItem(
                            'Failed Deliveries',
                            '${_queueStats['failedDeliveries'] ?? 0}',
                            Icons.error,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Queued Conversations
                    if (_queuedMessages.isNotEmpty) ...[
                      const Text(
                        'Conversations with Queued Messages',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._queuedMessages
                          .map((message) => _buildQueuedMessageItem(message)),
                      const SizedBox(height: 24),
                    ],

                    // Action Buttons
                    if (_queuedMessages.isNotEmpty)
                      _buildActionButton(
                        'Clear All Queues',
                        'Delete all queued messages and events',
                        Icons.clear_all,
                        _clearAllQueues,
                        Colors.red,
                      ),

                    if (_queuedMessages.isEmpty && !_isLoading)
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No Queued Messages',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'All messages have been delivered successfully.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFFFF6B35),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueuedMessageItem(Map<String, dynamic> message) {
    final recipientId = message['recipientId'] as String? ?? '';
    final eventCount = message['eventCount'] as int? ?? 0;
    final lastQueuedAt = message['lastQueuedAt'] as String? ?? '';

    // Get conversation display name from chat provider
    String displayName = 'Unknown User';
    try {
      final chatListProvider =
          Provider.of<ChatListProvider>(context, listen: false);
      final conversation = chatListProvider.conversations.firstWhere(
        (conv) =>
            conv.participant1Id == recipientId ||
            conv.participant2Id == recipientId,
        orElse: () => ChatConversation(
          participant1Id: '',
          participant2Id: '',
        ),
      );

      if (conversation.id.isNotEmpty) {
        final currentUserId = _socketService.currentSessionId;
        displayName = conversation.getDisplayName(currentUserId ?? '');
      }
    } catch (e) {
      print('🔌 QueueStats: Error getting conversation name: $e');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.message,
              color: Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$eventCount queued events • ${_formatDateTime(lastQueuedAt)}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.info_outline, color: Colors.blue),
                onPressed: () => _showQueueDetails(message),
                tooltip: 'View details',
              ),
              IconButton(
                icon: const Icon(Icons.clear, color: Colors.red),
                onPressed: () => _clearConversationQueue(recipientId),
                tooltip: 'Clear queue',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
    Color color,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey[400],
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
