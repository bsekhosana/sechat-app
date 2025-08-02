import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../providers/invitation_provider.dart';
import '../../../core/services/se_session_service.dart';
import '../../../core/services/se_shared_preference_service.dart';
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
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double height = MediaQuery.of(context).size.height;
    double width = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize:
            Size(width, height * 0.05), // Fixed height for consistent layout
        child: Container(
          color: Colors.white,
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.only(left: 25, right: 25),
          child: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFFFF6B35),
            labelColor: const Color(0xFFFF6B35),
            unselectedLabelColor: Colors.grey,
            indicatorWeight: 2,
            labelStyle: TextStyle(
              fontSize: width * 0.04,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: TextStyle(
              fontSize: width * 0.04,
              fontWeight: FontWeight.w400,
            ),
            indicator: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Color(0xFFFF6B35),
                  width: width * 0.003,
                ),
              ),
            ),
            // Ensure tabs are evenly distributed
            labelPadding: EdgeInsets.symmetric(horizontal: width * 0.02),
            tabs: [
              Tab(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FaIcon(
                      FontAwesomeIcons.inbox,
                      size: width * 0.04,
                    ),
                    SizedBox(height: height * 0.005),
                    Text(
                      'Received',
                      style: TextStyle(fontSize: width * 0.03),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              Tab(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FaIcon(
                      FontAwesomeIcons.paperPlane,
                      size: width * 0.04,
                    ),
                    SizedBox(height: height * 0.005),
                    Text(
                      'Sent',
                      style: TextStyle(fontSize: width * 0.03),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ReceivedInvitationsTab(),
          _SentInvitationsTab(),
        ],
      ),
    );
  }
}

class _ReceivedInvitationsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FaIcon(
                  FontAwesomeIcons.inbox,
                  size: 64,
                  color: Colors.grey,
                ),
                SizedBox(height: 16),
                Text(
                  'No received invitations',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'When someone sends you an invitation,\nit will appear here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 20),
          itemCount: receivedInvitations.length,
          itemBuilder: (context, index) {
            final invitation = receivedInvitations[index];
            return _InvitationCard(
              invitation: invitation,
              isReceived: true,
            );
          },
        );
      },
    );
  }
}

class _SentInvitationsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<InvitationProvider>(
      builder: (context, invitationProvider, child) {
        if (invitationProvider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFFFF6B35),
            ),
          );
        }

        final sentInvitations = invitationProvider.sentInvitations;

        if (sentInvitations.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FaIcon(
                  FontAwesomeIcons.paperPlane,
                  size: 64,
                  color: Colors.grey,
                ),
                SizedBox(height: 16),
                Text(
                  'No sent invitations',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Invitations you send will appear here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 0),
          itemCount: sentInvitations.length,
          itemBuilder: (context, index) {
            final invitation = sentInvitations[index];
            return _InvitationCard(
              invitation: invitation,
              isReceived: false,
            );
          },
        );
      },
    );
  }
}

class _InvitationCard extends StatelessWidget {
  final Invitation invitation;
  final bool isReceived;

  const _InvitationCard({
    required this.invitation,
    required this.isReceived,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFFF6B35),
                  child: Text(
                    (isReceived
                            ? invitation.fromUsername
                            : invitation.toUsername)
                        .substring(0, 1)
                        .toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
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
                        isReceived
                            ? invitation.fromUsername
                            : invitation.toUsername,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _getStatusText(invitation.status),
                        style: TextStyle(
                          color: _getStatusColor(invitation.status),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    _buildActionButtons(context),
                    if (invitation.status == InvitationStatus.accepted)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        child: GestureDetector(
                          onTap: () => _chat(context),
                          child: Icon(
                            Icons.chat_bubble_outline,
                            color: const Color(0xFFFF6B35),
                            size: 20,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _getInvitationMessage(invitation.status),
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sent ${_formatDate(invitation.createdAt)}',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    if (invitation.status != InvitationStatus.pending) {
      // Show status indicator for non-pending invitations
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _getStatusColor(invitation.status).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _getStatusColor(invitation.status),
            width: 1,
          ),
        ),
        child: Text(
          _getStatusText(invitation.status),
          style: TextStyle(
            color: _getStatusColor(invitation.status),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (isReceived) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => _acceptInvitation(context),
            icon: const Icon(
              Icons.check,
              color: Colors.green,
            ),
            tooltip: 'Accept',
          ),
          IconButton(
            onPressed: () => _declineInvitation(context),
            icon: const Icon(
              Icons.close,
              color: Colors.red,
            ),
            tooltip: 'Decline',
          ),
        ],
      );
    } else {
      return IconButton(
        onPressed: () => _cancelInvitation(context),
        icon: const Icon(
          Icons.cancel,
          color: Colors.orange,
        ),
        tooltip: 'Cancel',
      );
    }
  }

  String _getStatusText(InvitationStatus status) {
    switch (status) {
      case InvitationStatus.pending:
        return 'Pending';
      case InvitationStatus.accepted:
        return 'Accepted';
      case InvitationStatus.declined:
        return 'Declined';
      case InvitationStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color _getStatusColor(InvitationStatus status) {
    switch (status) {
      case InvitationStatus.pending:
        return Colors.orange;
      case InvitationStatus.accepted:
        return Colors.green;
      case InvitationStatus.declined:
        return Colors.red;
      case InvitationStatus.cancelled:
        return Colors.grey;
    }
  }

  String _getInvitationMessage(InvitationStatus status) {
    // if invitatoin accepted show invitattion accepted instead of wants to connect with you
    if (isReceived) {
      if (status == InvitationStatus.accepted) {
        return 'You accepted ${invitation.fromUsername}\'s invitation';
      } else {
        return '${invitation.fromUsername} wants to connect with you';
      }
    } else {
      if (status == InvitationStatus.accepted) {
        return 'You accepted ${invitation.toUsername}\'s invitation';
      } else {
        return 'You invited ${invitation.toUsername} to connect';
      }
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes} minutes ago';
      }
      return '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Future<void> _acceptInvitation(BuildContext context) async {
    final invitationProvider = context.read<InvitationProvider>();
    final success = await invitationProvider.acceptInvitation(invitation.id);

    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invitation accepted!'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(invitationProvider.error ?? 'Failed to accept invitation'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _declineInvitation(BuildContext context) async {
    final invitationProvider = context.read<InvitationProvider>();
    final success = await invitationProvider.declineInvitation(invitation.id);

    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invitation declined'),
          backgroundColor: Colors.orange,
        ),
      );
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(invitationProvider.error ?? 'Failed to decline invitation'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _cancelInvitation(BuildContext context) async {
    final invitationProvider = context.read<InvitationProvider>();
    final success = await invitationProvider.cancelInvitation(invitation.id);

    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invitation cancelled'),
          backgroundColor: Colors.orange,
        ),
      );
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(invitationProvider.error ?? 'Failed to cancel invitation'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _chat(BuildContext context) async {
    try {
      // Find the chat that corresponds to this accepted invitation
      final prefsService = SeSharedPreferenceService();
      final chatsJson = await prefsService.getJsonList('chats') ?? [];

      // Find chat with matching participants
      Chat? targetChat;
      for (final chatJson in chatsJson) {
        try {
          final chat = Chat.fromJson(chatJson);
          final currentUserId = SeSessionService().currentSessionId ?? '';

          // Check if this chat involves the same users as the invitation
          if (isReceived) {
            // For received invitations, check if chat involves fromUserId and current user
            if (chat.user1Id == invitation.fromUserId &&
                    chat.user2Id == currentUserId ||
                chat.user1Id == currentUserId &&
                    chat.user2Id == invitation.fromUserId) {
              targetChat = chat;
              break;
            }
          } else {
            // For sent invitations, check if chat involves toUserId and current user
            if (chat.user1Id == invitation.toUserId &&
                    chat.user2Id == currentUserId ||
                chat.user1Id == currentUserId &&
                    chat.user2Id == invitation.toUserId) {
              targetChat = chat;
              break;
            }
          }
        } catch (e) {
          print('Error parsing chat: $e');
        }
      }

      if (targetChat != null && context.mounted) {
        // Navigate to the chat screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChatScreen(chat: targetChat!),
          ),
        );
      } else if (context.mounted) {
        // Show error if chat not found
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat not found. Please try again later.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Error navigating to chat: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening chat: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
