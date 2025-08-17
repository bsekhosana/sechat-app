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

    // Clear key exchange indicator when screen is loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      IndicatorService().clearKeyExchangeIndicator();

      // Refresh the key exchange data
      final provider = context.read<KeyExchangeRequestProvider>();
      provider.refresh();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
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
                            ? 'From: ${request.displayName ?? '${request.fromSessionId.substring(0, 8)}...'}'
                            : 'To: ${request.displayName ?? '${request.toSessionId.substring(0, 8)}...'}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        request.requestPhrase,
                        style: TextStyle(
                          fontSize: 14,
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
                    color: _getStatusColor(request.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    request.statusDisplayText,
                    style: TextStyle(
                      color: _getStatusColor(request.status),
                      fontSize: 10,
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
            onPressed: isProcessing ? () {} : () => _acceptRequest(request.id),
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

  Future<void> _acceptRequest(String requestId) async {
    try {
      final provider = context.read<KeyExchangeRequestProvider>();
      final success = await provider.acceptKeyExchangeRequest(requestId);

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
}
