import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/invitation_provider.dart';
import '../../../core/services/se_session_service.dart';
import '../../../shared/models/chat.dart';
import '../../chat/screens/chat_screen.dart';

class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key});

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Force refresh invitations when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InvitationProvider>().refreshInvitations();
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
            // Show error message if any
            Consumer<InvitationProvider>(
              builder: (context, invitationProvider, child) {
                if (invitationProvider.error != null) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    margin: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: Colors.red[600], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            invitationProvider.error!,
                            style: TextStyle(
                              color: Colors.red[700],
                              fontSize: 14,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => invitationProvider.clearError(),
                          child: Icon(Icons.close,
                              color: Colors.red[600], size: 20),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.people,
                      color: Color(0xFFFF6B35),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Invitations',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.share,
                      color: Colors.grey,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.add,
                      color: Colors.grey,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),

            // Tab Bar
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFFFF6B35),
                labelColor: const Color(0xFFFF6B35),
                unselectedLabelColor: Colors.grey[600],
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                indicator: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: const Color(0xFFFF6B35),
                      width: 3,
                    ),
                  ),
                ),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inbox, size: 20),
                        const SizedBox(width: 8),
                        const Text('Received'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.send, size: 20),
                        const SizedBox(width: 8),
                        const Text('Sent'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Tab Bar View
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildReceivedInvitations(),
                  _buildSentInvitations(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceivedInvitations() {
    return Consumer<InvitationProvider>(
      builder: (context, invitationProvider, child) {
        if (invitationProvider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFFFF6B35),
            ),
          );
        }

        final receivedInvitations = invitationProvider.receivedInvitations;

        if (receivedInvitations.isEmpty) {
          return _buildEmptyState(
            icon: Icons.inbox,
            title: 'No received invitations',
            subtitle:
                'When someone sends you an invitation,\nit will appear here.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: receivedInvitations.length,
          itemBuilder: (context, index) {
            final invitation = receivedInvitations[index];
            return _buildInvitationCard(invitation, true);
          },
        );
      },
    );
  }

  Widget _buildSentInvitations() {
    return Consumer<InvitationProvider>(
      builder: (context, invitationProvider, child) {
        print(
            '📱 InvitationsScreen: Consumer triggered - isLoading: ${invitationProvider.isLoading}');

        if (invitationProvider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFFFF6B35),
            ),
          );
        }

        final sentInvitations = invitationProvider.sentInvitations;
        print(
            '📱 InvitationsScreen: Sent invitations count: ${sentInvitations.length}');
        print(
            '📱 InvitationsScreen: All invitations count: ${invitationProvider.invitations.length}');
        print(
            '📱 InvitationsScreen: Current session ID: ${SeSessionService().currentSessionId}');

        // Debug: Print all invitations to see what's in the list
        for (int i = 0; i < invitationProvider.invitations.length; i++) {
          final inv = invitationProvider.invitations[i];
          print(
              '📱 InvitationsScreen: Invitation $i: fromUserId=${inv.fromUserId}, toUserId=${inv.toUserId}, status=${inv.status}');
        }

        if (sentInvitations.isEmpty) {
          return _buildEmptyState(
            icon: Icons.send,
            title: 'No sent invitations',
            subtitle: 'Invitations you send will appear here.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: sentInvitations.length,
          itemBuilder: (context, index) {
            final invitation = sentInvitations[index];
            print(
                '📱 InvitationsScreen: Building sent invitation card: ${invitation.id}');
            return _buildInvitationCard(invitation, false);
          },
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(40),
              ),
              child: Icon(
                icon,
                size: 40,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvitationCard(dynamic invitation, bool isReceived) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isReceived
                ? Colors.blue.withValues(alpha: 0.1)
                : Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isReceived ? Icons.inbox : Icons.send,
            color: isReceived ? Colors.blue : Colors.orange,
            size: 20,
          ),
        ),
        title: Text(
          isReceived ? invitation.fromUsername : invitation.toUsername,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          isReceived ? invitation.fromUserId : invitation.toUserId,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
        trailing: _buildInvitationStatusWidget(invitation, isReceived),
      ),
    );
  }

  Widget _buildInvitationStatusWidget(dynamic invitation, bool isReceived) {
    final status =
        invitation.status.toString().split('.').last; // Convert enum to string

    if (isReceived) {
      // Received invitations - show accept/decline buttons for pending
      if (status == 'pending') {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => _acceptInvitation(invitation),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.green,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _declineInvitation(invitation),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.red,
                  size: 20,
                ),
              ),
            ),
          ],
        );
      } else {
        // Show status badge for non-pending received invitations
        return _buildStatusBadge(status);
      }
    } else {
      // Sent invitations - show status and actions
      if (status == 'pending') {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Delete button above status
            GestureDetector(
              onTap: () => _deleteInvitation(invitation),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.delete,
                  color: Colors.red,
                  size: 16,
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Pending status below
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Pending',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      } else if (status == 'accepted') {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Accepted status above
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 20,
              ),
            ),
            const SizedBox(height: 4),
            // Chat button below
            GestureDetector(
              onTap: () => _openChat(invitation),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.chat,
                  color: Color(0xFFFF6B35),
                  size: 20,
                ),
              ),
            ),
          ],
        );
      } else if (status == 'declined') {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.cancel,
                color: Colors.red,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _resendInvitation(invitation),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.refresh,
                  color: Color(0xFFFF6B35),
                  size: 20,
                ),
              ),
            ),
          ],
        );
      } else {
        return _buildStatusBadge(status);
      }
    }
  }

  Widget _buildStatusBadge(String status) {
    Color badgeColor;
    Color textColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case 'accepted':
        badgeColor = Colors.green.withValues(alpha: 0.1);
        textColor = Colors.green;
        statusText = 'Accepted';
        statusIcon = Icons.check_circle;
        break;
      case 'declined':
        badgeColor = Colors.red.withValues(alpha: 0.1);
        textColor = Colors.red;
        statusText = 'Declined';
        statusIcon = Icons.cancel;
        break;
      case 'cancelled':
        badgeColor = Colors.grey.withValues(alpha: 0.1);
        textColor = Colors.grey[600]!;
        statusText = 'Cancelled';
        statusIcon = Icons.block;
        break;
      default:
        badgeColor = Colors.grey.withValues(alpha: 0.1);
        textColor = Colors.grey[600]!;
        statusText = 'Unknown';
        statusIcon = Icons.help;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, color: textColor, size: 16),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _acceptInvitation(dynamic invitation) async {
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Accepting invitation...'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );

      // Call the InvitationProvider to accept the invitation
      final invitationProvider = context.read<InvitationProvider>();
      final success = await invitationProvider.acceptInvitation(invitation.id);

      if (context.mounted) {
        if (success) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Accepted invitation from ${invitation.fromUsername}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          // Show error message
          final errorMessage =
              invitationProvider.error ?? 'Failed to accept invitation';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
          // Clear the error after showing it
          invitationProvider.clearError();
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accepting invitation: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _declineInvitation(dynamic invitation) async {
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Declining invitation...'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );

      // Call the InvitationProvider to decline the invitation
      final invitationProvider = context.read<InvitationProvider>();
      final success = await invitationProvider.declineInvitation(invitation.id);

      if (context.mounted) {
        if (success) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Declined invitation from ${invitation.fromUsername}'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          // Show error message
          final errorMessage =
              invitationProvider.error ?? 'Failed to decline invitation';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
          // Clear the error after showing it
          invitationProvider.clearError();
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error declining invitation: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _openChat(dynamic invitation) async {
    // Find the chat for this accepted invitation
    final invitationProvider = context.read<InvitationProvider>();
    final chats = await invitationProvider.getChats();

    // Look for a chat between these two users
    Chat? foundChat;
    try {
      foundChat = chats.firstWhere(
        (chat) =>
            (chat.user1Id == invitation.fromUserId &&
                chat.user2Id == invitation.toUserId) ||
            (chat.user1Id == invitation.toUserId &&
                chat.user2Id == invitation.fromUserId),
      );
    } catch (e) {
      foundChat = null;
    }

    if (foundChat != null) {
      // Navigate to chat screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChatScreen(chat: foundChat!),
        ),
      );
    } else {
      // Show error if chat not found
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chat not found for ${invitation.toUsername}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _deleteInvitation(dynamic invitation) async {
    try {
      // Show confirmation action sheet
      final shouldDelete = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              // Title
              const Text(
                'Delete Invitation',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              // Message
              Text(
                'Are you sure you want to delete the invitation to ${invitation.toUsername}?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 30),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      );

      if (shouldDelete == true) {
        // Show loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deleting invitation...'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );

        // Call the InvitationProvider to delete the invitation
        final invitationProvider = context.read<InvitationProvider>();
        final success =
            await invitationProvider.deleteInvitation(invitation.id);

        if (context.mounted) {
          if (success) {
            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Invitation to ${invitation.toUsername} deleted'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          } else {
            // Show error message
            final errorMessage =
                invitationProvider.error ?? 'Failed to delete invitation';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
            // Clear the error after showing it
            invitationProvider.clearError();
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting invitation: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _resendInvitation(dynamic invitation) async {
    try {
      // Show confirmation dialog
      final shouldResend = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Resend Invitation',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to resend the invitation to ${invitation.toUsername}?',
            style: const TextStyle(color: Colors.black),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                'Resend',
                style: TextStyle(color: Color(0xFFFF6B35)),
              ),
            ),
          ],
        ),
      );

      if (shouldResend == true) {
        // Show loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resending invitation...'),
            backgroundColor: const Color(0xFFFF6B35),
            duration: Duration(seconds: 2),
          ),
        );

        // Call the InvitationProvider to resend the invitation
        final invitationProvider = context.read<InvitationProvider>();
        final success =
            await invitationProvider.resendInvitation(invitation.id);

        if (context.mounted) {
          if (success) {
            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Invitation to ${invitation.toUsername} resent'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          } else {
            // Show error message
            final errorMessage =
                invitationProvider.error ?? 'Failed to resend invitation';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
            // Clear the error after showing it
            invitationProvider.clearError();
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error resending invitation: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}
