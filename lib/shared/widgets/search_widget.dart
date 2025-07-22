import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../features/search/providers/search_provider.dart';
import '../models/user.dart';
import '../../features/invitations/providers/invitation_provider.dart';

class SearchWidget extends StatefulWidget {
  const SearchWidget({super.key});

  @override
  State<SearchWidget> createState() => _SearchWidgetState();
}

class _SearchWidgetState extends State<SearchWidget>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;
  Timer? _feedbackTimer;

  // Animation controllers
  late AnimationController _loadingController;
  late Animation<double> _loadingAnimation;
  late AnimationController _feedbackController;
  late Animation<double> _feedbackAnimation;

  @override
  void initState() {
    super.initState();

    // Loading animation controller
    _loadingController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _loadingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _loadingController, curve: Curves.easeInOut),
    );

    // Feedback animation controller
    _feedbackController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _feedbackAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _feedbackController, curve: Curves.easeInOut),
    );

    _searchController.addListener(_onSearchChanged);

    // Note: The new SearchProvider handles invitation status updates internally
    // No need to manually update here as it's handled by the invitation flow
  }

  void _onSearchChanged() {
    // Cancel any existing timer
    _debounceTimer?.cancel();

    // Start a new 1.5-second timer to match SearchProvider debounce
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        final searchProvider = context.read<SearchProvider>();
        print(
            '🔍 SearchWidget: Triggering search for: "${_searchController.text}"');
        searchProvider.searchUsers(_searchController.text);
      }
    });
  }

  // Show feedback message below search bar
  void _showFeedback(String message, {bool isError = false}) {
    setState(() {
      // _feedbackMessage = message; // This line was removed from the new_code
      // _feedbackColor = isError ? Colors.red : Colors.green; // This line was removed from the new_code
    });

    // Animate in
    _feedbackController.forward();

    // Auto-hide after 3 seconds
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _feedbackController.reverse().then((_) {
          setState(() {
            // _feedbackMessage = null; // This line was removed from the new_code
          });
        });
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    context.read<SearchProvider>().clearSearch();
  }

  void _showSearchActionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SearchActionSheet(
        searchController: _searchController,
        focusNode: _searchFocusNode,
        onClearSearch: _clearSearch,
        onSearchChanged: _onSearchChanged,
      ),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _loadingController.dispose();
    _feedbackController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _showSearchActionSheet,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2C),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Icon(
            Icons.search,
            color: Color(0xFF666666),
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _SearchActionSheet extends StatefulWidget {
  final TextEditingController searchController;
  final FocusNode focusNode;
  final VoidCallback onClearSearch;
  final VoidCallback onSearchChanged;

  const _SearchActionSheet({
    required this.searchController,
    required this.focusNode,
    required this.onClearSearch,
    required this.onSearchChanged,
  });

  @override
  State<_SearchActionSheet> createState() => _SearchActionSheetState();
}

class _SearchActionSheetState extends State<_SearchActionSheet>
    with TickerProviderStateMixin {
  late AnimationController _loadingController;
  late Animation<double> _loadingAnimation;

  @override
  void initState() {
    super.initState();

    // Loading animation controller
    _loadingController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _loadingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _loadingController, curve: Curves.easeInOut),
    );

    // Focus the search input when action sheet opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _loadingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
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

          // Search input section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                // Search input
                Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C2C2C),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.searchController,
                    builder: (context, value, child) {
                      return TextField(
                        controller: widget.searchController,
                        focusNode: widget.focusNode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search users...',
                          hintStyle: const TextStyle(
                            color: Color(0xFF666666),
                            fontSize: 16,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Color(0xFF666666),
                          ),
                          suffixIcon: value.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: Color(0xFF666666),
                                  ),
                                  onPressed: widget.onClearSearch,
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        onChanged: (value) {
                          // Only trigger search through the debounced method in parent
                          // Don't call widget.onSearchChanged() directly here
                        },
                      );
                    },
                  ),
                ),

                // Loading indicator
                Consumer<SearchProvider>(
                  builder: (context, searchProvider, child) {
                    if (searchProvider.searchState == SearchState.loading) {
                      return Container(
                        margin: const EdgeInsets.only(top: 8),
                        child: const LinearProgressIndicator(
                          backgroundColor: Colors.transparent,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
                          minHeight: 2,
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Results section
          Expanded(
            child: Consumer<SearchProvider>(
              builder: (context, searchProvider, child) {
                print(
                    '🔍 SearchWidget: Building UI - State: ${searchProvider.searchState}, Query: "${searchProvider.query}", Error: "${searchProvider.error}", ShowNetworkError: ${searchProvider.showNetworkError}');

                if (searchProvider.query.isEmpty) {
                  return _buildEmptyState();
                }

                // Show network error with retry
                if (searchProvider.showNetworkError) {
                  print('🔍 SearchWidget: Showing network error widget');
                  return _buildNetworkErrorWidget(searchProvider);
                }

                // Show loading state
                if (searchProvider.searchState == SearchState.loading) {
                  print('🔍 SearchWidget: Showing loading widget');
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFFF6B35),
                    ),
                  );
                }

                // Show error state
                if (searchProvider.searchState == SearchState.error) {
                  print('🔍 SearchWidget: Showing error widget');
                  return _buildErrorWidget(searchProvider);
                }

                // Show search results
                if (searchProvider.searchResults.isNotEmpty) {
                  print('🔍 SearchWidget: Showing results list');
                  return _buildResultsList(searchProvider.searchResults);
                }

                // Show no results
                if (searchProvider.searchState == SearchState.success &&
                    searchProvider.query.length >= 3) {
                  print('🔍 SearchWidget: Showing no results widget');
                  return _buildNoResults();
                }

                // Default empty state
                print('🔍 SearchWidget: Showing default empty state');
                return _buildEmptyState();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            color: Colors.white.withOpacity(0.3),
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'Search for users to connect with',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Type a username to find people',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.search_off,
            color: Color(0xFF666666),
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'No results found',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search term',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkErrorWidget(SearchProvider searchProvider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wifi_off,
            size: 64,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Please check your internet connection and try again.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: searchProvider.manualRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry Now'),
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

  Widget _buildErrorWidget(SearchProvider searchProvider) {
    // Extract a user-friendly error message
    String errorMessage = searchProvider.error ?? 'An error occurred';
    if (errorMessage.contains('Connection reset by peer')) {
      errorMessage = 'Connection to server was lost. Please try again.';
    } else if (errorMessage.contains('SocketException')) {
      errorMessage =
          'Unable to connect to server. Please check your connection.';
    } else if (errorMessage.contains('ClientException')) {
      errorMessage = 'Network error occurred. Please try again.';
    } else if (errorMessage.length > 100) {
      errorMessage = 'Search failed. Please try again.';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              errorMessage,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
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

  Widget _buildResultsList(List<User> results) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final user = results[index];
        return _buildUserResult(user);
      },
    );
  }

  Widget _buildUserResult(User user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // Optional: Handle user tap for profile view
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Profile Placeholder
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 255, 107, 53),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      user.username.isNotEmpty
                          ? user.username[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // User Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHighlightedText(
                        user.username,
                        context.read<SearchProvider>().query,
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Joined ${_formatDate(user.createdAt)}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Invite/Remove Button
                Consumer<InvitationProvider>(
                  builder: (context, invitationProvider, child) {
                    final isInvited = invitationProvider.isUserInvited(user.id);
                    final isQueued = invitationProvider.isUserQueued(user.id);
                    final isLoading = context
                        .read<SearchProvider>()
                        .isInvitationLoading(user.id);

                    // Determine button state
                    Widget buttonContent;
                    Color buttonColor;
                    VoidCallback? onPressed;
                    String tooltip;

                    if (isLoading) {
                      // Loading state
                      buttonContent = const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      );
                      buttonColor = const Color(0xFFFF6B35);
                      onPressed = null;
                      tooltip = 'Processing...';
                    } else if (isQueued) {
                      // Queued state
                      buttonContent = const Icon(
                        Icons.schedule,
                        color: Colors.white,
                        size: 20,
                      );
                      buttonColor =
                          const Color(0xFFFFA500); // Orange for queued
                      onPressed =
                          () => _showRemoveInvitationActionSheet(context, user);
                      tooltip = 'Queued invitation - tap to remove';
                    } else if (isInvited) {
                      // Invited state
                      buttonContent = const Icon(
                        Icons.person_remove,
                        color: Colors.white,
                        size: 20,
                      );
                      buttonColor = const Color(0xFFFF5555);
                      onPressed =
                          () => _showRemoveInvitationActionSheet(context, user);
                      tooltip = 'Remove invitation';
                    } else {
                      // Not invited state
                      buttonContent = const Icon(
                        Icons.person_add,
                        color: Colors.white,
                        size: 20,
                      );
                      buttonColor = const Color(0xFFFF6B35);
                      onPressed =
                          () => _showInvitationActionSheet(context, user);
                      tooltip = 'Send invitation';
                    }

                    return Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: buttonColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        onPressed: onPressed,
                        icon: buttonContent,
                        tooltip: tooltip,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper method to highlight matching text
  Widget _buildHighlightedText(String text, String query, TextStyle style) {
    if (query.isEmpty) {
      return Text(text, style: style);
    }

    final String lowerText = text.toLowerCase();
    final String lowerQuery = query.toLowerCase();

    if (!lowerText.contains(lowerQuery)) {
      return Text(text, style: style);
    }

    final List<TextSpan> spans = [];
    int start = 0;

    while (start < text.length) {
      final int index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        // No more matches, add remaining text
        spans.add(TextSpan(text: text.substring(start), style: style));
        break;
      }

      // Add text before match
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: style));
      }

      // Add highlighted match
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: style.copyWith(
          backgroundColor: const Color(0xFFFF6B35),
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ));

      start = index + query.length;
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays < 30) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months months ago';
    } else {
      return DateFormat('MMM yyyy').format(date);
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
                        onPressed: () async {
                          final invitationProvider =
                              context.read<InvitationProvider>();

                          final success =
                              await invitationProvider.sendInvitation(user.id);

                          if (success && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Invitation sent to ${user.username}!'),
                                backgroundColor: Colors.green,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          } else if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Failed to send invitation: ${invitationProvider.error}'),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }

                          Navigator.of(context).pop(true);
                        },
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

  Future<bool?> _showRemoveInvitationActionSheet(
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
                  'Remove Invitation',
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
                  'Are you sure you want to remove the invitation to ${user.username}?',
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
                        onPressed: () async {
                          final searchProvider = context.read<SearchProvider>();
                          final invitationProvider =
                              context.read<InvitationProvider>();

                          final success =
                              await searchProvider.removeInvitation(user.id);

                          if (success && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Invitation removed from ${user.username}!'),
                                backgroundColor: Colors.green,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          } else if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Failed to remove invitation: ${searchProvider.error}'),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }

                          Navigator.of(context).pop(true);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5555),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Remove'),
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
}
