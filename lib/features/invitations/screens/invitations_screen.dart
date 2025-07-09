import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:share_plus/share_plus.dart';
import '../../../shared/providers/auth_provider.dart';
import '../providers/invitation_provider.dart';
import '../../../shared/models/invitation.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/profile_icon_widget.dart';

class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key});

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  int _tabIndex = 0; // 0 = Received, 1 = Sent

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InvitationProvider>().loadInvitations();
    });
  }

  void _shareApp() {
    const String shareText = '''
🔒 Join me on SeChat - Private & Secure Messaging! 

✨ Features:
• End-to-end encrypted conversations
• Anonymous messaging
• No personal data required
• Clean, modern interface

Download now and let's chat securely!

#SeChat #PrivateMessaging #Encrypted
    ''';

    Share.share(
      shareText,
      subject: 'Join me on SeChat - Secure Messaging App',
    );
  }

  void _acceptInvitation(Invitation invitation) async {
    final provider = context.read<InvitationProvider>();
    final success = await provider.acceptInvitation(invitation.id);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invitation accepted!'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Failed to accept invitation'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _declineInvitation(Invitation invitation) async {
    final provider = context.read<InvitationProvider>();
    final success = await provider.declineInvitation(invitation.id);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invitation declined'),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Failed to decline invitation'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _deleteInvitation(Invitation invitation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text(
          'Delete Invitation',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this invitation?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final provider = context.read<InvitationProvider>();
      final success = await provider.deleteInvitation(invitation.id);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invitation deleted'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.error ?? 'Failed to delete invitation'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFFF6B35);
      case 'accepted':
        return const Color(0xFF4CAF50);
      case 'declined':
        return const Color(0xFFFF5555);
      default:
        return const Color(0xFF666666);
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'declined':
        return 'Declined';
      default:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().currentUser;
    final userId = currentUser?.id;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _shareApp,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.share,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: SearchWidget(),
                  ),
                  const SizedBox(width: 12),
                  const ProfileIconWidget(),
                ],
              ),
            ),
            // Tabs
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF232323),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _buildTabButton('Received', 0),
                  _buildTabButton('Sent', 1),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Invitations list
            Expanded(
              child: Consumer<InvitationProvider>(
                builder: (context, invitationProvider, child) {
                  if (invitationProvider.isLoading) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF6B35),
                      ),
                    );
                  }
                  if (invitationProvider.error != null) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Color(0xFFFF6B35),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Error Loading Invitations',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            invitationProvider.error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              invitationProvider.clearError();
                              invitationProvider.loadInvitations();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6B35),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }
                  final invitations = invitationProvider.invitations;
                  List<Invitation> filtered;
                  if (_tabIndex == 0) {
                    // Received
                    filtered = invitations.where((i) => i.isReceived).toList();
                  } else {
                    // Sent
                    filtered = invitations.where((i) => !i.isReceived).toList();
                  }
                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _tabIndex == 0 ? Icons.mail_outline : Icons.send,
                            size: 64,
                            color: Color(0xFFFF6B35),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _tabIndex == 0
                                ? 'No Received Invitations'
                                : 'No Sent Invitations',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _tabIndex == 0
                                ? 'You haven\'t received any invitations yet'
                                : 'You haven\'t sent any invitations yet',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return AnimationLimiter(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final invitation = filtered[index];
                        // Get the other user (the user who is not the current user)
                        final otherUserId = invitation.otherUserId ??
                            (_tabIndex == 0
                                ? invitation.senderId
                                : invitation.recipientId);
                        final otherUser =
                            invitationProvider.getInvitationUser(otherUserId);

                        return AnimationConfiguration.staggeredList(
                          position: index,
                          duration: const Duration(milliseconds: 375),
                          child: SlideAnimation(
                            verticalOffset: 50.0,
                            child: FadeInAnimation(
                              child: _InvitationCard(
                                invitation: invitation,
                                otherUser: otherUser,
                                onAccept: _tabIndex == 0
                                    ? () => _acceptInvitation(invitation)
                                    : null,
                                onDecline: _tabIndex == 0
                                    ? () => _declineInvitation(invitation)
                                    : null,
                                onDelete: () => _deleteInvitation(invitation),
                                onChatTap: _tabIndex == 0
                                    ? () {
                                        // Navigate to chat for received invitations
                                        // You would typically pass the otherUserId to the chat screen
                                        // For now, we'll just show a snackbar
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'Chat not implemented yet'),
                                            backgroundColor: Color(0xFFFF6B35),
                                          ),
                                        );
                                      }
                                    : null,
                                formatTime: _formatTime,
                                getStatusColor: _getStatusColor,
                                getStatusText: _getStatusText,
                                isReceived: _tabIndex == 0,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final selected = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _tabIndex = index);
          // Mark invitations as read when switching tabs
          final invitationProvider = context.read<InvitationProvider>();
          if (index == 0) {
            // Received tab - mark received invitations as read
            invitationProvider.markReceivedInvitationsAsRead();
          } else {
            // Sent tab - mark sent invitations as read
            invitationProvider.markSentInvitationsAsRead();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFF6B35) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  final Invitation invitation;
  final User? otherUser;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback onDelete;
  final VoidCallback? onChatTap;
  final String Function(DateTime) formatTime;
  final Color Function(String) getStatusColor;
  final String Function(String) getStatusText;
  final bool isReceived;

  const _InvitationCard({
    required this.invitation,
    this.otherUser,
    this.onAccept,
    this.onDecline,
    required this.onDelete,
    this.onChatTap,
    required this.formatTime,
    required this.getStatusColor,
    required this.getStatusText,
    required this.isReceived,
  });

  @override
  Widget build(BuildContext context) {
    final isPendingCard = invitation.isPending();
    final cardBackgroundColor =
        isPendingCard ? const Color(0xFFFF6B35) : const Color(0xFF2C2C2C);
    final primaryTextColor = isPendingCard ? Colors.black : Colors.white;
    final secondaryTextColor = isPendingCard
        ? Colors.black.withOpacity(0.7)
        : Colors.white.withOpacity(0.7);
    final accentColor = isPendingCard ? Colors.black : const Color(0xFFFF6B35);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: accentColor,
                child: Text(
                  otherUser?.username.substring(0, 1).toUpperCase() ?? '?',
                  style: TextStyle(
                    color: isPendingCard ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      otherUser?.username ?? 'Unknown User',
                      style: TextStyle(
                        color: primaryTextColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      invitation.message,
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatTime(invitation.createdAt),
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isPendingCard
                          ? Colors.black.withOpacity(0.2)
                          : getStatusColor(invitation.status),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      getStatusText(invitation.status),
                      style: TextStyle(
                        color: isPendingCard ? Colors.black : Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (isReceived && invitation.isPending()) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDecline,
                  style: TextButton.styleFrom(
                    backgroundColor: isPendingCard
                        ? Colors.black.withOpacity(0.2)
                        : Colors.red.withOpacity(0.2),
                    foregroundColor: isPendingCard ? Colors.black : Colors.red,
                  ),
                  child: const Text('Decline'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isPendingCard ? Colors.black : const Color(0xFF4CAF50),
                    foregroundColor:
                        isPendingCard ? const Color(0xFFFF6B35) : Colors.white,
                  ),
                  child: const Text('Accept'),
                ),
              ],
            ),
          ] else if (invitation.isAccepted()) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(
                    backgroundColor: isPendingCard
                        ? Colors.black.withOpacity(0.2)
                        : Colors.red.withOpacity(0.2),
                    foregroundColor: isPendingCard ? Colors.black : Colors.red,
                  ),
                  child: const Text('Block'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: onChatTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isPendingCard ? Colors.black : const Color(0xFF4CAF50),
                    foregroundColor:
                        isPendingCard ? const Color(0xFFFF6B35) : Colors.white,
                  ),
                  icon: const Icon(Icons.chat, size: 16),
                  label: const Text('Chat'),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(
                    backgroundColor: isPendingCard
                        ? Colors.black.withOpacity(0.2)
                        : Colors.red.withOpacity(0.2),
                    foregroundColor: isPendingCard ? Colors.black : Colors.red,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
