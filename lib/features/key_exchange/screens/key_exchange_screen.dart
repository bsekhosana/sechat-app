import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sechat_app/shared/widgets/connection_status_widget.dart';
import '../../../shared/models/key_exchange_request.dart';
import '../providers/key_exchange_request_provider.dart';
import '../../../shared/widgets/custom_elevated_button.dart';
import '../../../core/services/indicator_service.dart';

class KeyExchangeScreen extends StatefulWidget {
  const KeyExchangeScreen({super.key});

  @override
  State<KeyExchangeScreen> createState() => _KeyExchangeScreenState();
}

class _KeyExchangeScreenState extends State<KeyExchangeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Refresh the key exchange data when screen is loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Refresh the key exchange data
      final provider = context.read<KeyExchangeRequestProvider>();
      provider.refresh();

      // Update badge count to reflect current state
      final indicatorService = IndicatorService();
      final pendingCount = provider.receivedRequests
          .where((req) => req.status == 'received' || req.status == 'pending')
          .length;
      indicatorService.updateCountsWithContext(
          pendingKeyExchange: pendingCount);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();

    // Reset screen context when leaving the key exchange screen
    // This allows badge updates to resume when the user is not on this screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final indicatorService = IndicatorService();
        indicatorService.setScreenContext(isOnKeyExchangeScreen: false);
        print(
            '🔑 KeyExchangeScreen: ✅ Screen context reset - badge updates will resume');
      } catch (e) {
        print('🔑 KeyExchangeScreen: ❌ Error resetting screen context: $e');
      }
    });

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Connection Status
            const ConnectionStatusWidget(),

            // Tab Bar
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFFFF6B35),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFFFF6B35),
              tabs: const [
                Tab(text: 'Received'),
                Tab(text: 'Sent'),
              ],
            ),
            SizedBox(height: 20),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildReceivedTab(),
                  _buildSentTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceivedTab() {
    return Consumer<KeyExchangeRequestProvider>(
      builder: (context, provider, child) {
        final receivedRequests = provider.receivedRequests;
        print(
            '🔑 KeyExchangeScreen: 🔄 Consumer rebuild - received requests count: ${receivedRequests.length}');

        if (receivedRequests.isEmpty) {
          return _buildEmptyState(
            'No Key Exchange Requests',
            'You haven\'t received any key exchange requests yet.',
            Icons.key,
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: receivedRequests.length,
          itemBuilder: (context, index) {
            final request = receivedRequests[index];
            return _buildRequestCard(request, isReceived: true);
          },
        );
      },
    );
  }

  Widget _buildSentTab() {
    return Consumer<KeyExchangeRequestProvider>(
      builder: (context, provider, child) {
        final sentRequests = provider.sentRequests;

        if (sentRequests.isEmpty) {
          return _buildEmptyState(
            'No Sent Requests',
            'You haven\'t sent any key exchange requests yet.',
            Icons.send,
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: sentRequests.length,
          itemBuilder: (context, index) {
            final request = sentRequests[index];
            return _buildRequestCard(request, isReceived: false);
          },
        );
      },
    );
  }

  Widget _buildRequestCard(KeyExchangeRequest request,
      {required bool isReceived}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Center(
                    child: Icon(
                      isReceived ? Icons.key : Icons.send,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isReceived
                            ? 'From: ${request.displayName ?? '${request.fromSessionId}'}'
                            : 'To: ${request.displayName ?? '${request.toSessionId}'}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        request.requestPhrase,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        _getStatusColor(request.status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    request.statusDisplayText,
                    style: TextStyle(
                      color: _getStatusColor(request.status),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Requested: ${_formatTimestamp(request.timestamp)}',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
            if (request.respondedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Responded: ${_formatTimestamp(request.respondedAt!)}',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
              ),
            ],
            if (isReceived &&
                (request.isReceived ||
                    request.status == 'processing' ||
                    request.status == 'failed')) ...[
              const SizedBox(height: 16),
              _buildActionButtons(request),
            ],
            // Add resend button for sent requests that are not accepted
            if (!isReceived && request.status != 'accepted') ...[
              const SizedBox(height: 16),
              _buildResendButton(request),
            ],
            // Add delete button based on request status and type
            if (_shouldShowDeleteButton(request, isReceived)) ...[
              const SizedBox(height: 16),
              _buildDeleteButton(request, isReceived),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'received':
        return Colors.blue;
      case 'accepted':
        return Colors.green;
      case 'declined':
        return Colors.red;
      case 'failed':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  Widget _buildActionButtons(KeyExchangeRequest request) {
    final isProcessing = request.status == 'processing';
    final isFailed = request.status == 'failed';

    return Row(
      children: [
        Expanded(
          child: CustomElevatedButton(
            text: isProcessing ? 'Processing...' : 'Accept',
            icon: Icons.check,
            onPressed: isProcessing ? () {} : () => _acceptRequest(request),
            isPrimary: true,
            isLoading: isProcessing,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: CustomElevatedButton(
            text: isFailed ? 'Retry' : 'Decline',
            icon: isFailed ? Icons.refresh : Icons.close,
            onPressed: isFailed
                ? () => _retryRequest(request.id)
                : (isProcessing ? () {} : () => _declineRequest(request.id)),
            isPrimary: false,
            isLoading: false,
          ),
        ),
      ],
    );
  }

  Widget _buildResendButton(KeyExchangeRequest request) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _resendRequest(request.id),
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: const Text(
              'Resend Request',
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _acceptRequest(KeyExchangeRequest request) async {
    try {
      final provider = context.read<KeyExchangeRequestProvider>();
      final success = await provider.acceptKeyExchangeRequest(request, context);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Key exchange request accepted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to accept key exchange request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _declineRequest(String requestId) async {
    try {
      final provider = context.read<KeyExchangeRequestProvider>();
      final success = await provider.declineKeyExchangeRequest(requestId);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Key exchange request declined'),
            backgroundColor: Colors.orange,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to decline key exchange request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _retryRequest(String requestId) async {
    try {
      final provider = context.read<KeyExchangeRequestProvider>();
      final success = await provider.retryKeyExchangeRequest(requestId);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Key exchange request retried successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to retry key exchange request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _resendRequest(String requestId) async {
    try {
      final provider = context.read<KeyExchangeRequestProvider>();
      final success = await provider.resendKeyExchangeRequest(requestId);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Key exchange request resent successfully'),
            backgroundColor: Colors.blue,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to resend key exchange request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Check if delete button should be shown based on request status and type
  bool _shouldShowDeleteButton(KeyExchangeRequest request, bool isReceived) {
    if (isReceived) {
      // Recipients can only delete requests that are still pending (received status)
      return request.status == 'received';
    } else {
      // Senders can only delete/revoke requests that haven't been responded to
      return request.status == 'pending' || request.status == 'sent';
    }
  }

  Widget _buildDeleteButton(KeyExchangeRequest request, bool isReceived) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _showDeleteConfirmation(request, isReceived),
            icon: const Icon(Icons.delete, color: Colors.white),
            label: Text(
              isReceived ? 'Delete Request' : 'Revoke Request',
              style: const TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showDeleteConfirmation(KeyExchangeRequest request, bool isReceived) {
    final title = isReceived ? 'Delete Request' : 'Revoke Request';
    final message = isReceived
        ? 'Are you sure you want to delete this key exchange request? This action cannot be undone.'
        : 'Are you sure you want to revoke this key exchange request? The recipient will no longer be able to accept it.';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteRequest(request, isReceived);
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: Text(isReceived ? 'Delete' : 'Revoke'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteRequest(
      KeyExchangeRequest request, bool isReceived) async {
    try {
      final provider = context.read<KeyExchangeRequestProvider>();
      bool success;

      if (isReceived) {
        success = await provider.deleteReceivedRequest(request.id);
      } else {
        success = await provider.deleteSentRequest(request.id);
      }

      if (success && mounted) {
        final actionText = isReceived ? 'deleted' : 'revoked';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Key exchange request $actionText successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        final actionText = isReceived ? 'delete' : 'revoke';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to $actionText key exchange request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final actionText = isReceived ? 'delete' : 'revoke';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
