import 'package:flutter/material.dart';

/// Search bar widget for filtering chat conversations
class ChatSearchBar extends StatefulWidget {
  final Function(String) onSearchChanged;
  final VoidCallback onSearchCleared;
  final String? hintText;
  final String? initialValue;

  const ChatSearchBar({
    super.key,
    required this.onSearchChanged,
    required this.onSearchCleared,
    this.hintText,
    this.initialValue,
  });

  @override
  State<ChatSearchBar> createState() => _ChatSearchBarState();
}

class _ChatSearchBarState extends State<ChatSearchBar> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() {
      _hasFocus = _focusNode.hasFocus;
    });
  }

  void _onSearchChanged(String value) {
    widget.onSearchChanged(value);
  }

  void _onClearPressed() {
    _controller.clear();
    widget.onSearchCleared();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: _hasFocus
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withOpacity(0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _hasFocus
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: widget.hintText ?? 'Search conversations...',
          hintStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 16,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: _hasFocus
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            size: 24,
          ),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  onPressed: _onClearPressed,
                  icon: Icon(
                    Icons.clear,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  tooltip: 'Clear search',
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 16,
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: (value) {
          _focusNode.unfocus();
        },
      ),
    );
  }
}
