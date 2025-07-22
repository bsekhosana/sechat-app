import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sechat_app/features/invitations/providers/invitation_provider.dart';
import 'package:sechat_app/shared/widgets/qr_scanner_widget.dart';
import 'package:sechat_app/shared/widgets/qr_generator_widget.dart';
import 'package:sechat_app/shared/widgets/contact_details_widget.dart';
import 'package:sechat_app/shared/providers/auth_provider.dart';
import 'package:sechat_app/core/services/session_service.dart';
import 'package:sechat_app/shared/widgets/invite_user_widget.dart';
import 'package:sechat_app/shared/widgets/profile_icon_widget.dart';
import 'package:sechat_app/shared/widgets/user_avatar.dart';
import 'package:sechat_app/shared/models/invitation.dart';
import 'package:sechat_app/shared/models/user.dart';
import '../../chat/screens/chat_screen.dart';
import '../../chat/providers/chat_provider.dart';
import '../../../shared/models/chat.dart';
import '../../../core/services/api_service.dart';

class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key});

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen>
    with WidgetsBindingObserver {
  late InvitationProvider _invitationProvider;
  int _tabIndex = 0; // 0 = Received, 1 = Sent
  List<String> _newInvitationIds = []; // Track new invitations for animation

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _invitationProvider = context.read<InvitationProvider>();
    // Mark as on invitations screen
    _invitationProvider.setOnInvitationsScreen(true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _invitationProvider.loadInvitations();
      _setupRealTimeUpdates();
    });
  }

  void _setupRealTimeUpdates() {
    // Listen to invitation provider changes for real-time updates
    _invitationProvider.addListener(_onInvitationProviderChanged);
  }

  void _onInvitationProviderChanged() {
    if (!mounted) return;

    // Check for new received invitations
    final receivedInvitations = _invitationProvider.invitations
        .where((invitation) =>
            invitation.isReceived && invitation.status == 'pending')
        .toList();

    // Find new invitations that weren't in our list before
    for (final invitation in receivedInvitations) {
      if (!_newInvitationIds.contains(invitation.id)) {
        _newInvitationIds.add(invitation.id);
        _showNewInvitationToast(invitation);

        // Remove from new list after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() {
              _newInvitationIds.remove(invitation.id);
            });
          }
        });
      }
    }
  }

  void _showNewInvitationToast(Invitation invitation) {
    // Get sender username
    final senderUsername =
        _invitationProvider.getInvitationUser(invitation.senderId)?.username ??
            'Someone';

    // Show toast message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.mail, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'New invitation from $senderUsername',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFFF6B35),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () {
            // Switch to received tab if not already there
            if (_tabIndex != 0) {
              setState(() {
                _tabIndex = 0;
              });
            }
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Remove listener to prevent memory leaks
    _invitationProvider.removeListener(_onInvitationProviderChanged);
    // Mark as not on invitations screen
    _invitationProvider.setOnInvitationsScreen(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      // Mark as not on invitations screen when app is paused
      _invitationProvider.setOnInvitationsScreen(false);
    } else if (state == AppLifecycleState.resumed) {
      // Mark as on invitations screen when app is resumed
      _invitationProvider.setOnInvitationsScreen(true);
    }
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
    final confirmed =
        await _showDeleteInvitationActionSheet(context, invitation);

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

  Future<bool?> _showDeleteInvitationActionSheet(
      BuildContext context, Invitation invitation) async {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF2C2C2C),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Delete Invitation',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Description
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Are you sure you want to delete this invitation?',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 16),

              // Action buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _blockUserFromInvitation(Invitation invitation) async {
    final otherUserId = invitation.senderId;
    final otherUser =
        context.read<InvitationProvider>().getInvitationUser(otherUserId);
    final username = otherUser?.username ?? 'Unknown User';

    final confirmed = await _showBlockUserActionSheet(context, username);

    if (confirmed == true) {
      try {
        final response = await ApiService.blockUser(otherUserId);
        if (response['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'User blocked successfully'),
              backgroundColor: Colors.red,
            ),
          );
          // Refresh invitations
          context.read<InvitationProvider>().loadInvitations();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Failed to block user'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error blocking user: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool?> _showBlockUserActionSheet(
      BuildContext context, String username) async {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF2C2C2C),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Block User',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Description
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Are you sure you want to block $username? This will remove all chats and messages between you and prevent future communication.',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 16),

              // Action buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Block'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
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
                    child: InviteUserWidget(),
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
                        final otherUserId = _tabIndex == 0
                            ? invitation.senderId
                            : invitation.recipientId;

                        // Use stored username from invitation if available, otherwise fall back to provider
                        final otherUser =
                            invitationProvider.getInvitationUser(otherUserId);
                        final storedUsername = _tabIndex == 0
                            ? invitation.senderUsername
                            : invitation.recipientUsername;

                        // Debug logging for sent invitations
                        if (_tabIndex == 1) {
                          print(
                              '📱 InvitationsScreen - Sent invitation debug:');
                          print(
                              '📱 InvitationsScreen - Invitation ID: ${invitation.id}');
                          print(
                              '📱 InvitationsScreen - Sender ID: ${invitation.senderId}');
                          print(
                              '📱 InvitationsScreen - Recipient ID: ${invitation.recipientId}');
                          print(
                              '📱 InvitationsScreen - Sender Username: ${invitation.senderUsername}');
                          print(
                              '📱 InvitationsScreen - Recipient Username: ${invitation.recipientUsername}');
                          print(
                              '📱 InvitationsScreen - Other User ID: $otherUserId');
                          print(
                              '📱 InvitationsScreen - Other User from provider: ${otherUser?.username}');
                          print(
                              '📱 InvitationsScreen - Stored Username: $storedUsername');
                        }

                        // Create a user object with stored username if available
                        final displayUser = storedUsername != null &&
                                storedUsername.isNotEmpty
                            ? otherUser?.copyWith(username: storedUsername) ??
                                User(
                                  id: otherUserId,
                                  deviceId: '',
                                  username: storedUsername,
                                  isOnline: false,
                                )
                            : otherUser;

                        final isNewInvitation =
                            _newInvitationIds.contains(invitation.id);

                        return AnimationConfiguration.staggeredList(
                          position: index,
                          duration: const Duration(milliseconds: 375),
                          child: SlideAnimation(
                            verticalOffset: 50.0,
                            child: FadeInAnimation(
                              child: _InvitationCard(
                                invitation: invitation,
                                otherUser: displayUser,
                                onAccept: _tabIndex == 0
                                    ? () => _acceptInvitation(invitation)
                                    : null,
                                onDecline: _tabIndex == 0
                                    ? () => _declineInvitation(invitation)
                                    : null,
                                onDelete: _tabIndex == 0
                                    ? () => _blockUserFromInvitation(invitation)
                                    : () => _deleteInvitation(invitation),
                                onChatTap: invitation.isAccepted()
                                    ? () {
                                        // Navigate to chat for accepted invitations
                                        // Find the chat for this accepted invitation
                                        final chatProvider =
                                            context.read<ChatProvider>();
                                        final currentUser = context
                                            .read<AuthProvider>()
                                            .currentUser;

                                        if (currentUser != null) {
                                          // Find the chat with the other user
                                          final otherUserId =
                                              invitation.senderId ==
                                                      currentUser.id
                                                  ? invitation.recipientId
                                                  : invitation.senderId;

                                          final chat =
                                              chatProvider.chats.firstWhere(
                                            (c) =>
                                                c.getOtherUserId(
                                                    currentUser.id) ==
                                                otherUserId,
                                            orElse: () => Chat(
                                              id: invitation
                                                  .id, // Use invitation ID as temporary chat ID
                                              user1Id: currentUser.id,
                                              user2Id: otherUserId,
                                              lastMessageAt:
                                                  invitation.acceptedAt,
                                              createdAt:
                                                  invitation.acceptedAt ??
                                                      DateTime.now(),
                                              updatedAt:
                                                  invitation.acceptedAt ??
                                                      DateTime.now(),
                                            ),
                                          );

                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  ChatScreen(chat: chat),
                                            ),
                                          );
                                        }
                                      }
                                    : null,
                                formatTime: _formatTime,
                                getStatusColor: _getStatusColor,
                                getStatusText: _getStatusText,
                                isReceived: _tabIndex == 0,
                                deleteButtonText:
                                    _tabIndex == 0 ? 'Block' : 'Delete',
                                isNewInvitation: isNewInvitation,
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

class _InvitationCard extends StatefulWidget {
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
  final String deleteButtonText;
  final bool isNewInvitation;

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
    required this.deleteButtonText,
    required this.isNewInvitation,
  });

  @override
  State<_InvitationCard> createState() => _InvitationCardState();
}

class _InvitationCardState extends State<_InvitationCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<Color?> _borderAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.02,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _borderAnimation = ColorTween(
      begin: const Color(0xFFFF6B35),
      end: Colors.transparent,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    // Start animation if this is a new invitation
    if (widget.isNewInvitation) {
      _animationController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPendingCard = widget.invitation.isPending();
    final cardBackgroundColor =
        isPendingCard ? const Color(0xFFFF6B35) : const Color(0xFF2C2C2C);
    final primaryTextColor = isPendingCard ? Colors.black : Colors.white;
    final secondaryTextColor = isPendingCard
        ? Colors.black.withOpacity(0.7)
        : Colors.white.withOpacity(0.7);
    final accentColor = isPendingCard ? Colors.black : const Color(0xFFFF6B35);

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBackgroundColor,
              borderRadius: BorderRadius.circular(16),
              border: widget.isNewInvitation
                  ? Border.all(
                      color: _borderAnimation.value ?? Colors.transparent,
                      width: 2,
                    )
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    UserAvatar(
                      displayName: widget.otherUser?.username,
                      sessionId: widget.otherUser?.id,
                      radius: 20,
                      backgroundColor: accentColor,
                      textColor: isPendingCard ? Colors.white : Colors.black,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.otherUser?.username ?? 'Unknown User',
                            style: TextStyle(
                              color: primaryTextColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.invitation.message,
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
                          widget.formatTime(widget.invitation.createdAt),
                          style: TextStyle(
                            color: secondaryTextColor,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isPendingCard
                                ? Colors.black.withOpacity(0.2)
                                : widget
                                    .getStatusColor(widget.invitation.status),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.getStatusText(widget.invitation.status),
                            style: TextStyle(
                              color:
                                  isPendingCard ? Colors.black : Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (widget.isReceived && widget.invitation.isPending()) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: widget.onDecline,
                        style: TextButton.styleFrom(
                          backgroundColor: isPendingCard
                              ? Colors.black.withOpacity(0.2)
                              : Colors.red.withOpacity(0.2),
                          foregroundColor:
                              isPendingCard ? Colors.black : Colors.red,
                        ),
                        child: const Text('Decline'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: widget.onAccept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isPendingCard
                              ? Colors.black
                              : const Color(0xFF4CAF50),
                          foregroundColor: isPendingCard
                              ? const Color(0xFFFF6B35)
                              : Colors.white,
                        ),
                        child: const Text('Accept'),
                      ),
                    ],
                  ),
                ] else if (widget.invitation.isAccepted()) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: widget.onDelete,
                        style: TextButton.styleFrom(
                          backgroundColor: isPendingCard
                              ? Colors.black.withOpacity(0.2)
                              : Colors.red.withOpacity(0.2),
                          foregroundColor:
                              isPendingCard ? Colors.black : Colors.red,
                        ),
                        child: const Text('Block'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: widget.onChatTap,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isPendingCard
                              ? Colors.black
                              : const Color(0xFF4CAF50),
                          foregroundColor: isPendingCard
                              ? const Color(0xFFFF6B35)
                              : Colors.white,
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
                        onPressed: widget.onDelete,
                        style: TextButton.styleFrom(
                          backgroundColor: isPendingCard
                              ? Colors.black.withOpacity(0.2)
                              : Colors.red.withOpacity(0.2),
                          foregroundColor:
                              isPendingCard ? Colors.black : Colors.red,
                        ),
                        child: Text(widget.deleteButtonText),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
