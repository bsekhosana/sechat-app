import 'package:flutter/foundation.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import 'package:sechat_app/core/services/encryption_service.dart';
import 'package:sechat_app/core/services/key_exchange_service.dart';
import 'package:sechat_app/core/services/se_shared_preference_service.dart';
import 'package:sechat_app/core/services/indicator_service.dart';
import 'package:sechat_app/core/services/ui_service.dart';
import 'package:sechat_app/core/utils/guid_generator.dart';
import 'package:sechat_app/core/utils/conversation_id_generator.dart';
import 'package:sechat_app//../core/utils/logger.dart';

import 'package:sechat_app/features/notifications/services/local_notification_items_service.dart';
import 'package:sechat_app/shared/models/key_exchange_request.dart';
import 'dart:convert'; // Added for base64 decoding
import 'package:flutter/material.dart'; // Added for ScaffoldMessenger

/// Provider for managing key exchange requests
class KeyExchangeRequestProvider extends ChangeNotifier {
  final List<KeyExchangeRequest> _sentRequests = [];
  final List<KeyExchangeRequest> _receivedRequests = [];
  final List<KeyExchangeRequest> _pendingRequests = [];

  final SeSocketService _socketService = SeSocketService.instance;

  /// Generate consistent conversation ID that both users will have
  /// This ensures messages appear in the same conversation for both users
  /// Updated to match server's new consistent ID format
  String _generateConsistentConversationId(String user1Id, String user2Id) {
    return ConversationIdGenerator.generateConsistentConversationId(
        user1Id, user2Id);
  }

  /// Initialize the provider and load saved requests
  Future<void> initialize() async {
    await _loadSavedRequests();

    // Clean up any duplicates that might exist
    await _cleanupDuplicates();

    _ensureNotificationServiceConnection();
  }

  /// Clean up any duplicate KER items
  Future<void> _cleanupDuplicates() async {
    Logger.debug(
        '🧹 Cleaning up duplicate KER items...', 'KeyExchangeRequestProvider');

    // Clean up sent requests - keep only the most recent for each toSessionId
    final Map<String, KeyExchangeRequest> uniqueSentRequests = {};
    for (final request in _sentRequests) {
      final existing = uniqueSentRequests[request.toSessionId];
      if (existing == null || request.timestamp.isAfter(existing.timestamp)) {
        uniqueSentRequests[request.toSessionId] = request;
      }
    }

    // Clean up received requests - keep only the most recent for each fromSessionId
    final Map<String, KeyExchangeRequest> uniqueReceivedRequests = {};
    for (final request in _receivedRequests) {
      final existing = uniqueReceivedRequests[request.fromSessionId];
      if (existing == null || request.timestamp.isAfter(existing.timestamp)) {
        uniqueReceivedRequests[request.fromSessionId] = request;
      }
    }

    // Check if we need to clean up
    final sentCountBefore = _sentRequests.length;
    final receivedCountBefore = _receivedRequests.length;

    // Clear and rebuild the lists
    _sentRequests.clear();
    _sentRequests.addAll(uniqueSentRequests.values);

    _receivedRequests.clear();
    _receivedRequests.addAll(uniqueReceivedRequests.values);

    final sentCountAfter = _sentRequests.length;
    final receivedCountAfter = _receivedRequests.length;

    if (sentCountBefore != sentCountAfter ||
        receivedCountBefore != receivedCountAfter) {
      Logger.debug('🔑 KeyExchangeRequestProvider: 🧹 Cleaned up duplicates:');
      Logger.debug('  - Sent requests: $sentCountBefore → $sentCountAfter');
      Logger.debug(
          '  - Received requests: $receivedCountBefore → $receivedCountAfter');

      // Save the cleaned up data
      await _saveAllRequests();
      notifyListeners();
    } else {
      Logger.debug('🔑 KeyExchangeRequestProvider: ✅ No duplicates found');
    }
  }

  /// Refresh the data from storage
  Future<void> refresh() async {
    Logger.debug(
        '🔑 KeyExchangeRequestProvider: 🔄 Refreshing data from storage');
    await _loadSavedRequests();

    // Clean up any duplicates that might have been created
    await _cleanupDuplicates();

    Logger.debug(
        '🔑 KeyExchangeRequestProvider: ✅ Refresh completed - sent: ${_sentRequests.length}, received: ${_receivedRequests.length}');
  }

  /// Manually clean up duplicates (can be called externally)
  Future<void> cleanupDuplicates() async {
    Logger.debug(
        '🔑 KeyExchangeRequestProvider: 🧹 Manual duplicate cleanup requested');
    await _cleanupDuplicates();
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
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: New key exchange items detected, badge counts will update automatically');
    } catch (e) {
      Logger.debug('🔑 KeyExchangeRequestProvider: Error in notification: $e');
    }
  }

  /// Ensure connection with socket service
  void _ensureNotificationServiceConnection() {
    try {
      // Connect to socket service for key exchange notifications
      // This will be handled by the main navigation screen
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Socket service connection will be handled by main navigation');

      // Set up socket event handlers for key exchange events
      _setupSocketEventHandlers();
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ❌ Failed to connect to socket service: $e');
    }
  }

  /// Setup socket event handlers
  void _setupSocketEventHandlers() {
    try {
      // ChannelSocketService uses an event-driven system instead of callbacks
      // Event listeners are set up when the service initializes
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Socket event handlers set up - using channel-based system');
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ❌ Failed to set up socket event handlers: $e');
    }
  }

  /// Send a key exchange request to another user
  Future<bool> sendKeyExchangeRequest(
    String recipientSessionId, {
    required String requestPhrase,
  }) async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Sending key exchange request to: $recipientSessionId');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        Logger.debug('🔑 KeyExchangeRequestProvider: User not logged in');

        // Show error message to user
        UIService().showSnack(
          'User not logged in. Please log in and try again.',
        );

        return false;
      }

      // Get the current user's public key
      final userSession = SeSessionService().currentSession;
      final currentUserPublicKey = userSession?.publicKey;
      if (currentUserPublicKey == null) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ❌ Current user public key not available');
        UIService().showSnack('Public key not available. Please try again.');
        return false;
      }

      // STRICT DUPLICATION GUARD: Check if we already have ANY request with this session ID
      // Check both sent and received requests to prevent any duplicates
      final existingSentRequestIndex = _sentRequests.indexWhere(
        (req) => req.toSessionId == recipientSessionId,
      );

      // Also check if we have any received request from this session
      final existingReceivedRequestIndex = _receivedRequests.indexWhere(
        (req) => req.fromSessionId == recipientSessionId,
      );

      if (existingSentRequestIndex != -1) {
        // Update existing sent request instead of creating new one
        final existingRequest = _sentRequests[existingSentRequestIndex];
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: 🔄 Updating existing SENT request with $recipientSessionId (status: ${existingRequest.status})');

        // Update the existing request with new data
        _sentRequests[existingSentRequestIndex] = KeyExchangeRequest(
          id: existingRequest.id, // Keep the same ID
          fromSessionId: currentUserId,
          toSessionId: recipientSessionId,
          requestPhrase: requestPhrase,
          status: 'pending', // Reset to pending
          timestamp: DateTime.now(), // Update timestamp
          type: 'key_exchange_request',
          version: '1',
          publicKey: currentUserPublicKey,
        );

        // Save the updated request
        await _saveSentRequest(_sentRequests[existingSentRequestIndex]);
        notifyListeners();

        // Send the updated request
        _socketService.sendKeyExchangeRequest(
          recipientId: recipientSessionId,
          publicKey: currentUserPublicKey,
          requestId: existingRequest.id, // Use existing ID
          requestPhrase: requestPhrase,
        );

        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ Updated existing SENT request and resent to $recipientSessionId');
        return true;
      }

      if (existingReceivedRequestIndex != -1) {
        // We have a received request from this session - don't allow sending
        final existingReceivedRequest =
            _receivedRequests[existingReceivedRequestIndex];
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ❌ Cannot send request to $recipientSessionId - already have RECEIVED request from them (status: ${existingReceivedRequest.status})');

        // Show error message to user
        UIService().showSnack(
          'You already have a key exchange request from this user. Please respond to it first.',
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

      // Create local notification for sent request
      try {
        final notificationService = LocalNotificationItemsService();
        await notificationService.createKerSentNotification(
          senderId: currentUserId,
          recipientId: recipientSessionId,
          requestPhrase: requestPhrase,
        );
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ Local notification created for sent KER');
      } catch (e) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ⚠️ Failed to create local notification: $e');
      }

      // Send via KeyExchangeService which handles the proper data structure
      final success = await KeyExchangeService.instance.requestKeyExchange(
        recipientSessionId,
        requestPhrase: requestPhrase,
      );

      if (success) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ Key exchange request sent successfully');

        // Update status from 'pending' to 'sent' after successful sending
        request.status = 'sent';
        notifyListeners();

        // Save to local storage for persistence
        await _saveSentRequest(request);

        return true;
      } else {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ❌ Failed to send key exchange request');

        // Remove the request from local list if sending failed
        _sentRequests.remove(request);
        notifyListeners();

        // Show error message to user
        UIService().showSnack(
          'Failed to send key exchange request. Please try again.',
          isError: true,
        );

        return false;
      }
    } catch (e) {
      Logger.debug(
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
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: 🔥 Processing received key exchange request');
      Logger.debug('🔑 KeyExchangeRequestProvider: 🔥 Request data: $data');

      // Handle both old and new data formats
      final requestId =
          data['requestId'] as String? ?? data['request_id'] as String?;
      final senderId =
          data['senderId'] as String? ?? data['sender_id'] as String?;
      final requestPhrase =
          data['requestPhrase'] as String? ?? data['request_phrase'] as String?;
      final timestampRaw = data['timestamp'];

      if (requestId == null || senderId == null || requestPhrase == null) {
        Logger.debug('🔑 KeyExchangeRequestProvider: Invalid request data');

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
          // Try parsing as ISO string first
          if (timestampRaw.contains('T') || timestampRaw.contains('Z')) {
            timestamp = DateTime.parse(timestampRaw);
          } else {
            // Try parsing as milliseconds since epoch
            timestamp =
                DateTime.fromMillisecondsSinceEpoch(int.parse(timestampRaw));
          }
        } catch (e) {
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Invalid timestamp string: $timestampRaw, using current time');
          timestamp = DateTime.now();
        }
      } else {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Invalid timestamp type: ${timestampRaw.runtimeType}, using current time');
        timestamp = DateTime.now();
      }

      // Check if we already have this request by ID
      if (_receivedRequests.any((req) => req.id == requestId)) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Request already processed');
        return;
      }

      // Store the sender's public key for future encryption
      // Handle both old (snake_case) and new (camelCase) field names
      final senderPublicKey =
          data['publicKey'] as String? ?? data['sender_public_key'] as String?;

      // STRICT DUPLICATION GUARD: Check if we already have ANY request from this sender
      // Check both received and sent requests to prevent any duplicates
      final existingReceivedRequestIndex = _receivedRequests.indexWhere(
        (req) => req.fromSessionId == senderId,
      );

      // Also check if we have any sent request to this session
      final existingSentRequestIndex = _sentRequests.indexWhere(
        (req) => req.toSessionId == senderId,
      );

      if (existingReceivedRequestIndex != -1) {
        // Update existing received request instead of creating new one
        final existingRequest = _receivedRequests[existingReceivedRequestIndex];
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: 🔄 Updating existing RECEIVED request from $senderId (status: ${existingRequest.status})');

        // Update the existing request with new data
        _receivedRequests[existingReceivedRequestIndex] = KeyExchangeRequest(
          id: requestId, // Use new request ID
          fromSessionId: senderId,
          toSessionId: SeSessionService().currentSessionId ?? '',
          requestPhrase: requestPhrase,
          status: 'received', // Reset to received
          timestamp: timestamp, // Update timestamp
          type: 'key_exchange_request',
          version: data['version']?.toString(),
          publicKey: senderPublicKey,
        );

        // Save the updated request
        await _saveReceivedRequest(
            _receivedRequests[existingReceivedRequestIndex]);
        notifyListeners();

        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ Updated existing RECEIVED request from $senderId');
        return;
      }

      if (existingSentRequestIndex != -1) {
        // We have a sent request to this session - this shouldn't happen normally
        // but if it does, we should handle it gracefully
        final existingSentRequest = _sentRequests[existingSentRequestIndex];
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ⚠️ Received request from $senderId but we already have a SENT request to them (status: ${existingSentRequest.status})');

        // For now, we'll still process the received request but log this unusual case
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: 🔄 Processing received request despite existing sent request');
      }

      if (senderPublicKey != null) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Storing sender public key for: $senderId');
        await EncryptionService.storeRecipientPublicKey(
            senderId, senderPublicKey);
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ Public key stored successfully');
      } else {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ❌ No public key found in request data');
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: 🔍 Available fields: ${data.keys.toList()}');
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: 🔍 publicKey field: ${data['publicKey']}');
        Logger.debug(
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
        publicKey: senderPublicKey, // Store the sender's public key
      );

      _receivedRequests.add(request);
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Added request to _receivedRequests list (total: ${_receivedRequests.length})');

      // Force UI update
      notifyListeners();
      Logger.debug('🔑 KeyExchangeRequestProvider: ✅ notifyListeners() called');

      // Notify about new items for badge indicators
      _notifyNewItems();

      // Create local notification for received request
      try {
        final notificationService = LocalNotificationItemsService();
        final currentUserId = SeSessionService().currentSessionId;
        if (currentUserId != null) {
          await notificationService.createKerReceivedNotification(
            senderId: senderId,
            recipientId: currentUserId,
            requestPhrase: requestPhrase,
          );
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ✅ Local notification created for received KER');
        }
      } catch (e) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ⚠️ Failed to create local notification: $e');
      }

      // Save to local storage for persistence
      await _saveReceivedRequest(request);

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Received key exchange request processed');
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error processing received request: $e');
    }
  }

  /// Accept a key exchange request
  Future<bool> acceptKeyExchangeRequest(
      KeyExchangeRequest request, BuildContext context) async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Accepting key exchange request: ${request.id}');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ❌ Current user ID is null');
        return false;
      }

      // CRITICAL: Ensure socket is connected before sending accept event
      if (!_socketService.isConnected) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ❌ Socket not connected, attempting to reconnect...');

        try {
          // Try to reconnect the socket
          await _socketService.connect(SeSessionService().currentSessionId!);

          // Wait a moment for connection to stabilize
          await Future.delayed(const Duration(milliseconds: 500));

          // Check if connection was successful
          if (!_socketService.isConnected) {
            Logger.debug(
                '🔑 KeyExchangeRequestProvider: ❌ Failed to reconnect socket');

            // Show user-friendly error message about socket connectivity
            if (context.mounted) {
              final connectionStatus =
                  _socketService.getDetailedConnectionStatus();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                          '❌ Operation failed: Socket connection issues'),
                      Text(
                          'Status: ${connectionStatus['isConnected'] ? 'Connected' : 'Disconnected'}'),
                      Text(
                          'Ready: ${connectionStatus['isReady'] ? 'Yes' : 'No'}'),
                      Text(
                          'Session: ${connectionStatus['sessionConfirmed'] ? 'Confirmed' : 'Pending'}'),
                    ],
                  ),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 8),
                  action: SnackBarAction(
                    label: 'Retry',
                    textColor: Colors.white,
                    onPressed: () => _retryConnection(context),
                  ),
                ),
              );
            }

            return false;
          }

          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ✅ Socket reconnected successfully');
        } catch (e) {
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ❌ Failed to reconnect socket: $e');

          // Show user-friendly error message about socket connectivity
          if (context.mounted) {
            final connectionStatus =
                _socketService.getDetailedConnectionStatus();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('❌ Operation failed: Socket connection issues'),
                    Text(
                        'Status: ${connectionStatus['isConnected'] ? 'Connected' : 'Disconnected'}'),
                    Text(
                        'Ready: ${connectionStatus['isReady'] ? 'Yes' : 'No'}'),
                    Text(
                        'Session: ${connectionStatus['sessionConfirmed'] ? 'Confirmed' : 'Pending'}'),
                  ],
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 8),
                action: SnackBarAction(
                  label: 'Retry',
                  textColor: Colors.white,
                  onPressed: () => _retryConnection(context),
                ),
              ),
            );
          }

          return false;
        }
      }

      // Update the request status in local storage
      await _updateReceivedRequestStatus(request.id, 'accepted');

      // CRITICAL: Prevent future KER requests from this session since they will be in contact list
      // Remove any pending requests from this sender to prevent duplicates
      _receivedRequests.removeWhere((req) =>
          req.fromSessionId == request.fromSessionId &&
          req.id != request.id &&
          (req.status == 'received' ||
              req.status == 'pending' ||
              req.status == 'processing'));

      // Also remove any sent requests to this session since they will be in contact list
      _sentRequests.removeWhere((req) =>
          req.toSessionId == request.fromSessionId &&
          (req.status == 'pending' || req.status == 'sent'));

      // Save the cleaned up requests
      await _saveAllRequests();
      notifyListeners();

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Cleaned up duplicate requests for accepted session: ${request.fromSessionId}');

      // CRITICAL: Send key exchange accept event to server (not response)
      // This triggers the server to send key_exchange:response with our public key
      Logger.debug('🔑 KeyExchangeRequestProvider: 🔍🔍🔍 ABOUT TO CALL EMIT!');
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: 🔍🔍🔍 _socketService type: ${_socketService.runtimeType}');
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: 🔍🔍🔍 _socketService connected: ${_socketService.isConnected}');

      // Get the current user's public key to include in the accept event
      final userSession = SeSessionService().currentSession;
      final currentUserPublicKey = userSession?.publicKey;

      if (currentUserPublicKey == null) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ❌ Current user public key not available');
        return false;
      }

      // CRITICAL: Store the requester's public key from the original request
      // This ensures we can encrypt data to them after accepting
      try {
        final requesterPublicKey = request.publicKey;
        if (requesterPublicKey != null && requesterPublicKey.isNotEmpty) {
          await EncryptionService.storeRecipientPublicKey(
              request.fromSessionId, requesterPublicKey);
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ✅ Stored requester public key for ${request.fromSessionId}');
        } else {
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ⚠️ Warning: No public key in request to store');
        }
      } catch (e) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ❌ Failed to store requester public key: $e');
        // Don't fail the entire accept process if key storage fails
      }

      // Double-check socket connection before sending
      if (!_socketService.isConnected) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ❌ Socket still not connected after reconnection attempt');
        return false;
      }

      // CRITICAL: Generate consistent conversation ID for both users
      final consistentConversationId = _generateConsistentConversationId(
          currentUserId, request.fromSessionId);

      // Get current user's display name
      final currentUserDisplayName =
          SeSessionService().currentSession?.displayName ??
              'User $currentUserId';

      // CRITICAL: Create and encrypt user data to include in the accept event
      final userData = {
        'userName': currentUserDisplayName,
        'sessionId': currentUserId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'conversationId': consistentConversationId,
      };

      // Encrypt user data with requester's public key
      final encryptedUserData =
          await EncryptionService.encryptData(userData, request.fromSessionId);

      if (encryptedUserData == null) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ❌ Failed to encrypt user data for accept event');
        return false;
      }

      _socketService.emit('key_exchange:accept', {
        'requestId': request.id,
        'senderId': currentUserId, // The acceptor (us) - CORRECTED
        'recipientId': request.fromSessionId, // The requester - CORRECTED
        'publicKey': currentUserPublicKey, // CRITICAL: Include our public key
        'encryptedUserData':
            encryptedUserData, // CRITICAL: Include encrypted user data
        'conversationId':
            consistentConversationId, // CRITICAL: Include conversation ID
        'timestamp': DateTime.now().toIso8601String(),
      });

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Key exchange accept event sent to server with encrypted user data');
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Conversation ID included: $consistentConversationId');

      // No need to send separate user data exchange - it's now included in the accept event
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ℹ️ User data included in accept event, no separate exchange needed');

      // Mark the request as accepted
      request.status = 'accepted';
      request.respondedAt = DateTime.now();
      notifyListeners();

      // Save the final status
      await _saveReceivedRequest(request);

      // Create local notification for accepted request
      try {
        final notificationService = LocalNotificationItemsService();
        await notificationService.createKerAcceptedNotification(
          senderId: request.fromSessionId,
          recipientId: currentUserId,
          requestPhrase: request.requestPhrase,
        );
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ Local notification created for accepted KER');
      } catch (e) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ⚠️ Failed to create local notification: $e');
      }

      return true;
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error accepting key exchange request: $e');
      // Reset status to received on error to allow retry
      try {
        final existingRequest =
            _receivedRequests.firstWhere((req) => req.id == request.id);
        existingRequest.status = 'received';
        existingRequest.respondedAt = null;
        notifyListeners();

        // Save the reset status
        await _saveReceivedRequest(existingRequest);
      } catch (revertError) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Error reverting status: $revertError');
      }
      return false;
    }
  }

  /// Decline a key exchange request
  Future<bool> declineKeyExchangeRequest(String requestId) async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Declining key exchange request: $requestId');

      final request =
          _receivedRequests.firstWhere((req) => req.id == requestId);
      if (request.status != 'received') {
        Logger.debug(
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

      // Send key exchange decline according to API documentation
      _socketService.sendKeyExchangeDecline(
        senderId: currentUserId,
        recipientId: request.fromSessionId,
        requestId: requestId,
        reason: 'User declined the key exchange request',
      );

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Key exchange request declined successfully');

      // Mark the request as declined
      request.status = 'declined';
      request.respondedAt = DateTime.now();
      notifyListeners();

      // Save the final status
      await _saveReceivedRequest(request);

      // Create local notification for declined request
      try {
        final notificationService = LocalNotificationItemsService();
        await notificationService.createKerDeclinedNotification(
          senderId: request.fromSessionId,
          recipientId: currentUserId,
          requestPhrase: request.requestPhrase,
        );
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ Local notification created for declined KER');
      } catch (e) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ⚠️ Failed to create local notification: $e');
      }

      return true;
    } catch (e) {
      Logger.debug(
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
        Logger.debug(
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

      // Create local notification for failed request
      try {
        final notificationService = LocalNotificationItemsService();
        final currentUserId = SeSessionService().currentSessionId;
        if (currentUserId != null) {
          // For failed requests, we'll create a simple notification
          // This could be enhanced with a specific failed notification type
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ℹ️ Key exchange request failed - no notification created');
        }
      } catch (e) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ⚠️ Failed to create local notification: $e');
      }

      Logger.debug('🔑 KeyExchangeRequestProvider: ✅ Request marked as failed');
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error marking request as failed: $e');
    }
  }

  /// Retry a failed key exchange request
  Future<bool> retryKeyExchangeRequest(String requestId) async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Retrying key exchange request: $requestId');

      final request =
          _receivedRequests.firstWhere((req) => req.id == requestId);

      // Reset status to received to allow retry
      request.status = 'received';
      request.respondedAt = null;
      notifyListeners();

      // Save the reset status
      await _saveReceivedRequest(request);

      // Create local notification for retry
      try {
        final notificationService = LocalNotificationItemsService();
        final currentUserId = SeSessionService().currentSessionId;
        if (currentUserId != null) {
          await notificationService.createKerResentNotification(
            senderId: currentUserId,
            recipientId: request.toSessionId,
            requestPhrase: request.requestPhrase,
          );
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ✅ Local notification created for retry KER');
        }
      } catch (e) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ⚠️ Failed to create local notification: $e');
      }

      Logger.debug('🔑 KeyExchangeRequestProvider: ✅ Request reset for retry');
      return true;
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error retrying key exchange request: $e');
      return false;
    }
  }

  /// Handle key exchange error from socket
  void handleKeyExchangeError(Map<String, dynamic> errorData) {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Handling key exchange error');
      Logger.debug('🔑 KeyExchangeRequestProvider: Error data: $errorData');

      final errorCode = errorData['errorCode']?.toString();
      final requestId = errorData['requestId']?.toString();
      final recipientId = errorData['recipientId']?.toString();

      // Find the request in sent requests and update its status
      if (requestId != null) {
        final requestIndex =
            _sentRequests.indexWhere((req) => req.id == requestId);
        if (requestIndex != -1) {
          _sentRequests[requestIndex].status = 'failed';
          notifyListeners();
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Updated request $requestId status to failed');
        }
      }

      // If we have recipientId, find and update any requests to that recipient
      if (recipientId != null) {
        for (int i = 0; i < _sentRequests.length; i++) {
          if (_sentRequests[i].toSessionId == recipientId &&
              (_sentRequests[i].status == 'pending' ||
                  _sentRequests[i].status == 'sent')) {
            _sentRequests[i].status = 'failed';
            Logger.debug(
                '🔑 KeyExchangeRequestProvider: Updated request to $recipientId status to failed');
          }
        }
        notifyListeners();
      }

      // Note: No snackbar needed since push notification handles this
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error handling key exchange error: $e');
    }
  }

  /// Handle key exchange declined from socket
  Future<void> handleKeyExchangeDeclined(
      Map<String, dynamic> declineData) async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Handling key exchange declined');
      Logger.debug('🔑 KeyExchangeRequestProvider: Decline data: $declineData');

      // CRITICAL: Refresh data from storage to ensure we have the latest sent requests
      await _loadSavedRequests();
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Data refreshed from storage before processing decline');

      final senderId = declineData['senderId']?.toString();
      final requestId = declineData['requestId']?.toString();
      final reason = declineData['reason']?.toString();

      // Find the request in sent requests and update its status
      if (requestId != null) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: 🔍 Looking for sent request with ID: $requestId');
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: 🔍 Available sent request IDs: ${_sentRequests.map((req) => req.id).toList()}');

        final requestIndex =
            _sentRequests.indexWhere((req) => req.id == requestId);
        if (requestIndex != -1) {
          _sentRequests[requestIndex].status = 'declined';
          _sentRequests[requestIndex].respondedAt = DateTime.now();

          // Save the updated status to local storage
          await _saveSentRequest(_sentRequests[requestIndex]);

          notifyListeners();
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ✅ Updated request $requestId status to declined');
        } else {
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ❌ Request $requestId not found in sent requests');
        }
      }

      // If we have senderId, find and update any requests to that sender
      if (senderId != null) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: 🔍 Looking for sent requests to sender: $senderId');
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: 🔍 Available sent requests: ${_sentRequests.map((req) => '${req.id}->${req.toSessionId}(${req.status})').toList()}');

        for (int i = 0; i < _sentRequests.length; i++) {
          if (_sentRequests[i].toSessionId == senderId &&
              (_sentRequests[i].status == 'pending' ||
                  _sentRequests[i].status == 'sent')) {
            _sentRequests[i].status = 'declined';
            _sentRequests[i].respondedAt = DateTime.now();

            // Save the updated status to local storage
            await _saveSentRequest(_sentRequests[i]);

            Logger.debug(
                '🔑 KeyExchangeRequestProvider: ✅ Updated request to $senderId status to declined');
          }
        }
        notifyListeners();
      }

      // Create local notification for declined request
      try {
        final notificationService = LocalNotificationItemsService();
        final currentUserId = SeSessionService().currentSessionId;
        if (currentUserId != null && senderId != null) {
          await notificationService.createKerDeclinedNotification(
            senderId: senderId,
            recipientId: currentUserId,
            requestPhrase: reason ?? 'Key exchange request declined',
          );
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ✅ Local notification created for declined KER');
        }
      } catch (e) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ⚠️ Failed to create local notification: $e');
      }

      // Note: No snackbar needed since push notification handles this
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error handling key exchange decline: $e');
    }
  }

  /// Handle key exchange accepted from socket
  Future<void> handleKeyExchangeAccepted(
      Map<String, dynamic> acceptData) async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Handling key exchange accepted');
      Logger.debug('🔑 KeyExchangeRequestProvider: Accept data: $acceptData');

      // CRITICAL: Refresh data from storage to ensure we have the latest sent requests
      await _loadSavedRequests();
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Data refreshed from storage before processing acceptance');
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: 🔍 Total sent requests after refresh: ${_sentRequests.length}');
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: 🔍 Total received requests after refresh: ${_receivedRequests.length}');

      final senderId = acceptData['senderId']?.toString();
      final requestId = acceptData['requestId']?.toString();
      final conversationId = acceptData['conversationId']?.toString();

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: 🔍 Extracted senderId: $senderId');
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: 🔍 Extracted requestId: $requestId');
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: 🔍 Extracted conversationId: $conversationId');

      // Find the request in sent requests and update its status
      if (requestId != null) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: 🔍 Looking for sent request with ID: $requestId');
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: 🔍 Available sent request IDs: ${_sentRequests.map((req) => req.id).toList()}');

        final requestIndex =
            _sentRequests.indexWhere((req) => req.id == requestId);
        if (requestIndex != -1) {
          _sentRequests[requestIndex].status = 'accepted';
          _sentRequests[requestIndex].respondedAt = DateTime.now();

          // Save the updated status to local storage
          await _saveSentRequest(_sentRequests[requestIndex]);

          notifyListeners();
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ✅ Updated request $requestId status to accepted');
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: 🔔 notifyListeners() called - UI should rebuild');
        } else {
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ❌ Request $requestId not found in sent requests');
        }
      }

      // If we have senderId, find and update any requests to that sender
      if (senderId != null) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: 🔍 Looking for sent requests to sender: $senderId');
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: 🔍 Available sent requests: ${_sentRequests.map((req) => '${req.id}->${req.toSessionId}(${req.status})').toList()}');

        for (int i = 0; i < _sentRequests.length; i++) {
          if (_sentRequests[i].toSessionId == senderId &&
              (_sentRequests[i].status == 'pending' ||
                  _sentRequests[i].status == 'sent')) {
            _sentRequests[i].status = 'accepted';
            _sentRequests[i].respondedAt = DateTime.now();

            // Save the updated status to local storage
            await _saveSentRequest(_sentRequests[i]);

            Logger.debug(
                '🔑 KeyExchangeRequestProvider: ✅ Updated request to $senderId status to accepted');
          }
        }

        // CRITICAL: Clean up any duplicate requests since they will be in contact list
        _sentRequests.removeWhere(
            (req) => req.toSessionId == senderId && req.status != 'accepted');

        _receivedRequests.removeWhere((req) =>
            req.fromSessionId == senderId &&
            (req.status == 'received' ||
                req.status == 'pending' ||
                req.status == 'processing'));

        // Save the cleaned up requests
        await _saveAllRequests();
        notifyListeners();
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: 🔔 notifyListeners() called in fallback logic - UI should rebuild');

        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ Cleaned up duplicate requests for accepted sender: $senderId');
      }

      // Create local notification for accepted request
      try {
        final notificationService = LocalNotificationItemsService();
        final currentUserId = SeSessionService().currentSessionId;
        if (currentUserId != null && senderId != null) {
          await notificationService.createKerAcceptedNotification(
            senderId: senderId,
            recipientId: currentUserId,
            requestPhrase: 'Key exchange request accepted',
            conversationId: conversationId,
          );
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ✅ Local notification created for accepted KER');
        }
      } catch (e) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ⚠️ Failed to create local notification: $e');
      }

      // Note: No snackbar needed since push notification handles this
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error handling key exchange accepted: $e');
    }
  }

  /// Get user-friendly error message based on error code
  String _getUserFriendlyErrorMessage(String? errorCode) {
    switch (errorCode) {
      case 'RECIPIENT_NOT_FOUND':
        return 'The recipient is currently offline. Your request will be delivered when they come online.';
      case 'INVALID_PAYLOAD':
        return 'Invalid request format. Please try again.';
      case 'UNAUTHORIZED_REQUEST':
        return 'You can only send key exchange requests from your own session.';
      case 'NO_PUBLIC_KEY':
        return 'No public key found. Please ensure you are properly registered.';
      case 'REQUESTER_NOT_FOUND':
        return 'Unable to deliver response. The requester may be offline.';
      case 'UNAUTHORIZED_ACCEPT':
        return 'You can only accept key exchange requests sent to you.';
      case 'UNAUTHORIZED_DECLINE':
        return 'You can only decline key exchange requests sent to you.';
      case 'DECLINE_NOTIFICATION_FAILED':
        return 'Unable to notify requester of decline. They may be offline.';
      default:
        return 'An error occurred during key exchange. Please try again.';
    }
  }

  /// Resend a key exchange request (for sent requests)
  Future<bool> resendKeyExchangeRequest(String requestId) async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Resending key exchange request: $requestId');

      // Find the request in sent requests
      final requestIndex =
          _sentRequests.indexWhere((req) => req.id == requestId);
      if (requestIndex == -1) {
        Logger.debug(
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

        // Create local notification for resent request
        try {
          final notificationService = LocalNotificationItemsService();
          final currentUserId = SeSessionService().currentSessionId;
          if (currentUserId != null) {
            await notificationService.createKerResentNotification(
              senderId: currentUserId,
              recipientId: request.toSessionId,
              requestPhrase: request.requestPhrase,
            );
            Logger.debug(
                '🔑 KeyExchangeRequestProvider: ✅ Local notification created for resent KER');
          }
        } catch (e) {
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ⚠️ Failed to create local notification: $e');
        }

        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ Request resent successfully');
        return true;
      } else {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ❌ Failed to resend request');
        return false;
      }
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error resending request: $e');
      return false;
    }
  }

  /// Process key exchange acceptance notification
  Future<void> processKeyExchangeAccepted(Map<String, dynamic> data) async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Processing key exchange acceptance');

      final requestId = data['request_id'] as String?;
      final recipientId = data['recipient_id'] as String?;
      final acceptorPublicKey = data['acceptor_public_key'] as String?;

      if (requestId == null || recipientId == null) {
        Logger.debug('🔑 KeyExchangeRequestProvider: Invalid acceptance data');
        return;
      }

      // Check if we received the acceptor's public key
      if (acceptorPublicKey == null) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ❌ Acceptor public key not included in acceptance notification');
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Falling back to old retry mechanism');

        // Fall back to the old retry mechanism for backward compatibility
        await _processKeyExchangeAcceptedLegacy(data);
        return;
      }

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Received acceptor public key, storing it immediately');

      // Store the acceptor's public key immediately
      await _storeAcceptorPublicKey(recipientId, acceptorPublicKey);

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Looking for sent request with ID: $requestId');
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Current sent requests count: ${_sentRequests.length}');

      // Check if the request exists in sent requests
      final requestIndex =
          _sentRequests.indexWhere((req) => req.id == requestId);

      if (requestIndex == -1) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Request $requestId not found in sent requests');
        Logger.debug(
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

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Key exchange request marked as accepted');

      // Now we can immediately send encrypted user data since we have Bob's public key!
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Acceptor public key stored, sending encrypted user data immediately');
      await _sendEncryptedUserData(recipientId);
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error processing acceptance: $e');
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Stack trace: ${StackTrace.current}');
    }
  }

  /// Process key exchange declined notification
  Future<void> processKeyExchangeDeclined(Map<String, dynamic> data) async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Processing key exchange decline');

      final requestId = data['request_id'] as String?;
      final recipientId = data['recipient_id'] as String?;

      if (requestId == null || recipientId == null) {
        Logger.debug('🔑 KeyExchangeRequestProvider: Invalid decline data');
        return;
      }

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Looking for sent request with ID: $requestId');

      // Check if the request exists in sent requests
      final requestIndex =
          _sentRequests.indexWhere((req) => req.id == requestId);

      if (requestIndex == -1) {
        Logger.debug(
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

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Key exchange request marked as declined');

      // Create local notification for declined request (sender's perspective)
      try {
        final notificationService = LocalNotificationItemsService();
        final currentUserId = SeSessionService().currentSessionId;
        if (currentUserId != null) {
          await notificationService.createKerDeclinedNotification(
            senderId: currentUserId,
            recipientId: recipientId,
            requestPhrase: request.requestPhrase,
          );
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ✅ Local notification created for declined KER (sender)');
        }
      } catch (e) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ⚠️ Failed to create local notification: $e');
      }
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error processing decline: $e');
    }
  }

  /// Load and add a missing sent request from storage
  Future<void> _loadAndAddMissingSentRequest(
      String requestId, String recipientId) async {
    try {
      Logger.debug(
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
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Request $requestId not found in storage');
        savedRequestData = null;
      }

      if (savedRequestData != null) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Found missing request in storage, adding to sent requests');

        try {
          final request = KeyExchangeRequest.fromJson(savedRequestData);
          request.status = 'accepted';
          request.respondedAt = DateTime.now();

          _sentRequests.add(request);
          notifyListeners();

          // Save the updated request
          await _saveSentRequest(request);

          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ✅ Missing sent request loaded and marked as accepted');

          // Don't immediately send encrypted user data - wait for key exchange to complete
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Key exchange accepted, waiting for public key to be available...');

          // Schedule a check for when the key exchange is actually complete
          _scheduleKeyExchangeCompletionCheck(recipientId);
        } catch (parseError) {
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Error parsing saved request: $parseError');
        }
      } else {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Request $requestId not found in storage either');
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: This might be a new request or storage issue');
      }
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error loading missing sent request: $e');
    }
  }

  /// Load and add a missing sent request from storage for decline
  Future<void> _loadAndAddMissingSentRequestForDecline(
      String requestId, String recipientId) async {
    try {
      Logger.debug(
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
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Request $requestId not found in storage');
        savedRequestData = null;
      }

      if (savedRequestData != null) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Found missing request in storage, adding to sent requests as declined');

        try {
          final request = KeyExchangeRequest.fromJson(savedRequestData);
          request.status = 'declined';
          request.respondedAt = DateTime.now();

          _sentRequests.add(request);
          notifyListeners();

          // Save the updated request
          await _saveSentRequest(request);

          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ✅ Missing sent request loaded and marked as declined');
        } catch (parseError) {
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Error parsing saved request: $parseError');
        }
      } else {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Request $requestId not found in storage either');
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: This might be a new request or storage issue');
      }
    } catch (e) {
      Logger.debug(
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
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Key exchange complete for $userId - public key available');
        return true;
      }

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Key exchange not complete for $userId - public key not available');
      return false;
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error checking key exchange status: $e');
      return false;
    }
  }

  /// Helper method to send encrypted user data after accepting key exchange
  Future<void> _sendEncryptedUserData(String recipientId) async {
    try {
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) return;

      final currentSession = SeSessionService().currentSession;
      final userName = currentSession?.displayName ?? 'User $currentUserId';

      // Create user data payload
      final userData = {
        'userName': userName,
        'sessionId': currentUserId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'conversationId': '', // Will be set when conversation is created
      };

      // Encrypt the user data
      final encryptedData = await EncryptionService.encryptData(
        userData,
        recipientId,
      );

      if (encryptedData != null) {
        // Send user data exchange back to requester
        _socketService.sendUserDataExchange(
          recipientId: recipientId,
          encryptedData: encryptedData,
        );
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ User data exchange sent back to requester: $recipientId');
      } else {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ⚠️ Warning: Could not encrypt user data for exchange');
      }
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ⚠️ Warning: Could not send user data exchange: $e');
    }
  }

  /// Schedule a retry for sending encrypted user data
  void _scheduleEncryptedDataRetry(String recipientId, String currentUserId) {
    // Retry after 10 seconds to allow key exchange to complete
    // Key exchanges can take time to propagate and store keys
    Future.delayed(const Duration(seconds: 10), () async {
      try {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Retrying encrypted user data send to: $recipientId');

        // Check if the key exchange is now complete
        final isComplete = await _isKeyExchangeComplete(recipientId);

        if (isComplete) {
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Key exchange now complete, retrying encrypted data send');
          await _sendEncryptedUserData(recipientId);
        } else {
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Key exchange still not complete, will retry again later');
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Key exchange may still be in progress');

          // Schedule another retry after 30 seconds for the second attempt
          Future.delayed(const Duration(seconds: 30), () {
            _scheduleEncryptedDataRetry(recipientId, currentUserId);
          });
        }
      } catch (e) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Error during retry attempt: $e');

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
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Key exchange completion check limit reached for $recipientId');
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: The key exchange may not have completed properly');

      // Log the current state for debugging
      await _logKeyExchangeState(recipientId);
      return;
    }

    // Schedule a check after a short delay to allow the key exchange to propagate
    Future.delayed(const Duration(seconds: 5), () async {
      try {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Checking if key exchange is complete for: $recipientId (attempt ${attemptCount + 1}/12)');

        // Check if we have the recipient's public key
        final hasPublicKey =
            await KeyExchangeService.instance.hasPublicKeyForUser(recipientId);

        if (hasPublicKey) {
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Key exchange now complete, sending encrypted user data to: $recipientId');
          await _sendEncryptedUserData(recipientId);
        } else {
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Key exchange still not complete, will check again in 5 seconds');
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Note: The recipient may need to complete their side of the key exchange first');

          // Log the current state for debugging
          await _logKeyExchangeState(recipientId);

          // Schedule another check with incremented attempt count
          _scheduleKeyExchangeCompletionCheck(recipientId, attemptCount + 1);
        }
      } catch (e) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Error during key exchange completion check: $e');
        // Schedule another check even if there's an error
        _scheduleKeyExchangeCompletionCheck(recipientId, attemptCount + 1);
      }
    });
  }

  /// Log the current key exchange state for debugging
  Future<void> _logKeyExchangeState(String recipientId) async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: === Key Exchange State Debug ===');
      Logger.debug('🔑 KeyExchangeRequestProvider: Recipient ID: $recipientId');

      // Check if we have a public key
      final hasPublicKey =
          await KeyExchangeService.instance.hasPublicKeyForUser(recipientId);
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Has public key: $hasPublicKey');

      // Check if we have any sent requests to this recipient
      final sentRequests =
          _sentRequests.where((req) => req.toSessionId == recipientId).toList();
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Sent requests to recipient: ${sentRequests.length}');

      for (final request in sentRequests) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: - Request ${request.id}: ${request.status}');
      }

      // Check if we have any received requests from this recipient
      final receivedRequests = _receivedRequests
          .where((req) => req.fromSessionId == recipientId)
          .toList();
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Received requests from recipient: ${receivedRequests.length}');

      for (final request in receivedRequests) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: - Request ${request.id}: ${request.status}');
      }

      Logger.debug('🔑 KeyExchangeRequestProvider: === End Debug ===');
    } catch (e) {
      Logger.debug(
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
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ Sent request saved to local storage');
      } else {
        // Update existing request
        final index =
            existingRequests.indexWhere((req) => req['id'] == request.id);
        if (index != -1) {
          existingRequests[index] = request.toJson();
          await prefsService.setJsonList(
              'key_exchange_sent_requests', existingRequests);
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ✅ Sent request updated in local storage');
        }
      }
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error saving sent request: $e');
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
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ Received request saved to local storage');
      } else {
        // Update existing request
        final index =
            existingRequests.indexWhere((req) => req['id'] == request.id);
        if (index != -1) {
          existingRequests[index] = request.toJson();
          await prefsService.setJsonList(
              'key_exchange_received_requests', existingRequests);
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ✅ Received request updated in local storage');
        }
      }
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error saving received request: $e');
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
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ Request updated in local storage');
      } else {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Request not found in storage for update');
      }
    } catch (e) {
      Logger.debug('🔑 KeyExchangeRequestProvider: Error updating request: $e');
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
          Logger.debug(
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
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Error parsing saved received request: $e');
        }
      }

      // Sort requests by timestamp (newest first)
      _sentRequests.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _receivedRequests.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      notifyListeners();
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Loaded ${_sentRequests.length} sent and ${_receivedRequests.length} received requests');

      // Migrate old data format if needed
      await _migrateOldDataFormat();
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error loading saved requests: $e');
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

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: 🔄 Migrating old data format...');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        Logger.debug(
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
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Error parsing request during migration: $e');
        }
      }

      // Save to new storage format
      if (newSentRequests.isNotEmpty) {
        await prefsService.setJsonList(
            'key_exchange_sent_requests', newSentRequests);
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ Migrated ${newSentRequests.length} sent requests');
      }

      if (newReceivedRequests.isNotEmpty) {
        await prefsService.setJsonList(
            'key_exchange_received_requests', newReceivedRequests);
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ Migrated ${newReceivedRequests.length} received requests');
      }

      // Remove old data
      await prefsService.remove('key_exchange_requests');
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Migration completed, old data removed');

      // Reload the data with the new format
      await _loadSavedRequests();
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error during data migration: $e');
    }
  }

  /// Retry connection to socket service
  Future<void> _retryConnection(BuildContext context) async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: 🔄 Retrying socket connection...');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔄 Attempting to reconnect...'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Try to reconnect
      await _socketService.connect(SeSessionService().currentSessionId!);

      // Wait for connection to stabilize
      await Future.delayed(const Duration(seconds: 2));

      if (context.mounted) {
        if (_socketService.isConnected) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Reconnected successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Reconnection failed. Please try again.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ❌ Error during reconnection retry: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Reconnection error: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Clear all data and reset provider state (used when account is deleted)
  void clearAllData() {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: 🗑️ Clearing all data and resetting state...');

      // Clear all requests
      _sentRequests.clear();
      _receivedRequests.clear();
      _pendingRequests.clear();

      // Notify listeners
      notifyListeners();

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ All data cleared and state reset');
    } catch (e) {
      Logger.debug('🔑 KeyExchangeRequestProvider: ❌ Error clearing data: $e');
    }
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

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ All data cleared from storage and memory');
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error clearing data from storage: $e');
    }
  }

  /// Force refresh data from storage
  Future<void> forceRefreshFromStorage() async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: 🔄 Force refreshing data from storage...');
      await _loadSavedRequests();
      Logger.debug('🔑 KeyExchangeRequestProvider: ✅ Force refresh completed');
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error during force refresh: $e');
    }
  }

  /// Reload data when user session changes
  Future<void> reloadDataForNewSession() async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: 🔄 Reloading data for new user session...');

      // Clear current data
      _sentRequests.clear();
      _receivedRequests.clear();
      _pendingRequests.clear();

      // Load data for the new session
      await _loadSavedRequests();

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Data reloaded for new session');
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error reloading data for new session: $e');
    }
  }

  /// Store the acceptor's public key for immediate use
  Future<void> _storeAcceptorPublicKey(
      String recipientId, String publicKey) async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Storing acceptor public key for: $recipientId');

      // Debug: Check key format and length
      final keyBytes = base64.decode(publicKey);
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Key length: ${keyBytes.length} bytes (${keyBytes.length * 8} bits)');
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Key format: ${publicKey.substring(0, 20)}...');

      // Validate key length for AES encryption
      if (keyBytes.length != 16 &&
          keyBytes.length != 24 &&
          keyBytes.length != 32) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ⚠️ Warning: Key length ${keyBytes.length} bytes is not standard AES length (16/24/32 bytes)');
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: This may cause encryption failures');
      }

      // Store the public key using the EncryptionService
      await EncryptionService.storeRecipientPublicKey(recipientId, publicKey);

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Acceptor public key stored successfully');
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ❌ Error storing acceptor public key: $e');
      rethrow;
    }
  }

  /// Legacy fallback for when acceptor public key is not included
  Future<void> _processKeyExchangeAcceptedLegacy(
      Map<String, dynamic> data) async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Using legacy fallback mechanism');

      final requestId = data['request_id'] as String?;
      final recipientId = data['recipient_id'] as String?;

      if (requestId == null || recipientId == null) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Invalid acceptance data in legacy mode');
        return;
      }

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Looking for sent request with ID: $requestId');
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Current sent requests count: ${_sentRequests.length}');

      // Check if the request exists in sent requests
      final requestIndex =
          _sentRequests.indexWhere((req) => req.id == requestId);

      if (requestIndex == -1) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Request $requestId not found in sent requests');
        Logger.debug(
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

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Key exchange request marked as accepted (legacy mode)');

      // Use the old retry mechanism
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Key exchange accepted, waiting for public key to be available...');
      _scheduleKeyExchangeCompletionCheck(recipientId);
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error in legacy fallback: $e');
    }
  }

  /// Legacy version of loading missing sent request
  Future<void> _loadAndAddMissingSentRequestLegacy(
      String requestId, String recipientId) async {
    try {
      Logger.debug(
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
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Request $requestId not found in storage');
        savedRequestData = null;
      }

      if (savedRequestData != null) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Found missing request in storage, adding to sent requests (legacy mode)');

        try {
          final request = KeyExchangeRequest.fromJson(savedRequestData);
          request.status = 'accepted';
          request.respondedAt = DateTime.now();

          _sentRequests.add(request);
          notifyListeners();

          // Save the updated request
          await _saveSentRequest(request);

          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ✅ Missing sent request loaded and marked as accepted (legacy mode)');

          // Use the old retry mechanism
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Key exchange accepted, waiting for public key to be available...');
          _scheduleKeyExchangeCompletionCheck(recipientId);
        } catch (parseError) {
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Error parsing saved request: $parseError');
        }
      } else {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: Request $requestId not found in storage either');
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: This might be a new request or storage issue');
      }
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error loading missing sent request: $e');
    }
  }

  /// Update the status of a received key exchange request in local storage
  Future<void> _updateReceivedRequestStatus(
      String requestId, String status) async {
    try {
      final request =
          _receivedRequests.firstWhere((req) => req.id == requestId);
      request.status = status;
      request.respondedAt = DateTime.now();
      notifyListeners();
      await _saveReceivedRequest(request);
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Received request status updated to $status');
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error updating received request status: $e');
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
      Logger.debug(
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
      Logger.debug(
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
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error getting completion data: $e');
      return null;
    }
  }

  /// Refresh UI when key exchange data is updated
  Future<void> refreshKeyExchangeData() async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Refreshing key exchange data for UI update');

      // Reload data from storage to get latest updates
      await _loadSavedRequests();

      // Notify listeners to refresh UI
      notifyListeners();

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Key exchange data refreshed, UI updated');
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error refreshing key exchange data: $e');
    }
  }

  /// Update display name for a user and refresh UI
  Future<void> updateUserDisplayName(String userId, String displayName) async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Updating display name for $userId to: $displayName');

      // Store the display name mapping
      final prefsService = SeSharedPreferenceService();
      final displayNameMappings =
          await prefsService.getJson('ker_display_names') ?? {};
      displayNameMappings[userId] = displayName;
      await prefsService.setJson('ker_display_names', displayNameMappings);

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Display name mapping stored');

      // Update display names in all key exchange requests for this user
      bool hasUpdates = false;

      // Update sent requests
      for (final request in _sentRequests) {
        if (request.toSessionId == userId &&
            request.displayName != displayName) {
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Updating sent request display name from "${request.displayName}" to "$displayName"');
          request.displayName = displayName;
          hasUpdates = true;
        }
      }

      // Update received requests
      for (final request in _receivedRequests) {
        if (request.fromSessionId == userId &&
            request.displayName != displayName) {
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Updating received request display name from "${request.displayName}" to "$displayName"');
          request.displayName = displayName;
          hasUpdates = true;
        }
      }

      // Update pending requests
      for (final request in _pendingRequests) {
        if (request.fromSessionId == userId &&
            request.displayName != displayName) {
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: Updating pending request display name from "${request.displayName}" to "$displayName"');
          request.displayName = displayName;
          hasUpdates = true;
        }
      }

      Logger.debug('🔑 KeyExchangeRequestProvider: Has updates: $hasUpdates');

      // Save updated requests to storage
      if (hasUpdates) {
        await _saveAllRequests();
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ All requests saved to storage');
      }

      // Refresh the UI
      await refreshKeyExchangeData();

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Display name updated and UI refreshed');
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error updating display name: $e');
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

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ All requests saved to storage');
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error saving all requests: $e');
    }
  }

  /// Delete/revoke a sent key exchange request
  Future<bool> deleteSentRequest(String requestId) async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Deleting sent request: $requestId');

      // Find the request
      final requestIndex =
          _sentRequests.indexWhere((req) => req.id == requestId);
      if (requestIndex == -1) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ❌ Sent request not found: $requestId');
        return false;
      }

      final request = _sentRequests[requestIndex];

      // Notify the server that the request is revoked (if it was sent)
      if (request.status == 'sent' || request.status == 'pending') {
        try {
          _socketService.revokeKeyExchange(
            recipientId: request.toSessionId,
            requestId: request.id,
          );
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ✅ Revoke notification sent to server');
        } catch (e) {
          Logger.debug(
              '🔑 KeyExchangeRequestProvider: ⚠️ Failed to notify server about revocation: $e');
        }
      }

      // For now, we'll just log the revocation
      // In the future, this can be implemented to send revocation events via the channel socket
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: 📊 Key exchange request revoked: $requestId');

      // Update local request status
      request.status = 'revoked';
      notifyListeners();

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Key exchange request revoked locally: $requestId');

      // Remove from local list
      _sentRequests.removeAt(requestIndex);
      notifyListeners();

      // Remove from storage
      await _removeSentRequestFromStorage(requestId);

      // Note: Pending exchange cleanup is handled by KeyExchangeService internally

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Sent request deleted successfully');
      return true;
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error deleting sent request: $e');
      return false;
    }
  }

  /// Delete a received key exchange request
  Future<bool> deleteReceivedRequest(String requestId) async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Deleting received request: $requestId');

      // Find the request
      final requestIndex =
          _receivedRequests.indexWhere((req) => req.id == requestId);
      if (requestIndex == -1) {
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ❌ Received request not found: $requestId');
        return false;
      }

      final request = _receivedRequests[requestIndex];

      // Remove from local list
      _receivedRequests.removeAt(requestIndex);
      notifyListeners();

      // Remove from storage
      await _removeReceivedRequestFromStorage(requestId);

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Received request deleted successfully');
      return true;
    } catch (e) {
      Logger.debug(
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

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Sent request removed from storage');
    } catch (e) {
      Logger.debug(
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

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Received request removed from storage');
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error removing received request from storage: $e');
    }
  }

  /// Handle key exchange request revoked by sender
  Future<void> handleRequestRevoked(String requestId, String senderId) async {
    try {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Handling revoked request: $requestId from $senderId');

      // Find and remove the received request
      final receivedIndex =
          _receivedRequests.indexWhere((req) => req.id == requestId);
      if (receivedIndex != -1) {
        _receivedRequests.removeAt(receivedIndex);
        notifyListeners();
        await _removeReceivedRequestFromStorage(requestId);
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ Revoked request removed from received list');
      }

      // Also check sent requests in case there was a duplicate
      final sentIndex = _sentRequests.indexWhere((req) => req.id == requestId);
      if (sentIndex != -1) {
        _sentRequests.removeAt(sentIndex);
        notifyListeners();
        await _removeSentRequestFromStorage(requestId);
        Logger.debug(
            '🔑 KeyExchangeRequestProvider: ✅ Revoked request removed from sent list');
      }

      Logger.debug(
          '🔑 KeyExchangeRequestProvider: ✅ Request revocation handled successfully');
    } catch (e) {
      Logger.debug(
          '🔑 KeyExchangeRequestProvider: Error handling request revocation: $e');
    }
  }
}
