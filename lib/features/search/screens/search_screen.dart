import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import '../../../shared/providers/auth_provider.dart'; // Temporarily disabled
import '../../../core/services/global_user_service.dart';
import '../providers/search_provider.dart';
import '../../../shared/models/user.dart';
// import '../../invitations/providers/invitation_provider.dart'; // Temporarily disabled

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _debouncer = Debouncer(milliseconds: 200);
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeOverlay();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debouncer.run(() {
      final searchProvider = context.read<SearchProvider>();
      searchProvider.searchUsers(query);
      _updateOverlay();
    });
  }

  void _inviteUser(User user) async {
    // make sure not to overlap invitation action sheet with another invitation action sheet
    if (_overlayEntry != null) return;

    // Show confirmation action sheet
    final confirmed = await _showInvitationActionSheet(context, user);

    if (confirmed == true) {
      final searchProvider = context.read<SearchProvider>();
      // final invitationProvider = context.read<InvitationProvider>(); // Temporarily disabled
      // final authProvider = context.read<AuthProvider>(); // Temporarily disabled
      final currentUsername =
          GlobalUserService.instance.currentUsername ?? 'Unknown User';

      final success = await searchProvider.sendInvitation(user.id);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contact request sent successfully!'),
            backgroundColor: Color(0xFFFF6B35),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(searchProvider.error ?? 'Failed to send contact request'),
            backgroundColor: Colors.red,
          ),
        );
      }
      _clearSearchAndOverlay();
    }
  }

  Future<bool?> _showInvitationActionSheet(
      BuildContext context, User user) async {
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
                  'Send Invitation',
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
                  'Send an invitation to ${user.username}?',
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
                          backgroundColor: const Color(0xFFFF6B35),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Send'),
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
              // Search results container
              Align(
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  onTap: () {}, // Prevents taps from propagating to background
                  child: Container(
                    margin: const EdgeInsets.only(top: 90),
                    width: MediaQuery.of(context).size.width * 0.8,
                    constraints: const BoxConstraints(maxHeight: 400),
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
                    child: _buildSearchContent(searchProvider),
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

  Widget _buildSearchContent(SearchProvider searchProvider) {
    // Show network error with retry
    if (searchProvider.showNetworkError) {
      return _buildNetworkErrorWidget(searchProvider);
    }

    // Show loading state
    if (searchProvider.searchState == SearchState.loading) {
      return _buildLoadingWidget();
    }

    // Show error state
    if (searchProvider.searchState == SearchState.error) {
      return _buildErrorWidget(searchProvider);
    }

    // Show search results
    if (searchProvider.searchResults.isNotEmpty) {
      return _buildSearchResults(searchProvider);
    }

    // Show no results
    if (searchProvider.searchState == SearchState.success &&
        searchProvider.query.length >= 3) {
      return _buildNoResultsWidget();
    }

    // Default empty state
    return _buildEmptyWidget();
  }

  Widget _buildNetworkErrorWidget(SearchProvider searchProvider) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.wifi_off,
            size: 48,
            color: Colors.orange.withOpacity(0.7),
          ),
          const SizedBox(height: 16),
          Text(
            'No Internet Connection',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            searchProvider.error ?? 'An error occurred',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: searchProvider.manualRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
          ),
          const SizedBox(height: 16),
          Text(
            'Searching...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(SearchProvider searchProvider) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Colors.red.withOpacity(0.7),
          ),
          const SizedBox(height: 16),
          Text(
            'Search Failed',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            searchProvider.error ?? 'An error occurred',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              searchProvider.clearError();
              searchProvider.searchUsers(searchProvider.query);
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B35),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsWidget() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 48,
            color: Colors.grey.withOpacity(0.7),
          ),
          const SizedBox(height: 16),
          Text(
            'No Users Found',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try searching with a different username',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search,
            size: 48,
            color: Colors.grey.withOpacity(0.7),
          ),
          const SizedBox(height: 16),
          Text(
            'Search Users',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Type at least 3 characters to search',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(SearchProvider searchProvider) {
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      itemCount: searchProvider.searchResults.length,
      itemBuilder: (context, index) {
        final user = searchProvider.searchResults[index];
        // final currentUser = context.read<AuthProvider>().currentUser; // Temporarily disabled

        // Don't show current user in search results - temporarily disabled
        // if (currentUser?.id == user.id) {
        //   return const SizedBox.shrink();
        // }

        return _UserCard(
          user: user,
          onInvite: () => _inviteUser(user),
        );
      },
    );
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _updateOverlay() {
    final searchProvider = context.read<SearchProvider>();

    // Show overlay if there's a query and we should show results
    final shouldShowOverlay = _searchController.text.isNotEmpty &&
        (searchProvider.showResults ||
            searchProvider.searchState != SearchState.idle);

    if (shouldShowOverlay) {
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
    final searchProvider = context.watch<SearchProvider>();
    final isInvitationLoading = searchProvider.isInvitationLoading(user.id);
    final isAlreadyInvited = user.alreadyInvited;
    final invitationStatus = user.invitationStatus;

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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user.isOnline ? 'Online' : 'Offline',
              style: TextStyle(
                color: user.isOnline
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
            ),
            if (isAlreadyInvited && invitationStatus != null)
              Text(
                _getInvitationStatusText(invitationStatus),
                style: TextStyle(
                  color: _getInvitationStatusColor(invitationStatus),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        trailing: _buildActionButton(
            context, isInvitationLoading, isAlreadyInvited, invitationStatus),
      ),
    );
  }

  Widget _buildActionButton(
      BuildContext context, bool isLoading, bool isInvited, String? status) {
    if (isLoading) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.3),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
            ),
          ),
        ),
      );
    }

    if (isInvited) {
      // Show remove invitation button
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: IconButton(
          onPressed: () => _removeInvitation(context),
          icon: const Icon(
            Icons.close,
            color: Colors.white,
            size: 20,
          ),
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
          ),
        ),
      );
    }

    // Show add invitation button
    return Container(
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
    );
  }

  void _removeInvitation(BuildContext context) async {
    final searchProvider = context.read<SearchProvider>();
    // final invitationProvider = context.read<InvitationProvider>(); // Temporarily disabled

    final success = await searchProvider.removeInvitation(user.id);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invitation removed for ${user.username}'),
          backgroundColor: const Color(0xFF4CAF50),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(searchProvider.error ?? 'Failed to remove invitation'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _getInvitationStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Invitation sent';
      case 'queued':
        return 'Will send when online';
      case 'accepted':
        return 'Invitation accepted';
      case 'declined':
        return 'Invitation declined';
      default:
        return 'Invitation sent';
    }
  }

  Color _getInvitationStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'queued':
        return Colors.grey;
      case 'accepted':
        return Colors.green;
      case 'declined':
        return Colors.red;
      default:
        return Colors.orange;
    }
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
