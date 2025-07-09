import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/providers/auth_provider.dart';
import '../providers/search_provider.dart';
import '../../../shared/models/user.dart';
import '../../invitations/providers/invitation_provider.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _debouncer = Debouncer(milliseconds: 500);
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeOverlay();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debouncer.run(() {
      context.read<SearchProvider>().searchUsers(query);
      _updateOverlay();
    });
  }

  void _inviteUser(User user) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: Text(
          'Send Invitation',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to send an invitation to ${user.username}?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B35),
              foregroundColor: Colors.white,
            ),
            child: const Text('Send'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final invitationProvider = context.read<InvitationProvider>();
      final success = await invitationProvider.sendInvitation(
        recipientId: user.id,
        message: 'Hi! I\'d like to chat with you on SeChat.',
      );

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invitation sent to ${user.username}!'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(invitationProvider.error ?? 'Failed to send invitation'),
            backgroundColor: Colors.red,
          ),
        );
      }
      _clearSearchAndOverlay();
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;
    _overlayEntry = OverlayEntry(
      builder: (context) {
        final searchProvider = context.read<SearchProvider>();
        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              // Background overlay that can be tapped to dismiss
              Positioned.fill(
                child: GestureDetector(
                  onTap: _clearSearchAndOverlay,
                  child: Container(color: Colors.transparent),
                ),
              ),
              // Search results container (not tappable to dismiss)
              Align(
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  onTap: () {}, // Prevents taps from propagating to background
                  child: Container(
                    margin: const EdgeInsets.only(top: 90),
                    width: MediaQuery.of(context).size.width * 0.8,
                    decoration: BoxDecoration(
                      color: const Color(0xFF232323),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 8),
                      itemCount: searchProvider.searchResults.length,
                      itemBuilder: (context, index) {
                        final user = searchProvider.searchResults[index];
                        final currentUser =
                            context.read<AuthProvider>().currentUser;
                        if (currentUser?.id == user.id) {
                          return const SizedBox.shrink();
                        }
                        return _UserCard(
                          user: user,
                          onInvite: () => _inviteUser(user),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _updateOverlay() {
    final searchProvider = context.read<SearchProvider>();
    final showResults = _searchController.text.isNotEmpty &&
        searchProvider.searchResults.isNotEmpty;
    if (showResults) {
      if (_overlayEntry == null) {
        _showOverlay();
      } else {
        _overlayEntry!.markNeedsBuild();
      }
    } else {
      _removeOverlay();
    }
  }

  void _clearSearchAndOverlay() {
    _searchController.clear();
    context.read<SearchProvider>().clearSearch();
    FocusScope.of(context).unfocus();
    _removeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Users'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by username...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearchAndOverlay,
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                filled: true,
                fillColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.3),
              ),
            ),
          ),
          // You can add more main content here if needed
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final User user;
  final VoidCallback onInvite;

  const _UserCard({required this.user, required this.onInvite});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            user.username.substring(0, 1).toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          user.username,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          user.isOnline ? 'Online' : 'Offline',
          style: TextStyle(
            color: user.isOnline
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
        ),
        trailing: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B35),
            borderRadius: BorderRadius.circular(20),
          ),
          child: IconButton(
            onPressed: onInvite,
            icon: const Icon(
              Icons.add,
              color: Colors.white,
              size: 20,
            ),
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }
}

class Debouncer {
  final int milliseconds;
  Timer? _timer;

  Debouncer({required this.milliseconds});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }
}
