import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../features/search/providers/search_provider.dart';
import '../models/user.dart';
import '../../features/auth/screens/main_nav_screen.dart';

class SearchWidget extends StatefulWidget {
  const SearchWidget({super.key});

  @override
  State<SearchWidget> createState() => _SearchWidgetState();
}

class _SearchWidgetState extends State<SearchWidget>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late AnimationController _loadingController;
  late AnimationController _dropdownController;
  late Animation<double> _loadingAnimation;
  late Animation<double> _slideAnimation;

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

    // Dropdown animation controller
    _dropdownController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _dropdownController, curve: Curves.easeOut),
    );

    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final searchProvider = context.read<SearchProvider>();
    searchProvider.searchUsers(_searchController.text);
    if (_searchController.text.isNotEmpty) {
      MainNavScreen.of(context)?.showSearchOverlay(_searchController);
    } else {
      MainNavScreen.of(context)?.hideSearchOverlay();
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _focusNode.unfocus();
    context.read<SearchProvider>().clearSearch();
    MainNavScreen.of(context)?.hideSearchOverlay();
  }

  @override
  void dispose() {
    MainNavScreen.of(context)?.hideSearchOverlay();
    _searchController.dispose();
    _focusNode.dispose();
    _loadingController.dispose();
    _dropdownController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchProvider = context.watch<SearchProvider>();
    return Stack(
      children: [
        Container(
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2C),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, child) {
              return TextField(
                controller: _searchController,
                focusNode: _focusNode,
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
                          onPressed: _clearSearch,
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                onTap: () {
                  if (_searchController.text.isNotEmpty) {
                    MainNavScreen.of(context)
                        ?.showSearchOverlay(_searchController);
                  }
                },
                onEditingComplete: () {
                  MainNavScreen.of(context)?.hideSearchOverlay();
                },
                onSubmitted: (_) {
                  MainNavScreen.of(context)?.hideSearchOverlay();
                },
              );
            },
          ),
        ),
        if (searchProvider.isLoading)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              backgroundColor: Colors.transparent,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
              minHeight: 2,
            ),
          ),
      ],
    );
  }

  Widget _buildResultsDropdown(SearchProvider searchProvider) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF404040)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 15,
            offset: const Offset(0, 8),
            spreadRadius: 2,
          ),
        ],
      ),
      child: searchProvider.searchResults.isNotEmpty
          ? _buildResultsList(searchProvider.searchResults)
          : _buildNoResults(),
    );
  }

  Widget _buildNoResults() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(
            Icons.search_off,
            color: Color(0xFF666666),
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            'No results found',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(List<User> results) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: results.length,
        itemBuilder: (context, index) {
          final user = results[index];
          return _buildUserResult(user);
        },
      ),
    );
  }

  Widget _buildUserResult(User user) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            // Optional: Handle user tap for profile view
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Profile Placeholder (Google style)
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

                const SizedBox(width: 12),

                // User Info (Center) with highlighted text
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
                // Invite Button (Right)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    onPressed: () => _sendInvitation(user),
                    icon: const Icon(
                      Icons.person_add,
                      color: Colors.white,
                      size: 20,
                    ),
                    tooltip: 'Send invitation',
                  ),
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

  Future<void> _sendInvitation(User user) async {
    final searchProvider = context.read<SearchProvider>();

    final success = await searchProvider.sendInvitation(user.id);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invitation sent to ${user.username}!'),
          backgroundColor: const Color(0xFFFF6B35),
          duration: const Duration(seconds: 2),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send invitation: ${searchProvider.error}'),
          backgroundColor: const Color(0xFFFF5555),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
