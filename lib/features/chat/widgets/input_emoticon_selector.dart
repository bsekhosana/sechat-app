import 'package:flutter/material.dart';

/// Widget for selecting emoticons to send
class InputEmoticonSelector extends StatefulWidget {
  final Function(String) onEmoticonSelected;
  final VoidCallback onClose;

  const InputEmoticonSelector({
    super.key,
    required this.onEmoticonSelected,
    required this.onClose,
  });

  @override
  State<InputEmoticonSelector> createState() => _InputEmoticonSelectorState();
}

class _InputEmoticonSelectorState extends State<InputEmoticonSelector>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late PageController _pageController;

  int _currentPage = 0;
  final int _emoticonsPerPage = 32;

  // Popular emoticon categories
  final List<Map<String, dynamic>> _emoticonCategories = [
    {
      'name': 'Smileys',
      'emoticons': [
        '😀',
        '😃',
        '😄',
        '😁',
        '😆',
        '😅',
        '😂',
        '🤣',
        '😊',
        '😇',
        '🙂',
        '🙃',
        '😉',
        '😌',
        '😍',
        '🥰',
        '😘',
        '😗',
        '😙',
        '😚',
        '😋',
        '😛',
        '😝',
        '😜',
        '🤪',
        '🤨',
        '🧐',
        '🤓',
        '😎',
        '🤩',
        '🥳',
        '😏',
      ],
    },
    {
      'name': 'Gestures',
      'emoticons': [
        '👍',
        '👎',
        '👌',
        '✌️',
        '🤞',
        '🤟',
        '🤘',
        '🤙',
        '👈',
        '👉',
        '👆',
        '🖕',
        '👇',
        '☝️',
        '👋',
        '🤚',
        '🖐️',
        '✋',
        '🖖',
        '👌',
        '🤌',
        '🤏',
        '✌️',
        '🤞',
        '🤟',
        '🤘',
        '🤙',
        '👈',
        '👉',
        '👆',
        '🖕',
        '👇',
      ],
    },
    {
      'name': 'Hearts',
      'emoticons': [
        '❤️',
        '🧡',
        '💛',
        '💚',
        '💙',
        '💜',
        '🖤',
        '🤍',
        '🤎',
        '💔',
        '❣️',
        '💕',
        '💞',
        '💓',
        '💗',
        '💖',
        '💘',
        '💝',
        '💟',
        '♥️',
        '💌',
        '💋',
        '💯',
        '💢',
        '💥',
        '💫',
        '💦',
        '💨',
        '🕳️',
        '💬',
        '🗨️',
        '🗯️',
      ],
    },
    {
      'name': 'Animals',
      'emoticons': [
        '🐶',
        '🐱',
        '🐭',
        '🐹',
        '🐰',
        '🦊',
        '🐻',
        '🐼',
        '🐨',
        '🐯',
        '🦁',
        '🐮',
        '🐷',
        '🐸',
        '🐵',
        '🙈',
        '🙉',
        '🙊',
        '🐒',
        '🐔',
        '🐧',
        '🐦',
        '🐤',
        '🐣',
        '🐥',
        '🦆',
        '🦅',
        '🦉',
        '🦇',
        '🐺',
        '🐗',
        '🐴',
      ],
    },
    {
      'name': 'Food',
      'emoticons': [
        '🍎',
        '🍐',
        '🍊',
        '🍋',
        '🍌',
        '🍉',
        '🍇',
        '🍓',
        '🍈',
        '🍒',
        '🍑',
        '🥭',
        '🍍',
        '🥥',
        '🥝',
        '🍅',
        '🍆',
        '🥑',
        '🥦',
        '🥬',
        '🥒',
        '🌶️',
        '🌽',
        '🥕',
        '🥔',
        '🍠',
        '🥐',
        '🥯',
        '🍞',
        '🥖',
        '🥨',
        '🧀',
      ],
    },
    {
      'name': 'Objects',
      'emoticons': [
        '⚽',
        '🏀',
        '🏈',
        '⚾',
        '🥎',
        '🎾',
        '🏐',
        '🏉',
        '🥏',
        '🎱',
        '🪀',
        '🏓',
        '🏸',
        '🏒',
        '🏑',
        '🥍',
        '🏏',
        '🥅',
        '⛳',
        '🥊',
        '🥋',
        '🎽',
        '🛹',
        '🛷',
        '⛸️',
        '🥌',
        '🎿',
        '⛷️',
        '🏂',
        '🏋️',
        '🤼',
        '🤸',
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _emoticonCategories.length,
      vsync: this,
    );
    _pageController = PageController();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  'Emoticons',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: widget.onClose,
                  icon: Icon(
                    Icons.close,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),

          // Category tabs
          TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: Theme.of(context).colorScheme.primary,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor:
                Theme.of(context).colorScheme.onSurfaceVariant,
            tabs: _emoticonCategories.map((category) {
              return Tab(text: category['name'] as String);
            }).toList(),
          ),

          // Emoticon grid
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _emoticonCategories.map((category) {
                return _buildEmoticonGrid(
                    category['emoticons'] as List<String>);
              }).toList(),
            ),
          ),

          // Page indicator
          if (_emoticonCategories.isNotEmpty) _buildPageIndicator(),
        ],
      ),
    );
  }

  /// Build emoticon grid
  Widget _buildEmoticonGrid(List<String> emoticons) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: emoticons.length,
      itemBuilder: (context, index) {
        return _buildEmoticonItem(emoticons[index]);
      },
    );
  }

  /// Build individual emoticon item
  Widget _buildEmoticonItem(String emoticon) {
    return GestureDetector(
      onTap: () => widget.onEmoticonSelected(emoticon),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
          ),
        ),
        child: Center(
          child: Text(
            emoticon,
            style: const TextStyle(fontSize: 24),
          ),
        ),
      ),
    );
  }

  /// Build page indicator
  Widget _buildPageIndicator() {
    final totalPages = (_emoticonCategories.length / _emoticonsPerPage).ceil();

    if (totalPages <= 1) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(totalPages, (index) {
          return Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: index == _currentPage
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withOpacity(0.3),
              shape: BoxShape.circle,
            ),
          );
        }),
      ),
    );
  }
}
