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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
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
        trailing: isReceived
            ? Row(
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
              )
            : Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Pending',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
      ),
    );
  }

  void _acceptInvitation(dynamic invitation) {
    // TODO: Implement accept invitation logic
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Accepted invitation from ${invitation.fromUsername}'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _declineInvitation(dynamic invitation) {
    // TODO: Implement decline invitation logic
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Declined invitation from ${invitation.fromUsername}'),
        backgroundColor: Colors.red,
      ),
    );
  }
}
