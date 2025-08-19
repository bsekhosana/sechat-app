import 'package:flutter/foundation.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import 'package:sechat_app/core/services/encryption_service.dart';
import 'package:sechat_app/core/services/key_exchange_service.dart';
import 'package:sechat_app/core/services/se_shared_preference_service.dart';
import 'package:sechat_app/core/services/indicator_service.dart';
import 'package:sechat_app/core/services/ui_service.dart';
import 'package:sechat_app/core/utils/guid_generator.dart';
import 'package:sechat_app/features/notifications/services/notification_manager_service.dart';
import 'package:sechat_app/shared/models/key_exchange_request.dart';
import 'dart:convert'; // Added for base64 decoding

/// Provider for managing key exchange requests
class KeyExchangeRequestProvider extends ChangeNotifier {
  final List<KeyExchangeRequest> _sentRequests = [];
  final List<KeyExchangeRequest> _receivedRequests = [];
  final List<KeyExchangeRequest> _pendingRequests = [];

  /// Initialize the provider and load saved requests
  Future<void> initialize() async {
    await _loadSavedRequests();
    _ensureNotificationServiceConnection();
  }

  /// Refresh the data from storage
  Future<void> refresh() async {
    await _loadSavedRequests();
  }

  List<KeyExchangeRequest> get sentRequests => List.unmodifiable(_sentRequests);
  List<KeyExchangeRequest> get receivedRequests =>
      List.unmodifiable(_receivedRequests);
  List<KeyExchangeRequest> get pendingRequests =>
      List.unmodifiable(_pendingRequests);

  /// Check if there are new key exchange items that need badge indicators
  bool get hasNewItems {
    final now = DateTime.now();
    final fiveMinutesAgo = now.subtract(const Duration(minutes: 5));

    // Check for new sent requests (within last 5 minutes)
    final hasNewSent = _sentRequests.any((req) =>
        req.timestamp.isAfter(fiveMinutesAgo) &&
        (req.status == 'pending' || req.status == 'sent'));

    // Check for new received requests (within last 5 minutes)
    final hasNewReceived = _receivedRequests.any((req) =>
        req.timestamp.isAfter(fiveMinutesAgo) && req.status == 'received');

    return hasNewSent || hasNewReceived;
  }

  /// Get count of new key exchange items
  int get newItemsCount {
    final now = DateTime.now();
    final fiveMinutesAgo = now.subtract(const Duration(minutes: 5));

    int count = 0;

    // Count new sent requests
    count += _sentRequests
        .where((req) =>
            req.timestamp.isAfter(fiveMinutesAgo) &&
            (req.status == 'pending' || req.status == 'sent'))
        .length;

    // Count new received requests
    count += _receivedRequests
        .where((req) =>
            req.timestamp.isAfter(fiveMinutesAgo) && req.status == 'received')
        .length;

    return count;
  }

  /// Notify indicator service about new key exchange items
  void _notifyNewItems() {
    try {
      // Badge counts are now handled automatically by the main navigation screen
      // No need to manually notify the indicator service
      print(
          '🔑 KeyExchangeRequestProvider: New key exchange items detected, badge counts will update automatically');
    } catch (e) {
      print('🔑 KeyExchangeRequestProvider: Error in notification: $e');
    }
  }

  /// Ensure connection with socket service
  void _ensureNotificationServiceConnection() {
    try {
      // Connect to socket service for key exchange notifications
      // This will be handled by the main navigation screen
      print(
          '🔑 KeyExchangeRequestProvider: ✅ Socket service connection will be handled by main navigation');

      // Set up socket event handlers for key exchange events
      _setupSocketEventHandlers();
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: ❌ Failed to connect to socket service: $e');
    }
  }

  /// Set up socket event handlers for key exchange events
  void _setupSocketEventHandlers() {
    try {
      final socketService = SeSocketService();

      // Listen for revoked key exchange requests
      socketService.on('key_exchange_revoked', (data) {
        final requestId = data['requestId'] as String?;
        final senderId = data['senderId'] as String?;

        if (requestId != null && senderId != null) {
          handleRequestRevoked(requestId, senderId);
        }
      });

      print(
          '🔑 KeyExchangeRequestProvider: ✅ Socket event handlers set up successfully');
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: ❌ Error setting up socket event handlers: $e');
    }
  }

  // /// Process received key exchange request (called by callback system)
  // Future<void> processReceivedKeyExchangeRequest(Map<String, dynamic> data) async {
  //   print('🔑 KeyExchangeRequestProvider: 📥 Processing received key exchange request');
  //   print('🔑 KeyExchangeRequestProvider: 📋 Request data: $data');

  //   final senderId = data['senderId'] as String?;
  //   final publicKey = data['publicKey'] as String?;
  //   final requestId = data['requestId'] as String?;
  //   final requestPhrase = data['requestPhrase'] as String?;
  //   final version = data['version']?.toString();
  //   final timestamp = data['timestamp'] as String?;

  //   if (senderId != null && publicKey != null && requestId != null && requestPhrase != null) {
  //     print('🔑 KeyExchangeRequestProvider: ✅ Valid key exchange request data');

  //     // Create a new received request
  //     final receivedRequest = KeyExchangeRequest(
  //       id: requestId,
  //       fromSessionId: senderId,
  //       toSessionId: SeSessionService().currentSessionId ?? '',
  //       requestPhrase: requestPhrase,
  //       status: 'received',
  //       timestamp: DateTime.now(),
  //       type: 'received',
  //     );

  //     // Add to received requests list
  //     _receivedRequests.add(receivedRequest);

  //     // Save to local storage
  //     await _saveReceivedRequest(receivedRequest);

  //     // Notify listeners
  //     notifyListeners();

  //     // Notify about new items
  //     _notifyNewItems();

  //     print('🔑 KeyExchangeRequestProvider: ✅ Incoming request added and saved');
  //   } else {
  //     print('🔑 KeyExchangeRequestProvider: ❌ Invalid key exchange request data');
  //     print('🔑 KeyExchangeRequestProvider: 🔍 Missing fields:');
  //     print('🔑 KeyExchangeRequestProvider:   senderId: $senderId');
  //     print('🔑 KeyExchangeRequestProvider:   publicKey: $publicKey');
  //     print('🔑 KeyExchangeRequestProvider:   requestId: $requestId');
  //     print('🔑 KeyExchangeRequestProvider:   requestPhrase: $requestPhrase');
  //   }
  // }

  /// Add notification item for key exchange activities
  Future<void> _addNotificationItem(String title, String body, String type,
      Map<String, dynamic>? data) async {
    try {
      // Create notification through NotificationManagerService
      await NotificationManagerService().createKeyExchangeNotification(
        type: type,
        senderId: data?['sender_id'] ?? data?['recipient_id'] ?? 'unknown',
        senderName: title,
        message: body,
        metadata: data,
      );
      print('🔑 KeyExchangeRequestProvider: ✅ Notification created: $title');
    } catch (e) {
      print('🔑 KeyExchangeRequestProvider: ❌ Error creating notification: $e');
    }
  }

  /// Send a key exchange request to another user
  Future<bool> sendKeyExchangeRequest(
    String recipientSessionId, {
    required String requestPhrase,
  }) async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: Sending key exchange request to: $recipientSessionId');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🔑 KeyExchangeRequestProvider: User not logged in');

        // Show error message to user
        UIService().showSnack(
          'User not logged in. Please log in and try again.',
        );

        return false;
      }

      // Check if we already have a pending or existing request with this session
      final existingRequest = _sentRequests.firstWhere(
        (req) =>
            req.toSessionId == recipientSessionId &&
            (req.status == 'pending' || req.status == 'sent'),
        orElse: () => KeyExchangeRequest(
          id: '',
          fromSessionId: '',
          toSessionId: '',
          requestPhrase: '',
          status: '',
          timestamp: DateTime.now(),
          type: '',
          version: '',
        ),
      );

      if (existingRequest.id.isNotEmpty) {
        print(
            '🔑 KeyExchangeRequestProvider: ❌ Already have a pending/sent request with $recipientSessionId (status: ${existingRequest.status})');

        // Show error message to user
        UIService().showSnack(
          'You already have a pending key exchange request with this user.',
        );

        return false;
      }

      // Check if we have a received request from this session that we haven't responded to
      final receivedRequest = _receivedRequests.firstWhere(
        (req) =>
            req.fromSessionId == recipientSessionId && req.status == 'received',
        orElse: () => KeyExchangeRequest(
          id: '',
          fromSessionId: '',
          toSessionId: '',
          requestPhrase: '',
          status: '',
          timestamp: DateTime.now(),
          type: '',
          version: '',
        ),
      );

      if (receivedRequest.id.isNotEmpty) {
        print(
            '🔑 KeyExchangeRequestProvider: ❌ Already have a received request from $recipientSessionId that needs response');

        // Show error message to user
        UIService().showSnack(
          'You have a pending key exchange request from this user. Please respond to it first.',
        );

        return false;
      }

      // Create the key exchange request
      final request = KeyExchangeRequest(
        id: GuidGenerator.generateShortId(),
        fromSessionId: currentUserId,
        toSessionId: recipientSessionId,
        requestPhrase: requestPhrase,
        status: 'pending',
        timestamp: DateTime.now(),
        type: 'key_exchange_request',
        version: '1', // Default version for outgoing requests
      );

      // Store locally
      _sentRequests.add(request);
      notifyListeners();

      // Notify about new items for badge indicators
      _notifyNewItems();

      // Add notification item for sent request
      await _addNotificationItem(
        'Key Exchange Request Sent',
        'Request sent to establish secure connection',
        'key_exchange_sent',
        {
          'request_id': request.id,
          'recipient_id': recipientSessionId,
          'request_phrase': requestPhrase,
          'timestamp': request.timestamp.millisecondsSinceEpoch,
        },
      );

      // Send via KeyExchangeService which handles the proper data structure
      final success = await KeyExchangeService.instance.requestKeyExchange(
        recipientSessionId,
        requestPhrase: requestPhrase,
      );

      if (success) {
        print(
            '🔑 KeyExchangeRequestProvider: ✅ Key exchange request sent successfully');

        // Update status from 'pending' to 'sent' after successful sending
        request.status = 'sent';
        notifyListeners();

        // Save to local storage for persistence
        await _saveSentRequest(request);

        return true;
      } else {
        print(
            '🔑 KeyExchangeRequestProvider: ❌ Failed to send key exchange request');

        // Remove the request from local list if sending failed
        _sentRequests.remove(request);
        notifyListeners();

        // Show error message to user
        UIService().showSnack(
          'Failed to send key exchange request. Please try again.',
        );

        return false;
      }
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error sending key exchange request: $e');

      // Show error message to user
      UIService().showSnack(
        'Error sending key exchange request: ${e.toString()}',
      );

      return false;
    }
  }

  /// Process a received key exchange request
  Future<void> processReceivedKeyExchangeRequest(
      Map<String, dynamic> data) async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: Processing received key exchange request');
      print('🔑 KeyExchangeRequestProvider: 📋 Request data: $data');

      // Handle both old and new data formats
      final requestId =
          data['requestId'] as String? ?? data['request_id'] as String?;
      final senderId =
          data['senderId'] as String? ?? data['sender_id'] as String?;
      final requestPhrase =
          data['requestPhrase'] as String? ?? data['request_phrase'] as String?;
      final timestampRaw = data['timestamp'];

      if (requestId == null || senderId == null || requestPhrase == null) {
        print('🔑 KeyExchangeRequestProvider: Invalid request data');

        // Show error message to user
        UIService().showSnack(
          'Invalid key exchange request data received.',
        );

        return;
      }

      // Handle timestamp conversion safely
      DateTime timestamp;
      if (timestampRaw is int) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(timestampRaw);
      } else if (timestampRaw is String) {
        try {
          timestamp =
              DateTime.fromMillisecondsSinceEpoch(int.parse(timestampRaw));
        } catch (e) {
          print(
              '🔑 KeyExchangeRequestProvider: Invalid timestamp string: $timestampRaw, using current time');
          timestamp = DateTime.now();
        }
      } else {
        print(
            '🔑 KeyExchangeRequestProvider: Invalid timestamp type: ${timestampRaw.runtimeType}, using current time');
        timestamp = DateTime.now();
      }

      // Check if we already have this request
      if (_receivedRequests.any((req) => req.id == requestId)) {
        print('🔑 KeyExchangeRequestProvider: Request already processed');
        return;
      }

      // Store the sender's public key for future encryption
      // Handle both old (snake_case) and new (camelCase) field names
      final senderPublicKey =
          data['publicKey'] as String? ?? data['sender_public_key'] as String?;
      if (senderPublicKey != null) {
        print(
            '🔑 KeyExchangeRequestProvider: Storing sender public key for: $senderId');
        await EncryptionService.storeRecipientPublicKey(
            senderId, senderPublicKey);
        print(
            '🔑 KeyExchangeRequestProvider: ✅ Public key stored successfully');
      } else {
        print(
            '🔑 KeyExchangeRequestProvider: ❌ No public key found in request data');
        print(
            '🔑 KeyExchangeRequestProvider: 🔍 Available fields: ${data.keys.toList()}');
        print(
            '🔑 KeyExchangeRequestProvider: 🔍 publicKey field: ${data['publicKey']}');
        print(
            '🔑 KeyExchangeRequestProvider: 🔍 sender_public_key field: ${data['sender_public_key']}');
      }

      // Create the received request
      final request = KeyExchangeRequest(
        id: requestId,
        fromSessionId: senderId,
        toSessionId: SeSessionService().currentSessionId ?? '',
        requestPhrase: requestPhrase,
        status: 'received',
        timestamp: timestamp,
        type: 'key_exchange_request',
        version:
            data['version']?.toString(), // Store the version from the request
      );

      _receivedRequests.add(request);
      notifyListeners();

      // Notify about new items for badge indicators
      _notifyNewItems();

      // Add notification item for received request
      await _addNotificationItem(
        'Key Exchange Request Received',
        'New key exchange request received',
        'key_exchange_request',
        {
          'request_id': request.id,
          'sender_id': senderId,
          'request_phrase': requestPhrase,
          'timestamp': request.timestamp.millisecondsSinceEpoch,
        },
      );

      // Save to local storage for persistence
      await _saveReceivedRequest(request);

      print(
          '🔑 KeyExchangeRequestProvider: ✅ Received key exchange request processed');
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error processing received request: $e');
    }
  }

  /// Accept a key exchange request
  Future<bool> acceptKeyExchangeRequest(String requestId) async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: Accepting key exchange request: $requestId');

      final request =
          _receivedRequests.firstWhere((req) => req.id == requestId);
      if (request.status != 'received') {
        print(
            '🔑 KeyExchangeRequestProvider: Request is not in received status');
        return false;
      }

      // Update status to processing
      request.status = 'processing';
      notifyListeners();

      // Save the updated status to local storage
      await _saveReceivedRequest(request);

      // Send acceptance notification
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) return false;

      // Get Bob's (acceptor's) public key to include in the notification
      final currentSession = SeSessionService().currentSession;
      final bobPublicKey = currentSession?.publicKey;

      if (bobPublicKey == null) {
        print(
            '🔑 KeyExchangeRequestProvider: ❌ Current session public key not available');
        return false;
      }

      // Get the version from the original request if available
      final requestVersion = request.version ?? '1';

      final success = await SeSocketService().sendKeyExchangeResponse(
        recipientId: request.fromSessionId,
        accepted: true,
        responseData: {
          'type': 'key_exchange_accepted', // Include response type
          'publicKey':
              bobPublicKey, // Must match what sendKeyExchangeResponse expects
          'requestVersion': requestVersion,
          'responseId':
              GuidGenerator.generateGuid(), // Generate a unique response ID
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );

      if (success) {
        print(
            '🔑 KeyExchangeRequestProvider: ✅ Key exchange request accepted successfully');

        // Mark the request as accepted
        request.status = 'accepted';
        request.respondedAt = DateTime.now();
        notifyListeners();

        // Save the final status
        await _saveReceivedRequest(request);

        // Add notification item for accepted request (recipient's perspective)
        await _addNotificationItem(
          'Key Exchange Accepted',
          'You accepted a key exchange request from ${request.fromSessionId.substring(0, 18)}...',
          'key_exchange_accepted',
          {
            'request_id': requestId,
            'recipient_id': currentUserId,
            'sender_id': request.fromSessionId,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        );

        return true;
      } else {
        print(
            '🔑 KeyExchangeRequestProvider: ❌ Failed to send acceptance notification');
        // Reset status to received to allow retry
        request.status = 'received';
        request.respondedAt = null;
        notifyListeners();

        // Save the reset status
        await _saveReceivedRequest(request);

        return false;
      }
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error accepting key exchange request: $e');
      // Reset status to received on error to allow retry
      try {
        final request =
            _receivedRequests.firstWhere((req) => req.id == requestId);
        request.status = 'received';
        request.respondedAt = null;
        notifyListeners();

        // Save the reset status
        await _saveReceivedRequest(request);
      } catch (revertError) {
        print(
            '🔑 KeyExchangeRequestProvider: Error reverting status: $revertError');
      }
      return false;
    }
  }

  /// Decline a key exchange request
  Future<bool> declineKeyExchangeRequest(String requestId) async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: Declining key exchange request: $requestId');

      final request =
          _receivedRequests.firstWhere((req) => req.id == requestId);
      if (request.status != 'received') {
        print(
            '🔑 KeyExchangeRequestProvider: Request is not in received status');
        return false;
      }

      // Update status to processing
      request.status = 'processing';
      notifyListeners();

      // Save the updated status to local storage
      await _saveReceivedRequest(request);

      // Send decline notification
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) return false;

      // Get the version from the original request if available
      final requestVersion = request.version ?? '1';

      final success = await SeSocketService().sendKeyExchangeResponse(
        recipientId: request.fromSessionId,
        accepted: false,
        responseData: {
          'type': 'key_exchange_declined', // Include response type
          'publicKey': '', // Empty for declined requests
          'requestVersion': requestVersion,
          'responseId':
              GuidGenerator.generateGuid(), // Generate a unique response ID
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );

      if (success) {
        print(
            '🔑 KeyExchangeRequestProvider: ✅ Key exchange request declined successfully');

        // Mark the request as declined
        request.status = 'declined';
        request.respondedAt = DateTime.now();
        notifyListeners();

        // Save the final status
        await _saveReceivedRequest(request);

        // Add notification item for declined request (recipient's perspective)
        await _addNotificationItem(
          'Key Exchange Declined',
          'You declined a key exchange request from ${request.fromSessionId.substring(0, 18)}...',
          'key_exchange_declined',
          {
            'request_id': requestId,
            'recipient_id': currentUserId,
            'sender_id': request.fromSessionId,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        );

        return true;
      } else {
        print(
            '🔑 KeyExchangeRequestProvider: ❌ Failed to send decline notification');
        // Reset status to received to allow retry
        request.status = 'received';
        request.respondedAt = null;
        notifyListeners();

        // Save the reset status
        await _saveReceivedRequest(request);

        return false;
      }
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error declining key exchange request: $e');
      // Reset status to received on error to allow retry
      try {
        final request =
            _receivedRequests.firstWhere((req) => req.id == requestId);
        request.status = 'received';
        request.respondedAt = null;
        notifyListeners();

        // Save the reset status
        await _saveReceivedRequest(request);
      } catch (revertError) {
        print(
            '🔑 KeyExchangeRequestProvider: Error reverting status: $revertError');
      }
      return false;
    }
  }

  /// Mark a key exchange request as failed
  Future<void> markRequestAsFailed(String requestId) async {
    try {
      final request =
          _receivedRequests.firstWhere((req) => req.id == requestId);
      request.status = 'failed';
      request.respondedAt = DateTime.now();
      notifyListeners();

      // Save the failed status
      await _saveReceivedRequest(request);

      // Add notification item for failed request
      await _addNotificationItem(
        'Key Exchange Failed',
        'Key exchange request failed',
        'key_exchange_failed',
        {
          'request_id': requestId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );

      print('🔑 KeyExchangeRequestProvider: ✅ Request marked as failed');
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error marking request as failed: $e');
    }
  }

  /// Retry a failed key exchange request
  Future<bool> retryKeyExchangeRequest(String requestId) async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: Retrying key exchange request: $requestId');

      final request =
          _receivedRequests.firstWhere((req) => req.id == requestId);

      // Reset status to received to allow retry
      request.status = 'received';
      request.respondedAt = null;
      notifyListeners();

      // Save the reset status
      await _saveReceivedRequest(request);

      // Add notification item for retry
      await _addNotificationItem(
        'Key Exchange Retry',
        'Key exchange request reset for retry',
        'key_exchange_retry',
        {
          'request_id': requestId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );

      print('🔑 KeyExchangeRequestProvider: ✅ Request reset for retry');
      return true;
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error retrying key exchange request: $e');
      return false;
    }
  }

  /// Resend a key exchange request (for sent requests)
  Future<bool> resendKeyExchangeRequest(String requestId) async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: Resending key exchange request: $requestId');

      // Find the request in sent requests
      final requestIndex =
          _sentRequests.indexWhere((req) => req.id == requestId);
      if (requestIndex == -1) {
        print(
            '🔑 KeyExchangeRequestProvider: ❌ Sent request not found: $requestId');
        return false;
      }

      final request = _sentRequests[requestIndex];

      // Resend via KeyExchangeService
      final success =
          await KeyExchangeService.instance.resendKeyExchangeRequest(
        request.toSessionId,
        requestPhrase: request.requestPhrase,
      );

      if (success) {
        // Create updated request with new status and timestamp
        final updatedRequest = request.copyWith(
          status: 'sent',
          timestamp: DateTime.now(),
        );

        // Replace the old request in the list
        _sentRequests[requestIndex] = updatedRequest;
        notifyListeners();

        // Save updated request to storage
        await _saveUpdatedRequest(updatedRequest);

        // Add notification item
        _addNotificationItem(
          'Key Exchange Request Resent',
          'Request resent successfully',
          'key_exchange_resent',
          {
            'request_id': requestId,
            'recipient_id': request.toSessionId,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        );

        print('🔑 KeyExchangeRequestProvider: ✅ Request resent successfully');
        return true;
      } else {
        print('🔑 KeyExchangeRequestProvider: ❌ Failed to resend request');
        return false;
      }
    } catch (e) {
      print('🔑 KeyExchangeRequestProvider: Error resending request: $e');
      return false;
    }
  }

  /// Process key exchange acceptance notification
  Future<void> processKeyExchangeAccepted(Map<String, dynamic> data) async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: Processing key exchange acceptance');

      final requestId = data['request_id'] as String?;
      final recipientId = data['recipient_id'] as String?;
      final acceptorPublicKey = data['acceptor_public_key'] as String?;

      if (requestId == null || recipientId == null) {
        print('🔑 KeyExchangeRequestProvider: Invalid acceptance data');
        return;
      }

      // Check if we received the acceptor's public key
      if (acceptorPublicKey == null) {
        print(
            '🔑 KeyExchangeRequestProvider: ❌ Acceptor public key not included in acceptance notification');
        print(
            '🔑 KeyExchangeRequestProvider: Falling back to old retry mechanism');

        // Fall back to the old retry mechanism for backward compatibility
        await _processKeyExchangeAcceptedLegacy(data);
        return;
      }

      print(
          '🔑 KeyExchangeRequestProvider: ✅ Received acceptor public key, storing it immediately');

      // Store the acceptor's public key immediately
      await _storeAcceptorPublicKey(recipientId, acceptorPublicKey);

      print(
          '🔑 KeyExchangeRequestProvider: Looking for sent request with ID: $requestId');
      print(
          '🔑 KeyExchangeRequestProvider: Current sent requests count: ${_sentRequests.length}');

      // Check if the request exists in sent requests
      final requestIndex =
          _sentRequests.indexWhere((req) => req.id == requestId);

      if (requestIndex == -1) {
        print(
            '🔑 KeyExchangeRequestProvider: Request $requestId not found in sent requests');
        print(
            '🔑 KeyExchangeRequestProvider: Available sent request IDs: ${_sentRequests.map((req) => req.id).toList()}');

        // Try to find the request in storage and add it if it exists
        await _loadAndAddMissingSentRequest(requestId, recipientId);
        return;
      }

      // Update the found request
      final request = _sentRequests[requestIndex];
      request.status = 'accepted';
      request.respondedAt = DateTime.now();
      notifyListeners();

      // Save the updated request to storage
      await _saveSentRequest(request);

      print(
          '🔑 KeyExchangeRequestProvider: ✅ Key exchange request marked as accepted');

      // Now we can immediately send encrypted user data since we have Bob's public key!
      print(
          '🔑 KeyExchangeRequestProvider: Acceptor public key stored, sending encrypted user data immediately');
      await _sendEncryptedUserData(recipientId);
    } catch (e) {
      print('🔑 KeyExchangeRequestProvider: Error processing acceptance: $e');
      print(
          '🔑 KeyExchangeRequestProvider: Stack trace: ${StackTrace.current}');
    }
  }

  /// Process key exchange declined notification
  Future<void> processKeyExchangeDeclined(Map<String, dynamic> data) async {
    try {
      print('🔑 KeyExchangeRequestProvider: Processing key exchange decline');

      final requestId = data['request_id'] as String?;
      final recipientId = data['recipient_id'] as String?;

      if (requestId == null || recipientId == null) {
        print('🔑 KeyExchangeRequestProvider: Invalid decline data');
        return;
      }

      print(
          '🔑 KeyExchangeRequestProvider: Looking for sent request with ID: $requestId');

      // Check if the request exists in sent requests
      final requestIndex =
          _sentRequests.indexWhere((req) => req.id == requestId);

      if (requestIndex == -1) {
        print(
            '🔑 KeyExchangeRequestProvider: Request $requestId not found in sent requests');
        return;
      }

      // Update the found request
      final request = _sentRequests[requestIndex];
      request.status = 'declined';
      request.respondedAt = DateTime.now();
      notifyListeners();

      // Save the updated request to storage
      await _saveSentRequest(request);

      print(
          '🔑 KeyExchangeRequestProvider: ✅ Key exchange request marked as declined');

      // Add notification item for declined request
      _addNotificationItem(
        'Key Exchange Declined',
        'Your key exchange request was declined',
        'key_exchange_declined',
        {
          'request_id': requestId,
          'recipient_id': recipientId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (e) {
      print('🔑 KeyExchangeRequestProvider: Error processing decline: $e');
    }
  }

  /// Load and add a missing sent request from storage
  Future<void> _loadAndAddMissingSentRequest(
      String requestId, String recipientId) async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: Attempting to load missing sent request from storage');

      final prefsService = SeSharedPreferenceService();
      final savedRequests =
          await prefsService.getJsonList('key_exchange_requests') ?? [];

      // Look for the request in saved data
      Map<String, dynamic>? savedRequestData;
      try {
        savedRequestData = savedRequests.firstWhere(
          (req) =>
              req['id'] == requestId &&
              req['fromSessionId'] == SeSessionService().currentSessionId,
        );
      } catch (e) {
        print(
            '🔑 KeyExchangeRequestProvider: Request $requestId not found in storage');
        savedRequestData = null;
      }

      if (savedRequestData != null) {
        print(
            '🔑 KeyExchangeRequestProvider: Found missing request in storage, adding to sent requests');

        try {
          final request = KeyExchangeRequest.fromJson(savedRequestData);
          request.status = 'accepted';
          request.respondedAt = DateTime.now();

          _sentRequests.add(request);
          notifyListeners();

          // Save the updated request
          await _saveSentRequest(request);

          print(
              '🔑 KeyExchangeRequestProvider: ✅ Missing sent request loaded and marked as accepted');

          // Don't immediately send encrypted user data - wait for key exchange to complete
          print(
              '🔑 KeyExchangeRequestProvider: Key exchange accepted, waiting for public key to be available...');

          // Schedule a check for when the key exchange is actually complete
          _scheduleKeyExchangeCompletionCheck(recipientId);
        } catch (parseError) {
          print(
              '🔑 KeyExchangeRequestProvider: Error parsing saved request: $parseError');
        }
      } else {
        print(
            '🔑 KeyExchangeRequestProvider: Request $requestId not found in storage either');
        print(
            '🔑 KeyExchangeRequestProvider: This might be a new request or storage issue');
      }
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error loading missing sent request: $e');
    }
  }

  /// Load and add a missing sent request from storage for decline
  Future<void> _loadAndAddMissingSentRequestForDecline(
      String requestId, String recipientId) async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: Attempting to load missing sent request for decline from storage');

      final prefsService = SeSharedPreferenceService();
      final savedRequests =
          await prefsService.getJsonList('key_exchange_requests') ?? [];

      // Look for the request in saved data
      Map<String, dynamic>? savedRequestData;
      try {
        savedRequestData = savedRequests.firstWhere(
          (req) =>
              req['id'] == requestId &&
              req['fromSessionId'] == SeSessionService().currentSessionId,
        );
      } catch (e) {
        print(
            '🔑 KeyExchangeRequestProvider: Request $requestId not found in storage');
        savedRequestData = null;
      }

      if (savedRequestData != null) {
        print(
            '🔑 KeyExchangeRequestProvider: Found missing request in storage, adding to sent requests as declined');

        try {
          final request = KeyExchangeRequest.fromJson(savedRequestData);
          request.status = 'declined';
          request.respondedAt = DateTime.now();

          _sentRequests.add(request);
          notifyListeners();

          // Save the updated request
          await _saveSentRequest(request);

          print(
              '🔑 KeyExchangeRequestProvider: ✅ Missing sent request loaded and marked as declined');
        } catch (parseError) {
          print(
              '🔑 KeyExchangeRequestProvider: Error parsing saved request: $parseError');
        }
      } else {
        print(
            '🔑 KeyExchangeRequestProvider: Request $requestId not found in storage either');
        print(
            '🔑 KeyExchangeRequestProvider: This might be a new request or storage issue');
      }
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error loading missing sent request for decline: $e');
    }
  }

  /// Check if a key exchange is actually complete for a user
  Future<bool> _isKeyExchangeComplete(String userId) async {
    try {
      // Check if we have the public key
      final hasPublicKey =
          await KeyExchangeService.instance.hasPublicKeyForUser(userId);

      if (hasPublicKey) {
        print(
            '🔑 KeyExchangeRequestProvider: Key exchange complete for $userId - public key available');
        return true;
      }

      print(
          '🔑 KeyExchangeRequestProvider: Key exchange not complete for $userId - public key not available');
      return false;
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error checking key exchange status: $e');
      return false;
    }
  }

  /// Send encrypted user data to the recipient after key exchange acceptance
  Future<void> _sendEncryptedUserData(String recipientId) async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: Sending encrypted user data to: $recipientId');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) return;

      // First check if the key exchange is actually complete
      final isComplete = await _isKeyExchangeComplete(recipientId);
      if (!isComplete) {
        print(
            '🔑 KeyExchangeRequestProvider: Key exchange not complete yet, will retry later');
        print(
            '🔑 KeyExchangeRequestProvider: This is normal for newly accepted key exchanges');

        // Schedule a retry after a longer delay to allow key exchange to complete
        _scheduleEncryptedDataRetry(recipientId, currentUserId);
        return;
      }

      // Create user data payload
      final userData = {
        'type': 'user_data_exchange',
        'sender_id': currentUserId,
        'display_name': _getCurrentUserDisplayName(), // Get actual display name
        'profile_data': {
          'session_id': currentUserId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      };

      // Encrypt the data
      final encryptedPayload = await EncryptionService.createEncryptedPayload(
        userData,
        recipientId,
      );

      // Debug: Log the encrypted payload structure
      print('🔑 KeyExchangeRequestProvider: Encrypted payload created:');
      print(
          '🔑 KeyExchangeRequestProvider: - Payload keys: ${encryptedPayload.keys.toList()}');
      print(
          '🔑 KeyExchangeRequestProvider: - Data field length: ${(encryptedPayload['data'] as String).length}');

      // Safe substring operation - only take up to the actual length
      final dataField = encryptedPayload['data'] as String;
      final previewLength = dataField.length > 50 ? 50 : dataField.length;
      print(
          '🔑 KeyExchangeRequestProvider: - Data field preview: ${dataField.substring(0, previewLength)}...');
      print(
          '🔑 KeyExchangeRequestProvider: - Checksum: ${encryptedPayload['checksum']}');

      // Send encrypted data via socket service
      final success = await SeSocketService().sendMessage(
        recipientId: recipientId,
        message: 'Encrypted user data received',
        conversationId: 'key_exchange_$recipientId',
        messageId: 'user_data_${DateTime.now().millisecondsSinceEpoch}',
        metadata: {
          'encryptedData': encryptedPayload['data'] as String,
          'type': 'user_data_exchange',
          'encrypted': true,
          'checksum': encryptedPayload['checksum'] as String,
        },
      );

      if (success) {
        print(
            '🔑 KeyExchangeRequestProvider: ✅ Encrypted user data sent successfully');

        // Add notification item for user data sent
        _addNotificationItem(
          'Secure Connection Established',
          'Encrypted user data sent successfully',
          'user_data_exchange',
          {
            'recipient_id': recipientId,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        );
      } else {
        print(
            '🔑 KeyExchangeRequestProvider: ❌ Failed to send encrypted user data');
      }
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error sending encrypted user data: $e');

      // If it's a key missing error, schedule a retry
      if (e.toString().contains('Recipient public key not found')) {
        print(
            '🔑 KeyExchangeRequestProvider: Scheduling retry for encrypted data due to missing key');
        final currentUserId = SeSessionService().currentSessionId;
        if (currentUserId != null) {
          _scheduleEncryptedDataRetry(recipientId, currentUserId);
        }
      }
    }
  }

  /// Schedule a retry for sending encrypted user data
  void _scheduleEncryptedDataRetry(String recipientId, String currentUserId) {
    // Retry after 10 seconds to allow key exchange to complete
    // Key exchanges can take time to propagate and store keys
    Future.delayed(const Duration(seconds: 10), () async {
      try {
        print(
            '🔑 KeyExchangeRequestProvider: Retrying encrypted user data send to: $recipientId');

        // Check if the key exchange is now complete
        final isComplete = await _isKeyExchangeComplete(recipientId);

        if (isComplete) {
          print(
              '🔑 KeyExchangeRequestProvider: Key exchange now complete, retrying encrypted data send');
          await _sendEncryptedUserData(recipientId);
        } else {
          print(
              '🔑 KeyExchangeRequestProvider: Key exchange still not complete, will retry again later');
          print(
              '🔑 KeyExchangeRequestProvider: Key exchange may still be in progress');

          // Schedule another retry after 30 seconds for the second attempt
          Future.delayed(const Duration(seconds: 30), () {
            _scheduleEncryptedDataRetry(recipientId, currentUserId);
          });
        }
      } catch (e) {
        print('🔑 KeyExchangeRequestProvider: Error during retry attempt: $e');

        // Schedule another retry after 30 seconds even if there's an error
        Future.delayed(const Duration(seconds: 30), () {
          _scheduleEncryptedDataRetry(recipientId, currentUserId);
        });
      }
    });
  }

  /// Schedule a check for when the key exchange is actually complete
  void _scheduleKeyExchangeCompletionCheck(String recipientId,
      [int attemptCount = 0]) async {
    // Limit retry attempts to prevent infinite loops
    if (attemptCount >= 12) {
      // 12 attempts * 5 seconds = 1 minute
      print(
          '🔑 KeyExchangeRequestProvider: Key exchange completion check limit reached for $recipientId');
      print(
          '🔑 KeyExchangeRequestProvider: The key exchange may not have completed properly');

      // Log the current state for debugging
      await _logKeyExchangeState(recipientId);
      return;
    }

    // Schedule a check after a short delay to allow the key exchange to propagate
    Future.delayed(const Duration(seconds: 5), () async {
      try {
        print(
            '🔑 KeyExchangeRequestProvider: Checking if key exchange is complete for: $recipientId (attempt ${attemptCount + 1}/12)');

        // Check if we have the recipient's public key
        final hasPublicKey =
            await KeyExchangeService.instance.hasPublicKeyForUser(recipientId);

        if (hasPublicKey) {
          print(
              '🔑 KeyExchangeRequestProvider: Key exchange now complete, sending encrypted user data to: $recipientId');
          await _sendEncryptedUserData(recipientId);
        } else {
          print(
              '🔑 KeyExchangeRequestProvider: Key exchange still not complete, will check again in 5 seconds');
          print(
              '🔑 KeyExchangeRequestProvider: Note: The recipient may need to complete their side of the key exchange first');

          // Log the current state for debugging
          await _logKeyExchangeState(recipientId);

          // Schedule another check with incremented attempt count
          _scheduleKeyExchangeCompletionCheck(recipientId, attemptCount + 1);
        }
      } catch (e) {
        print(
            '🔑 KeyExchangeRequestProvider: Error during key exchange completion check: $e');
        // Schedule another check even if there's an error
        _scheduleKeyExchangeCompletionCheck(recipientId, attemptCount + 1);
      }
    });
  }

  /// Log the current key exchange state for debugging
  Future<void> _logKeyExchangeState(String recipientId) async {
    try {
      print('🔑 KeyExchangeRequestProvider: === Key Exchange State Debug ===');
      print('🔑 KeyExchangeRequestProvider: Recipient ID: $recipientId');

      // Check if we have a public key
      final hasPublicKey =
          await KeyExchangeService.instance.hasPublicKeyForUser(recipientId);
      print('🔑 KeyExchangeRequestProvider: Has public key: $hasPublicKey');

      // Check if we have any sent requests to this recipient
      final sentRequests =
          _sentRequests.where((req) => req.toSessionId == recipientId).toList();
      print(
          '🔑 KeyExchangeRequestProvider: Sent requests to recipient: ${sentRequests.length}');

      for (final request in sentRequests) {
        print(
            '🔑 KeyExchangeRequestProvider: - Request ${request.id}: ${request.status}');
      }

      // Check if we have any received requests from this recipient
      final receivedRequests = _receivedRequests
          .where((req) => req.fromSessionId == recipientId)
          .toList();
      print(
          '🔑 KeyExchangeRequestProvider: Received requests from recipient: ${receivedRequests.length}');

      for (final request in receivedRequests) {
        print(
            '🔑 KeyExchangeRequestProvider: - Request ${request.id}: ${request.status}');
      }

      print('🔑 KeyExchangeRequestProvider: === End Debug ===');
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error logging key exchange state: $e');
    }
  }

  /// Save sent request to local storage
  Future<void> _saveSentRequest(KeyExchangeRequest request) async {
    try {
      final prefsService = SeSharedPreferenceService();
      final existingRequests =
          await prefsService.getJsonList('key_exchange_sent_requests') ?? [];

      // Check if request already exists
      if (!existingRequests.any((req) => req['id'] == request.id)) {
        existingRequests.add(request.toJson());
        await prefsService.setJsonList(
            'key_exchange_sent_requests', existingRequests);
        print(
            '🔑 KeyExchangeRequestProvider: ✅ Sent request saved to local storage');
      } else {
        // Update existing request
        final index =
            existingRequests.indexWhere((req) => req['id'] == request.id);
        if (index != -1) {
          existingRequests[index] = request.toJson();
          await prefsService.setJsonList(
              'key_exchange_sent_requests', existingRequests);
          print(
              '🔑 KeyExchangeRequestProvider: ✅ Sent request updated in local storage');
        }
      }
    } catch (e) {
      print('🔑 KeyExchangeRequestProvider: Error saving sent request: $e');
    }
  }

  /// Save received request to local storage
  Future<void> _saveReceivedRequest(KeyExchangeRequest request) async {
    try {
      final prefsService = SeSharedPreferenceService();
      final existingRequests =
          await prefsService.getJsonList('key_exchange_received_requests') ??
              [];

      // Check if request already exists
      if (!existingRequests.any((req) => req['id'] == request.id)) {
        existingRequests.add(request.toJson());
        await prefsService.setJsonList(
            'key_exchange_received_requests', existingRequests);
        print(
            '🔑 KeyExchangeRequestProvider: ✅ Received request saved to local storage');
      } else {
        // Update existing request
        final index =
            existingRequests.indexWhere((req) => req['id'] == request.id);
        if (index != -1) {
          existingRequests[index] = request.toJson();
          await prefsService.setJsonList(
              'key_exchange_received_requests', existingRequests);
          print(
              '🔑 KeyExchangeRequestProvider: ✅ Received request updated in local storage');
        }
      }
    } catch (e) {
      print('🔑 KeyExchangeRequestProvider: Error saving received request: $e');
    }
  }

  /// Save updated request to local storage
  Future<void> _saveUpdatedRequest(KeyExchangeRequest request) async {
    try {
      final prefsService = SeSharedPreferenceService();

      // Determine which storage to update based on request type
      String storageKey;
      if (request.fromSessionId == SeSessionService().currentSessionId) {
        storageKey = 'key_exchange_sent_requests';
      } else {
        storageKey = 'key_exchange_received_requests';
      }

      final existingRequests = await prefsService.getJsonList(storageKey) ?? [];

      // Find and update existing request
      final index =
          existingRequests.indexWhere((req) => req['id'] == request.id);
      if (index != -1) {
        existingRequests[index] = request.toJson();
        await prefsService.setJsonList(storageKey, existingRequests);
        print(
            '🔑 KeyExchangeRequestProvider: ✅ Request updated in local storage');
      } else {
        print(
            '🔑 KeyExchangeRequestProvider: Request not found in storage for update');
      }
    } catch (e) {
      print('🔑 KeyExchangeRequestProvider: Error updating request: $e');
    }
  }

  /// Load saved requests from local storage
  Future<void> _loadSavedRequests() async {
    try {
      final prefsService = SeSharedPreferenceService();

      // Load sent requests
      final sentRequestsJson =
          await prefsService.getJsonList('key_exchange_sent_requests') ?? [];
      final receivedRequestsJson =
          await prefsService.getJsonList('key_exchange_received_requests') ??
              [];

      // Clear existing lists before reloading
      _sentRequests.clear();
      _receivedRequests.clear();

      // Load sent requests
      for (final requestJson in sentRequestsJson) {
        try {
          final request = KeyExchangeRequest.fromJson(requestJson);
          if (!_sentRequests.any((req) => req.id == request.id)) {
            _sentRequests.add(request);
          }
        } catch (e) {
          print(
              '🔑 KeyExchangeRequestProvider: Error parsing saved sent request: $e');
        }
      }

      // Load received requests
      for (final requestJson in receivedRequestsJson) {
        try {
          final request = KeyExchangeRequest.fromJson(requestJson);
          if (!_receivedRequests.any((req) => req.id == request.id)) {
            _receivedRequests.add(request);
          }
        } catch (e) {
          print(
              '🔑 KeyExchangeRequestProvider: Error parsing saved received request: $e');
        }
      }

      // Sort requests by timestamp (newest first)
      _sentRequests.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _receivedRequests.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      notifyListeners();
      print(
          '🔑 KeyExchangeRequestProvider: ✅ Loaded ${_sentRequests.length} sent and ${_receivedRequests.length} received requests');

      // Migrate old data format if needed
      await _migrateOldDataFormat();
    } catch (e) {
      print('🔑 KeyExchangeRequestProvider: Error loading saved requests: $e');
    }
  }

  /// Migrate old data format to new separate storage keys
  Future<void> _migrateOldDataFormat() async {
    try {
      final prefsService = SeSharedPreferenceService();

      // Check if old format exists
      final oldRequests =
          await prefsService.getJsonList('key_exchange_requests') ?? [];
      if (oldRequests.isEmpty) {
        return; // No migration needed
      }

      print('🔑 KeyExchangeRequestProvider: 🔄 Migrating old data format...');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔑 KeyExchangeRequestProvider: ❌ Cannot migrate - no current user ID');
        return;
      }

      final List<Map<String, dynamic>> newSentRequests = [];
      final List<Map<String, dynamic>> newReceivedRequests = [];

      // Separate old requests into sent and received
      for (final requestJson in oldRequests) {
        try {
          final request = KeyExchangeRequest.fromJson(requestJson);

          if (request.fromSessionId == currentUserId) {
            // This is a request we sent
            newSentRequests.add(requestJson);
          } else if (request.toSessionId == currentUserId) {
            // This is a request we received
            newReceivedRequests.add(requestJson);
          }
        } catch (e) {
          print(
              '🔑 KeyExchangeRequestProvider: Error parsing request during migration: $e');
        }
      }

      // Save to new storage format
      if (newSentRequests.isNotEmpty) {
        await prefsService.setJsonList(
            'key_exchange_sent_requests', newSentRequests);
        print(
            '🔑 KeyExchangeRequestProvider: ✅ Migrated ${newSentRequests.length} sent requests');
      }

      if (newReceivedRequests.isNotEmpty) {
        await prefsService.setJsonList(
            'key_exchange_received_requests', newReceivedRequests);
        print(
            '🔑 KeyExchangeRequestProvider: ✅ Migrated ${newReceivedRequests.length} received requests');
      }

      // Remove old data
      await prefsService.remove('key_exchange_requests');
      print(
          '🔑 KeyExchangeRequestProvider: ✅ Migration completed, old data removed');

      // Reload the data with the new format
      await _loadSavedRequests();
    } catch (e) {
      print('🔑 KeyExchangeRequestProvider: Error during data migration: $e');
    }
  }

  /// Clear all data (for testing/reset)
  void clearAllData() {
    _sentRequests.clear();
    _receivedRequests.clear();
    _pendingRequests.clear();
    notifyListeners();
  }

  /// Clear all data from storage (for testing/reset)
  Future<void> clearAllDataFromStorage() async {
    try {
      final prefsService = SeSharedPreferenceService();

      // Clear all storage keys
      await prefsService.remove('key_exchange_sent_requests');
      await prefsService.remove('key_exchange_received_requests');
      await prefsService.remove('key_exchange_requests'); // Old format
      await prefsService.remove('key_exchange_pending_requests');

      // Clear in-memory data
      clearAllData();

      print(
          '🔑 KeyExchangeRequestProvider: ✅ All data cleared from storage and memory');
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error clearing data from storage: $e');
    }
  }

  /// Force refresh data from storage
  Future<void> forceRefreshFromStorage() async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: 🔄 Force refreshing data from storage...');
      await _loadSavedRequests();
      print('🔑 KeyExchangeRequestProvider: ✅ Force refresh completed');
    } catch (e) {
      print('🔑 KeyExchangeRequestProvider: Error during force refresh: $e');
    }
  }

  /// Reload data when user session changes
  Future<void> reloadDataForNewSession() async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: 🔄 Reloading data for new user session...');

      // Clear current data
      _sentRequests.clear();
      _receivedRequests.clear();
      _pendingRequests.clear();

      // Load data for the new session
      await _loadSavedRequests();

      print('🔑 KeyExchangeRequestProvider: ✅ Data reloaded for new session');
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error reloading data for new session: $e');
    }
  }

  /// Store the acceptor's public key for immediate use
  Future<void> _storeAcceptorPublicKey(
      String recipientId, String publicKey) async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: Storing acceptor public key for: $recipientId');

      // Debug: Check key format and length
      final keyBytes = base64.decode(publicKey);
      print(
          '🔑 KeyExchangeRequestProvider: Key length: ${keyBytes.length} bytes (${keyBytes.length * 8} bits)');
      print(
          '🔑 KeyExchangeRequestProvider: Key format: ${publicKey.substring(0, 20)}...');

      // Validate key length for AES encryption
      if (keyBytes.length != 16 &&
          keyBytes.length != 24 &&
          keyBytes.length != 32) {
        print(
            '🔑 KeyExchangeRequestProvider: ⚠️ Warning: Key length ${keyBytes.length} bytes is not standard AES length (16/24/32 bytes)');
        print(
            '🔑 KeyExchangeRequestProvider: This may cause encryption failures');
      }

      // Store the public key using the EncryptionService
      await EncryptionService.storeRecipientPublicKey(recipientId, publicKey);

      print(
          '🔑 KeyExchangeRequestProvider: ✅ Acceptor public key stored successfully');
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: ❌ Error storing acceptor public key: $e');
      rethrow;
    }
  }

  /// Legacy fallback for when acceptor public key is not included
  Future<void> _processKeyExchangeAcceptedLegacy(
      Map<String, dynamic> data) async {
    try {
      print('🔑 KeyExchangeRequestProvider: Using legacy fallback mechanism');

      final requestId = data['request_id'] as String?;
      final recipientId = data['recipient_id'] as String?;

      if (requestId == null || recipientId == null) {
        print(
            '🔑 KeyExchangeRequestProvider: Invalid acceptance data in legacy mode');
        return;
      }

      print(
          '🔑 KeyExchangeRequestProvider: Looking for sent request with ID: $requestId');
      print(
          '🔑 KeyExchangeRequestProvider: Current sent requests count: ${_sentRequests.length}');

      // Check if the request exists in sent requests
      final requestIndex =
          _sentRequests.indexWhere((req) => req.id == requestId);

      if (requestIndex == -1) {
        print(
            '🔑 KeyExchangeRequestProvider: Request $requestId not found in sent requests');
        print(
            '🔑 KeyExchangeRequestProvider: Available sent request IDs: ${_sentRequests.map((req) => req.id).toList()}');

        // Try to find the request in storage and add it if it exists
        await _loadAndAddMissingSentRequestLegacy(requestId, recipientId);
        return;
      }

      // Update the found request
      final request = _sentRequests[requestIndex];
      request.status = 'accepted';
      request.respondedAt = DateTime.now();
      notifyListeners();

      // Save the updated request to storage
      await _saveSentRequest(request);

      print(
          '🔑 KeyExchangeRequestProvider: ✅ Key exchange request marked as accepted (legacy mode)');

      // Use the old retry mechanism
      print(
          '🔑 KeyExchangeRequestProvider: Key exchange accepted, waiting for public key to be available...');
      _scheduleKeyExchangeCompletionCheck(recipientId);
    } catch (e) {
      print('🔑 KeyExchangeRequestProvider: Error in legacy fallback: $e');
    }
  }

  /// Legacy version of loading missing sent request
  Future<void> _loadAndAddMissingSentRequestLegacy(
      String requestId, String recipientId) async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: Attempting to load missing sent request from storage (legacy mode)');

      final prefsService = SeSharedPreferenceService();
      final savedRequests =
          await prefsService.getJsonList('key_exchange_requests') ?? [];

      // Look for the request in saved data
      Map<String, dynamic>? savedRequestData;
      try {
        savedRequestData = savedRequests.firstWhere(
          (req) =>
              req['id'] == requestId &&
              req['fromSessionId'] == SeSessionService().currentSessionId,
        );
      } catch (e) {
        print(
            '🔑 KeyExchangeRequestProvider: Request $requestId not found in storage');
        savedRequestData = null;
      }

      if (savedRequestData != null) {
        print(
            '🔑 KeyExchangeRequestProvider: Found missing request in storage, adding to sent requests (legacy mode)');

        try {
          final request = KeyExchangeRequest.fromJson(savedRequestData);
          request.status = 'accepted';
          request.respondedAt = DateTime.now();

          _sentRequests.add(request);
          notifyListeners();

          // Save the updated request
          await _saveSentRequest(request);

          print(
              '🔑 KeyExchangeRequestProvider: ✅ Missing sent request loaded and marked as accepted (legacy mode)');

          // Use the old retry mechanism
          print(
              '🔑 KeyExchangeRequestProvider: Key exchange accepted, waiting for public key to be available...');
          _scheduleKeyExchangeCompletionCheck(recipientId);
        } catch (parseError) {
          print(
              '🔑 KeyExchangeRequestProvider: Error parsing saved request: $parseError');
        }
      } else {
        print(
            '🔑 KeyExchangeRequestProvider: Request $requestId not found in storage either');
        print(
            '🔑 KeyExchangeRequestProvider: This might be a new request or storage issue');
      }
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error loading missing sent request: $e');
    }
  }

  /// Get the current user's display name from their session
  String _getCurrentUserDisplayName() {
    final currentSession = SeSessionService().currentSession;
    final currentSessionId = SeSessionService().currentSessionId;
    return currentSession?.displayName ??
        'User ${currentSessionId?.substring(0, 8) ?? 'Unknown'}';
  }

  /// Get display name for a user from stored mappings
  Future<String> getDisplayNameForUser(String userId) async {
    try {
      final prefsService = SeSharedPreferenceService();
      final displayNameMappings =
          await prefsService.getJson('ker_display_names') ?? {};

      final displayName = displayNameMappings[userId];
      if (displayName != null && displayName is String) {
        return displayName;
      }

      // Fallback to session ID format if no display name found
      return 'User ${userId.substring(0, 8)}...';
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error getting display name for $userId: $e');
      return 'Unknown User';
    }
  }

  /// Check if a key exchange is completed for a user
  Future<bool> isKeyExchangeCompleted(String userId) async {
    try {
      final prefsService = SeSharedPreferenceService();
      final completedExchanges =
          await prefsService.getJson('completed_key_exchanges') ?? {};

      final exchangeData = completedExchanges[userId];
      if (exchangeData != null && exchangeData['status'] == 'complete') {
        return true;
      }

      return false;
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error checking completion status: $e');
      return false;
    }
  }

  /// Get completion data for a user (including display name)
  Future<Map<String, dynamic>?> getCompletionData(String userId) async {
    try {
      final prefsService = SeSharedPreferenceService();
      final completedExchanges =
          await prefsService.getJson('completed_key_exchanges') ?? {};

      return completedExchanges[userId];
    } catch (e) {
      print('🔑 KeyExchangeRequestProvider: Error getting completion data: $e');
      return null;
    }
  }

  /// Refresh UI when key exchange data is updated
  Future<void> refreshKeyExchangeData() async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: Refreshing key exchange data for UI update');

      // Reload data from storage to get latest updates
      await _loadSavedRequests();

      // Notify listeners to refresh UI
      notifyListeners();

      print(
          '🔑 KeyExchangeRequestProvider: ✅ Key exchange data refreshed, UI updated');
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error refreshing key exchange data: $e');
    }
  }

  /// Update display name for a user and refresh UI
  Future<void> updateUserDisplayName(String userId, String displayName) async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: Updating display name for $userId to: $displayName');

      // Store the display name mapping
      final prefsService = SeSharedPreferenceService();
      final displayNameMappings =
          await prefsService.getJson('ker_display_names') ?? {};
      displayNameMappings[userId] = displayName;
      await prefsService.setJson('ker_display_names', displayNameMappings);

      print('🔑 KeyExchangeRequestProvider: ✅ Display name mapping stored');

      // Update display names in all key exchange requests for this user
      bool hasUpdates = false;

      // Update sent requests
      for (final request in _sentRequests) {
        if (request.toSessionId == userId &&
            request.displayName != displayName) {
          print(
              '🔑 KeyExchangeRequestProvider: Updating sent request display name from "${request.displayName}" to "$displayName"');
          request.displayName = displayName;
          hasUpdates = true;
        }
      }

      // Update received requests
      for (final request in _receivedRequests) {
        if (request.fromSessionId == userId &&
            request.displayName != displayName) {
          print(
              '🔑 KeyExchangeRequestProvider: Updating received request display name from "${request.displayName}" to "$displayName"');
          request.displayName = displayName;
          hasUpdates = true;
        }
      }

      // Update pending requests
      for (final request in _pendingRequests) {
        if (request.fromSessionId == userId &&
            request.displayName != displayName) {
          print(
              '🔑 KeyExchangeRequestProvider: Updating pending request display name from "${request.displayName}" to "$displayName"');
          request.displayName = displayName;
          hasUpdates = true;
        }
      }

      print('🔑 KeyExchangeRequestProvider: Has updates: $hasUpdates');

      // Save updated requests to storage
      if (hasUpdates) {
        await _saveAllRequests();
        print('🔑 KeyExchangeRequestProvider: ✅ All requests saved to storage');
      }

      // Refresh the UI
      await refreshKeyExchangeData();

      print(
          '🔑 KeyExchangeRequestProvider: ✅ Display name updated and UI refreshed');
    } catch (e) {
      print('🔑 KeyExchangeRequestProvider: Error updating display name: $e');
    }
  }

  /// Save all requests to storage
  Future<void> _saveAllRequests() async {
    try {
      final prefsService = SeSharedPreferenceService();

      // Save sent requests
      final sentRequestsJson =
          _sentRequests.map((req) => req.toJson()).toList();
      await prefsService.setJsonList(
          'key_exchange_sent_requests', sentRequestsJson);

      // Save received requests
      final receivedRequestsJson =
          _receivedRequests.map((req) => req.toJson()).toList();
      await prefsService.setJsonList(
          'key_exchange_received_requests', receivedRequestsJson);

      // Save pending requests
      final pendingRequestsJson =
          _pendingRequests.map((req) => req.toJson()).toList();
      await prefsService.setJsonList(
          'key_exchange_pending_requests', pendingRequestsJson);

      print('🔑 KeyExchangeRequestProvider: ✅ All requests saved to storage');
    } catch (e) {
      print('🔑 KeyExchangeRequestProvider: Error saving all requests: $e');
    }
  }

  /// Delete/revoke a sent key exchange request
  Future<bool> deleteSentRequest(String requestId) async {
    try {
      print('🔑 KeyExchangeRequestProvider: Deleting sent request: $requestId');

      // Find the request
      final requestIndex =
          _sentRequests.indexWhere((req) => req.id == requestId);
      if (requestIndex == -1) {
        print(
            '🔑 KeyExchangeRequestProvider: ❌ Sent request not found: $requestId');
        return false;
      }

      final request = _sentRequests[requestIndex];

      // Notify the server that the request is revoked (if it was sent)
      if (request.status == 'sent' || request.status == 'pending') {
        try {
          await SeSocketService().revokeKeyExchangeRequest(
            recipientId: request.toSessionId,
            requestId: requestId,
          );
          print(
              '🔑 KeyExchangeRequestProvider: ✅ Revoke notification sent to server');
        } catch (e) {
          print(
              '🔑 KeyExchangeRequestProvider: ⚠️ Failed to notify server about revocation: $e');
        }
      }

      // Remove from local list
      _sentRequests.removeAt(requestIndex);
      notifyListeners();

      // Remove from storage
      await _removeSentRequestFromStorage(requestId);

      // Note: Pending exchange cleanup is handled by KeyExchangeService internally

      print(
          '🔑 KeyExchangeRequestProvider: ✅ Sent request deleted successfully');
      return true;
    } catch (e) {
      print('🔑 KeyExchangeRequestProvider: Error deleting sent request: $e');
      return false;
    }
  }

  /// Delete a received key exchange request
  Future<bool> deleteReceivedRequest(String requestId) async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: Deleting received request: $requestId');

      // Find the request
      final requestIndex =
          _receivedRequests.indexWhere((req) => req.id == requestId);
      if (requestIndex == -1) {
        print(
            '🔑 KeyExchangeRequestProvider: ❌ Received request not found: $requestId');
        return false;
      }

      final request = _receivedRequests[requestIndex];

      // Remove from local list
      _receivedRequests.removeAt(requestIndex);
      notifyListeners();

      // Remove from storage
      await _removeReceivedRequestFromStorage(requestId);

      print(
          '🔑 KeyExchangeRequestProvider: ✅ Received request deleted successfully');
      return true;
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error deleting received request: $e');
      return false;
    }
  }

  /// Remove sent request from storage
  Future<void> _removeSentRequestFromStorage(String requestId) async {
    try {
      final prefsService = SeSharedPreferenceService();
      final existingRequests =
          await prefsService.getJsonList('key_exchange_sent_requests') ?? [];

      final updatedRequests =
          existingRequests.where((req) => req['id'] != requestId).toList();
      await prefsService.setJsonList(
          'key_exchange_sent_requests', updatedRequests);

      print(
          '🔑 KeyExchangeRequestProvider: ✅ Sent request removed from storage');
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error removing sent request from storage: $e');
    }
  }

  /// Remove received request from storage
  Future<void> _removeReceivedRequestFromStorage(String requestId) async {
    try {
      final prefsService = SeSharedPreferenceService();
      final existingRequests =
          await prefsService.getJsonList('key_exchange_received_requests') ??
              [];

      final updatedRequests =
          existingRequests.where((req) => req['id'] != requestId).toList();
      await prefsService.setJsonList(
          'key_exchange_received_requests', updatedRequests);

      print(
          '🔑 KeyExchangeRequestProvider: ✅ Received request removed from storage');
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error removing received request from storage: $e');
    }
  }

  /// Handle key exchange request revoked by sender
  Future<void> handleRequestRevoked(String requestId, String senderId) async {
    try {
      print(
          '🔑 KeyExchangeRequestProvider: Handling revoked request: $requestId from $senderId');

      // Find and remove the received request
      final receivedIndex =
          _receivedRequests.indexWhere((req) => req.id == requestId);
      if (receivedIndex != -1) {
        _receivedRequests.removeAt(receivedIndex);
        notifyListeners();
        await _removeReceivedRequestFromStorage(requestId);
        print(
            '🔑 KeyExchangeRequestProvider: ✅ Revoked request removed from received list');
      }

      // Also check sent requests in case there was a duplicate
      final sentIndex = _sentRequests.indexWhere((req) => req.id == requestId);
      if (sentIndex != -1) {
        _sentRequests.removeAt(sentIndex);
        notifyListeners();
        await _removeSentRequestFromStorage(requestId);
        print(
            '🔑 KeyExchangeRequestProvider: ✅ Revoked request removed from sent list');
      }

      print(
          '🔑 KeyExchangeRequestProvider: ✅ Request revocation handled successfully');
    } catch (e) {
      print(
          '🔑 KeyExchangeRequestProvider: Error handling request revocation: $e');
    }
  }
}
