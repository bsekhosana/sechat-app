# SeChat Realtime Integration Guide

## Overview
This guide shows how to integrate the new realtime services with existing SeChat providers and UI components.

## Quick Start

### 1. Initialize Realtime Services
```dart
// In main.dart or app initialization
void main() async {
  // ... existing setup ...
  
  // Initialize realtime services
  await RealtimeServiceManager.instance.initialize();
  
  runApp(MyApp());
}
```

### 2. Access Services Anywhere
```dart
// Using extension methods (recommended)
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Access services directly
    final presenceService = context.presence;
    final typingService = context.typing;
    final messageService = context.messages;
    
    return Container();
  }
}

// Or using the manager directly
final manager = RealtimeServiceManager.instance;
final presenceService = manager.presence;
```

## Integration Examples

### Presence Integration

#### Update ChatListProvider
```dart
class ChatListProvider extends ChangeNotifier {
  late final PresenceService _presenceService;
  
  @override
  void init() {
    _presenceService = RealtimeServiceManager.instance.presence;
    
    // Listen for presence updates
    _presenceService.presenceStream.listen((update) {
      if (update.source == 'peer') {
        // Update conversation online status
        updateConversationOnlineStatus(update.sessionId, update.isOnline);
        notifyListeners();
      }
    });
  }
  
  void updateConversationOnlineStatus(String userId, bool isOnline) {
    // Find conversation by participant and update status
    final index = _conversations.indexWhere((conv) => 
      conv.participant1Id == userId || conv.participant2Id == userId);
    
    if (index != -1) {
      _conversations[index] = _conversations[index].copyWith(
        isOnline: isOnline,
        lastSeen: isOnline ? null : DateTime.now(),
      );
    }
  }
}
```

#### Update ChatHeader
```dart
class ChatHeader extends StatelessWidget {
  final String recipientId;
  
  @override
  Widget build(BuildContext context) {
    return Consumer<ChatListProvider>(
      builder: (context, chatListProvider, child) {
        final conversation = chatListProvider.getConversationByParticipant(recipientId);
        
        return Row(
          children: [
            // Online status indicator
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: conversation?.isOnline == true 
                  ? Colors.green 
                  : Colors.grey,
              ),
            ),
            
            // User name and status
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(conversation?.recipientName ?? 'Unknown'),
                Text(
                  conversation?.isOnline == true 
                    ? 'Online' 
                    : 'Last seen ${_formatLastSeen(conversation?.lastSeen)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
```

### Typing Integration

#### Update SessionChatProvider
```dart
class SessionChatProvider extends ChangeNotifier {
  late final TypingService _typingService;
  bool _isRecipientTyping = false;
  
  @override
  void init() {
    _typingService = RealtimeServiceManager.instance.typing;
    
    // Listen for typing updates
    _typingService.typingStream.listen((update) {
      if (update.source == 'peer' && 
          update.conversationId == _currentConversationId) {
        _isRecipientTyping = update.isTyping;
        notifyListeners();
      }
    });
  }
  
  // Handle text input for typing indicators
  void onTextInput(String text) {
    if (_currentConversationId != null && _currentRecipientId != null) {
      _typingService.onTextInput(
        _currentConversationId!,
        [_currentRecipientId!],
      );
    }
  }
  
  // Stop typing when message sent or focus lost
  void stopTyping() {
    if (_currentConversationId != null && _currentRecipientId != null) {
      _typingService.stopTyping(_currentConversationId!);
    }
  }
  
  bool get isRecipientTyping => _isRecipientTyping;
}
```

#### Update ChatInputField
```dart
class ChatInputField extends StatefulWidget {
  final String conversationId;
  final String recipientId;
  final Function(String) onSend;
  
  @override
  _ChatInputFieldState createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends State<ChatInputField> {
  final TextEditingController _controller = TextEditingController();
  late final TypingService _typingService;
  
  @override
  void initState() {
    super.initState();
    _typingService = RealtimeServiceManager.instance.typing;
    
    // Listen for text changes to trigger typing indicators
    _controller.addListener(_onTextChanged);
  }
  
  void _onTextChanged() {
    if (_controller.text.isNotEmpty) {
      _typingService.onTextInput(
        widget.conversationId,
        [widget.recipientId],
      );
    } else {
      _typingService.stopTyping(widget.conversationId);
    }
  }
  
  void _onSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      // Stop typing before sending
      _typingService.stopTyping(widget.conversationId);
      
      // Send message
      widget.onSend(text);
      _controller.clear();
    }
  }
  
  @override
  void dispose() {
    // Stop typing when disposing
    _typingService.stopTyping(widget.conversationId);
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'Type a message...',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _onSend(),
          ),
        ),
        IconButton(
          icon: Icon(Icons.send),
          onPressed: _onSend,
        ),
      ],
    );
  }
}
```

### Message Delivery Integration

#### Update Message Sending
```dart
class SessionChatProvider extends ChangeNotifier {
  late final MessageTransportService _messageService;
  
  @override
  void init() {
    _messageService = RealtimeServiceManager.instance.messages;
    
    // Listen for message delivery updates
    _messageService.deliveryStream.listen((update) {
      if (update.conversationId == _currentConversationId) {
        // Update message delivery state in UI
        _updateMessageDeliveryState(update.messageId, update.state);
        notifyListeners();
      }
    });
  }
  
  Future<void> sendMessage(String content) async {
    final message = Message(
      id: GuidGenerator.generateGuid(),
      content: content,
      senderId: _currentUserId!,
      recipientId: _currentRecipientId!,
      conversationId: _currentConversationId!,
      timestamp: DateTime.now(),
    );
    
    // Send via realtime service
    final success = await _messageService.sendMessage(message);
    
    if (success) {
      // Add to local messages list
      _messages.add(message);
      notifyListeners();
    }
  }
  
  void _updateMessageDeliveryState(String messageId, MessageDeliveryState state) {
    final index = _messages.indexWhere((msg) => msg.id == messageId);
    if (index != -1) {
      // Update message with delivery state
      // You might need to extend Message model to include delivery state
    }
  }
}
```

#### Update Message Widget
```dart
class MessageWidget extends StatelessWidget {
  final Message message;
  final MessageDeliveryState? deliveryState;
  
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            padding: EdgeInsets.all(12),
            margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.blue[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(message.content),
          ),
        ),
        
        // Delivery status indicator
        Container(
          margin: EdgeInsets.only(right: 8),
          child: _buildDeliveryIndicator(deliveryState),
        ),
      ],
    );
  }
  
  Widget _buildDeliveryIndicator(MessageDeliveryState? state) {
    switch (state) {
      case MessageDeliveryState.localQueued:
        return Icon(Icons.schedule, size: 16, color: Colors.grey);
      case MessageDeliveryState.socketSent:
        return Icon(Icons.schedule, size: 16, color: Colors.grey);
      case MessageDeliveryState.serverAcked:
        return Icon(Icons.done, size: 16, color: Colors.grey);
      case MessageDeliveryState.delivered:
        return Icon(Icons.done_all, size: 16, color: Colors.grey);
      case MessageDeliveryState.read:
        return Icon(Icons.done_all, size: 16, color: Colors.blue);
      case MessageDeliveryState.failed:
        return Icon(Icons.error, size: 16, color: Colors.red);
      default:
        return Icon(Icons.schedule, size: 16, color: Colors.grey);
    }
  }
}
```

## Migration Strategy

### Phase 1: Add New Services (Current)
- ✅ Core realtime services implemented
- ✅ Socket server protocol updated
- ✅ Service manager created

### Phase 2: Gradual Integration
1. **Presence**: Start with chat list and headers
2. **Typing**: Integrate with chat input fields
3. **Messages**: Update message sending and delivery states

### Phase 3: Remove Legacy Code
- Remove old typing indicator methods
- Remove old online status methods
- Remove old message status methods

### Phase 4: Testing & Optimization
- Test all realtime features
- Optimize performance
- Add error handling

## Best Practices

### 1. Service Access
```dart
// ✅ Good: Use extension methods
final presence = context.presence;

// ❌ Bad: Direct service access
final presence = PresenceService.instance;
```

### 2. Error Handling
```dart
try {
  await _messageService.sendMessage(message);
} catch (e) {
  // Handle error gracefully
  _showErrorMessage('Failed to send message');
}
```

### 3. Resource Management
```dart
@override
void dispose() {
  // Always stop typing when disposing
  _typingService.stopTyping(_conversationId);
  super.dispose();
}
```

### 4. State Management
```dart
// Use streams for real-time updates
_messageService.deliveryStream.listen((update) {
  // Update UI state
  _updateMessageDeliveryState(update.messageId, update.state);
  notifyListeners();
});
```

## Troubleshooting

### Common Issues

1. **Services not initialized**
   - Ensure `RealtimeServiceManager.instance.initialize()` is called
   - Check initialization order in main.dart

2. **Typing indicators not working**
   - Verify conversation ID and recipient ID are correct
   - Check socket connection status

3. **Presence not updating**
   - Verify app lifecycle listeners are working
   - Check socket connection and server logs

4. **Message delivery states not updating**
   - Verify message ID consistency
   - Check server event handlers

### Debug Mode
Enable debug logging by setting the environment variable:
```bash
flutter run --dart-define=LOG_LEVEL=true
```

This will show detailed realtime service logs with counters and tags.

---
**Status**: Integration Guide Complete  
**Next**: Start implementing in existing providers
