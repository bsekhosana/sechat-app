import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/message.dart';
import '../models/media_message.dart';
import '../models/chat_conversation.dart';
import 'message_storage_service.dart';
import 'chat_encryption_service.dart';
import 'message_status_tracking_service.dart';

/// Service for handling location message sharing, GPS integration, and management
class LocationMessageService {
  static LocationMessageService? _instance;
  static LocationMessageService get instance =>
      _instance ??= LocationMessageService._();

  final MessageStorageService _storageService = MessageStorageService.instance;
  final ChatEncryptionService _encryptionService =
      ChatEncryptionService.instance;
  final MessageStatusTrackingService _statusTrackingService =
      MessageStatusTrackingService.instance;

  // Location state
  bool _isGettingLocation = false;
  StreamController<LocationUpdate>? _locationUpdateController;
  StreamController<LocationProcessingProgress>? _processingProgressController;

  // Location cache
  LocationData? _lastKnownLocation;
  List<LocationData> _recentLocations = [];
  List<FavoriteLocation> _favoriteLocations = [];

  LocationMessageService._();

  /// Stream for location updates
  Stream<LocationUpdate>? get locationUpdateStream =>
      _locationUpdateController?.stream;

  /// Stream for location processing progress updates
  Stream<LocationProcessingProgress>? get processingProgressStream =>
      _processingProgressController?.stream;

  /// Check if currently getting location
  bool get isGettingLocation => _isGettingLocation;

  /// Get last known location
  LocationData? get lastKnownLocation => _lastKnownLocation;

  /// Get recent locations
  List<LocationData> get recentLocations => List.unmodifiable(_recentLocations);

  /// Get favorite locations
  List<FavoriteLocation> get favoriteLocations =>
      List.unmodifiable(_favoriteLocations);

  /// Get current location
  Future<LocationData?> getCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      if (_isGettingLocation) {
        print(
            '📍 LocationMessageService: Already getting location, returning last known');
        return _lastKnownLocation;
      }

      print(
          '📍 LocationMessageService: Getting current location with accuracy: $accuracy');

      _isGettingLocation = true;
      _locationUpdateController = StreamController<LocationUpdate>.broadcast();

      // Emit location started
      _locationUpdateController?.add(LocationUpdate(
        type: LocationUpdateType.started,
        message: 'Getting current location...',
        location: _lastKnownLocation,
      ));

      // In real implementation, this would use GPS/location services
      // For now, we'll simulate location detection
      final location = await _simulateLocationDetection(accuracy);

      if (location != null) {
        _lastKnownLocation = location;
        _addToRecentLocations(location);

        // Emit location success
        _locationUpdateController?.add(LocationUpdate(
          type: LocationUpdateType.success,
          message: 'Location obtained successfully',
          location: location,
        ));

        print(
            '📍 LocationMessageService: ✅ Current location obtained: ${location.latitude}, ${location.longitude}');
      } else {
        // Emit location error
        _locationUpdateController?.add(LocationUpdate(
          type: LocationUpdateType.error,
          message: 'Failed to get location',
          location: _lastKnownLocation,
        ));

        print('📍 LocationMessageService: ❌ Failed to get current location');
      }

      return location;
    } catch (e) {
      print('📍 LocationMessageService: ❌ Error getting current location: $e');

      _locationUpdateController?.add(LocationUpdate(
        type: LocationUpdateType.error,
        message: 'Error: $e',
        location: _lastKnownLocation,
      ));

      return _lastKnownLocation;
    } finally {
      _isGettingLocation = false;
      await _locationUpdateController?.close();
      _locationUpdateController = null;
    }
  }

  /// Share current location
  Future<Message?> shareCurrentLocation({
    required String conversationId,
    required String recipientId,
    LocationSharingOptions options = const LocationSharingOptions(),
  }) async {
    try {
      print(
          '📍 LocationMessageService: Sharing current location with options: $options');

      // Get current location
      final location = await getCurrentLocation(accuracy: options.accuracy);
      if (location == null) {
        print('📍 LocationMessageService: ❌ No location available to share');
        return null;
      }

      // Share the location
      final message = await _shareLocation(
        conversationId: conversationId,
        recipientId: recipientId,
        location: location,
        options: options,
      );

      print(
          '📍 LocationMessageService: ✅ Current location shared successfully');
      return message;
    } catch (e) {
      print(
          '📍 LocationMessageService: ❌ Failed to share current location: $e');
      rethrow;
    }
  }

  /// Share specific location
  Future<Message?> shareLocation({
    required String conversationId,
    required String recipientId,
    required LocationData location,
    LocationSharingOptions options = const LocationSharingOptions(),
  }) async {
    try {
      print(
          '📍 LocationMessageService: Sharing specific location: ${location.latitude}, ${location.longitude}');

      final message = await _shareLocation(
        conversationId: conversationId,
        recipientId: recipientId,
        location: location,
        options: options,
      );

      print('📍 LocationMessageService: ✅ Location shared successfully');
      return message;
    } catch (e) {
      print('📍 LocationMessageService: ❌ Failed to share location: $e');
      rethrow;
    }
  }

  /// Share location from map selection
  Future<Message?> shareLocationFromMap({
    required String conversationId,
    required String recipientId,
    required double latitude,
    required double longitude,
    String? address,
    LocationSharingOptions options = const LocationSharingOptions(),
  }) async {
    try {
      print(
          '📍 LocationMessageService: Sharing location from map: $latitude, $longitude');

      // Create location data from coordinates
      final location = LocationData(
        latitude: latitude,
        longitude: longitude,
        accuracy: options.accuracy,
        timestamp: DateTime.now(),
        address: address,
        source: LocationSource.mapSelection,
      );

      final message = await _shareLocation(
        conversationId: conversationId,
        recipientId: recipientId,
        location: location,
        options: options,
      );

      print('📍 LocationMessageService: ✅ Map location shared successfully');
      return message;
    } catch (e) {
      print('📍 LocationMessageService: ❌ Failed to share map location: $e');
      rethrow;
    }
  }

  /// Share location from address search
  Future<Message?> shareLocationFromAddress({
    required String conversationId,
    required String recipientId,
    required String address,
    LocationSharingOptions options = const LocationSharingOptions(),
  }) async {
    try {
      print(
          '📍 LocationMessageService: Sharing location from address: $address');

      // In real implementation, this would geocode the address
      // For now, we'll simulate geocoding
      final location = await _simulateGeocoding(address);
      if (location == null) {
        print('📍 LocationMessageService: ❌ Failed to geocode address');
        return null;
      }

      final message = await _shareLocation(
        conversationId: conversationId,
        recipientId: recipientId,
        location: location,
        options: options,
      );

      print(
          '📍 LocationMessageService: ✅ Address location shared successfully');
      return message;
    } catch (e) {
      print(
          '📍 LocationMessageService: ❌ Failed to share address location: $e');
      rethrow;
    }
  }

  /// Add location to favorites
  Future<bool> addToFavorites(LocationData location, {String? name}) async {
    try {
      print('📍 LocationMessageService: Adding location to favorites');

      final favoriteLocation = FavoriteLocation(
        id: const Uuid().v4(),
        location: location,
        name: name ?? 'Favorite Location',
        addedAt: DateTime.now(),
      );

      _favoriteLocations.add(favoriteLocation);

      print('📍 LocationMessageService: ✅ Location added to favorites');
      return true;
    } catch (e) {
      print(
          '📍 LocationMessageService: ❌ Failed to add location to favorites: $e');
      return false;
    }
  }

  /// Remove location from favorites
  Future<bool> removeFromFavorites(String favoriteId) async {
    try {
      print(
          '📍 LocationMessageService: Removing location from favorites: $favoriteId');

      _favoriteLocations.removeWhere((favorite) => favorite.id == favoriteId);

      print('📍 LocationMessageService: ✅ Location removed from favorites');
      return true;
    } catch (e) {
      print(
          '📍 LocationMessageService: ❌ Failed to remove location from favorites: $e');
      return false;
    }
  }

  /// Get location statistics
  Future<Map<String, dynamic>> getLocationStats() async {
    try {
      return {
        'total_locations_shared': 0,
        'total_favorite_locations': _favoriteLocations.length,
        'recent_locations_count': _recentLocations.length,
        'last_location_timestamp':
            _lastKnownLocation?.timestamp?.millisecondsSinceEpoch,
        'most_shared_coordinates': null,
        'location_sharing_frequency': 'daily',
      };
    } catch (e) {
      print('📍 LocationMessageService: ❌ Failed to get location stats: $e');
      return {};
    }
  }

  /// Delete a location message
  Future<bool> deleteLocationMessage(String messageId) async {
    try {
      print('📍 LocationMessageService: Deleting location message: $messageId');

      // Get the message
      final message = await _getMessageById(messageId);
      if (message == null) {
        print('📍 LocationMessageService: ❌ Message not found: $messageId');
        return false;
      }

      // Check if it's a location message
      if (message.type != MessageType.location) {
        print(
            '📍 LocationMessageService: ❌ Not a location message: ${message.type}');
        return false;
      }

      // Mark message as deleted
      final deletedMessage = message.copyWith(
        status: MessageStatus.deleted,
        deletedAt: DateTime.now(),
      );

      await _storageService.saveMessage(deletedMessage);

      print(
          '📍 LocationMessageService: ✅ Location message deleted: $messageId');
      return true;
    } catch (e) {
      print(
          '📍 LocationMessageService: ❌ Failed to delete location message: $e');
      return false;
    }
  }

  /// Share location internally
  Future<Message?> _shareLocation({
    required String conversationId,
    required String recipientId,
    required LocationData location,
    required LocationSharingOptions options,
  }) async {
    try {
      // Generate map preview
      final mapPreviewPath = await _generateMapPreview(location, options);

      // Create media message for map preview
      final mediaMessage = MediaMessage(
        messageId: const Uuid().v4(),
        type: MediaType.image, // Map preview is an image
        filePath: mapPreviewPath ?? '',
        fileName: 'map_preview_${DateTime.now().millisecondsSinceEpoch}.png',
        mimeType: 'image/png',
        fileSize: 0, // Will be updated after file creation
        duration: null,
        isCompressed: false,
        thumbnailPath: mapPreviewPath,
        metadata: {
          'location_data': location.toMap(),
          'map_options': options.toMap(),
        },
      );

      // Save media message to storage if preview exists
      if (mapPreviewPath != null) {
        final previewFile = File(mapPreviewPath);
        if (await previewFile.exists()) {
          final previewData = await previewFile.readAsBytes();
          final fileSize = previewData.length;

          // Update media message with actual file size
          final updatedMediaMessage = mediaMessage.copyWith(fileSize: fileSize);
          await _storageService.saveMediaMessage(
              updatedMediaMessage, previewData);
        }
      }

      // Create location message
      final message = Message(
        conversationId: conversationId,
        senderId: _getCurrentUserId(),
        recipientId: recipientId,
        type: MessageType.location,
        content: {
          'latitude': location.latitude,
          'longitude': location.longitude,
          'accuracy': location.accuracy.name,
          'timestamp': location.timestamp.millisecondsSinceEpoch,
          'address': location.address,
          'source': location.source.name,
          'map_preview_path': mapPreviewPath,
          'sharing_options': options.toMap(),
        },
        status: MessageStatus.sending,
        fileSize: mapPreviewPath != null ? 0 : 0,
        mimeType: 'application/location',
        replyToMessageId: null,
        metadata: {
          'location_data': location.toMap(),
          'map_options': options.toMap(),
        },
      );

      // Save message to storage
      await _storageService.saveMessage(message);

      // Update conversation with new message
      await _updateConversationWithMessage(message);

      // Mark message as sent
      await _statusTrackingService.markMessageAsSent(message.id);

      return message;
    } catch (e) {
      print('📍 LocationMessageService: ❌ Failed to share location: $e');
      rethrow;
    }
  }

  /// Generate map preview
  Future<String?> _generateMapPreview(
      LocationData location, LocationSharingOptions options) async {
    try {
      print('📍 LocationMessageService: Generating map preview');

      // In real implementation, this would use a map service to generate a preview image
      // For now, we'll create a placeholder preview

      final tempDir = await getTemporaryDirectory();
      final previewFileName =
          'map_preview_${DateTime.now().millisecondsSinceEpoch}.png';
      final previewPath = path.join(tempDir.path, previewFileName);

      // Simulate preview creation (in real implementation, this would generate a map image)
      // For now, we'll create a placeholder file
      final previewFile = File(previewPath);
      await previewFile.writeAsBytes(Uint8List(0)); // Empty file as placeholder

      print('📍 LocationMessageService: ✅ Map preview generated: $previewPath');
      return previewPath;
    } catch (e) {
      print('📍 LocationMessageService: ❌ Failed to generate map preview: $e');
      return null;
    }
  }

  /// Simulate location detection
  Future<LocationData?> _simulateLocationDetection(
      LocationAccuracy accuracy) async {
    try {
      // Simulate GPS delay
      await Future.delayed(Duration(milliseconds: 1500));

      // Generate simulated coordinates (San Francisco area)
      final latitude =
          37.7749 + (0.01 * (DateTime.now().millisecond % 100 - 50));
      final longitude =
          -122.4194 + (0.01 * (DateTime.now().millisecond % 100 - 50));

      final location = LocationData(
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        timestamp: DateTime.now(),
        address: 'San Francisco, CA, USA',
        source: LocationSource.gps,
      );

      return location;
    } catch (e) {
      print(
          '📍 LocationMessageService: ❌ Simulated location detection failed: $e');
      return null;
    }
  }

  /// Simulate geocoding
  Future<LocationData?> _simulateGeocoding(String address) async {
    try {
      // Simulate geocoding delay
      await Future.delayed(Duration(milliseconds: 1000));

      // Generate simulated coordinates based on address hash
      final hash = address.hashCode;
      final latitude = 37.7749 + (0.01 * (hash % 100 - 50));
      final longitude = -122.4194 + (0.01 * (hash % 100 - 50));

      final location = LocationData(
        latitude: latitude,
        longitude: longitude,
        accuracy: LocationAccuracy.high,
        timestamp: DateTime.now(),
        address: address,
        source: LocationSource.addressSearch,
      );

      return location;
    } catch (e) {
      print('📍 LocationMessageService: ❌ Simulated geocoding failed: $e');
      return null;
    }
  }

  /// Add location to recent locations
  void _addToRecentLocations(LocationData location) {
    _recentLocations.insert(0, location);

    // Keep only last 10 locations
    if (_recentLocations.length > 10) {
      _recentLocations = _recentLocations.take(10).toList();
    }
  }

  /// Send location message
  Future<Message?> sendLocationMessage({
    required String conversationId,
    required String recipientId,
    required LocationData location,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      print('📍 LocationMessageService: Sending location message to $recipientId');

      // Create message
      final message = Message(
        conversationId: conversationId,
        senderId: _getCurrentUserId(),
        recipientId: recipientId,
        type: MessageType.location,
        content: {
          'latitude': location.latitude,
          'longitude': location.longitude,
          'accuracy': location.accuracy.name,
          'address': location.address,
          'source': location.source.name,
          'timestamp': location.timestamp.millisecondsSinceEpoch,
        },
        replyToMessageId: replyToMessageId,
        metadata: metadata,
        status: MessageStatus.sending,
      );

      // Save message to storage
      await _storageService.saveMessage(message);

      // Update conversation with new message
      await _updateConversationWithMessage(message);

      // Mark message as sent
      await _statusTrackingService.markMessageAsSent(message.id);

      print('📍 LocationMessageService: ✅ Location message sent successfully: ${message.id}');
      return message;
    } catch (e) {
      print('📍 LocationMessageService: ❌ Failed to send location message: $e');
      rethrow;
    }
  }

  /// Update conversation with new message
  Future<void> _updateConversationWithMessage(Message message) async {
    try {
      final conversation =
          await _storageService.getConversation(message.conversationId);
      if (conversation == null) return;

      final updatedConversation = conversation.updateWithNewMessage(
        messageId: message.id,
        messagePreview: message.previewText,
        messageType: _convertToConversationMessageType(message.type),
        isFromCurrentUser: message.senderId == _getCurrentUserId(),
      );

      await _storageService.saveConversation(updatedConversation);
    } catch (e) {
      print('📍 LocationMessageService: ❌ Failed to update conversation: $e');
    }
  }

  /// Convert MessageType to conversation MessageType
  MessageType _convertToConversationMessageType(MessageType type) {
    // Since we're using the same MessageType enum, just return the type directly
    return type;
  }

  /// Get message by ID
  Future<Message?> _getMessageById(String messageId) async {
    try {
      // This will be implemented when we add message retrieval to the storage service
      // For now, return null
      return null;
    } catch (e) {
      print('📍 LocationMessageService: ❌ Failed to get message: $e');
      return null;
    }
  }

  /// Get current user ID
  String _getCurrentUserId() {
    // This will be implemented when we integrate with the session service
    // For now, return a placeholder
    return 'current_user_id';
  }

  /// Dispose of resources
  void dispose() {
    _isGettingLocation = false;
    _locationUpdateController?.close();
    _processingProgressController?.close();
    print('📍 LocationMessageService: ✅ Service disposed');
  }
}

/// Data class for location data
class LocationData {
  final double latitude;
  final double longitude;
  final LocationAccuracy accuracy;
  final DateTime timestamp;
  final String? address;
  final LocationSource source;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
    this.address,
    required this.source,
  });

  /// Convert to map for storage
  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy.name,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'address': address,
      'source': source.name,
    };
  }

  /// Create from map
  factory LocationData.fromMap(Map<String, dynamic> map) {
    return LocationData(
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      accuracy: LocationAccuracy.values.firstWhere(
        (e) => e.name == map['accuracy'],
        orElse: () => LocationAccuracy.medium,
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      address: map['address'] as String?,
      source: LocationSource.values.firstWhere(
        (e) => e.name == map['source'],
        orElse: () => LocationSource.unknown,
      ),
    );
  }
}

/// Data class for favorite location
class FavoriteLocation {
  final String id;
  final LocationData location;
  final String name;
  final DateTime addedAt;

  FavoriteLocation({
    required this.id,
    required this.location,
    required this.name,
    required this.addedAt,
  });
}

/// Data class for location update
class LocationUpdate {
  final LocationUpdateType type;
  final String message;
  final LocationData? location;

  LocationUpdate({
    required this.type,
    required this.message,
    this.location,
  });
}

/// Data class for location processing progress
class LocationProcessingProgress {
  final double progress; // 0.0 to 1.0
  final LocationProcessingStatus status;
  final String message;
  final LocationOperation operation;

  LocationProcessingProgress({
    required this.progress,
    required this.status,
    required this.message,
    required this.operation,
  });
}

/// Options for location sharing
class LocationSharingOptions {
  final LocationAccuracy accuracy;
  final bool includeAddress;
  final bool includeMapPreview;
  final String mapStyle; // e.g., 'standard', 'satellite', 'terrain'
  final int mapZoomLevel; // 1-20
  final bool includeTimestamp;
  final bool includeAccuracy;

  const LocationSharingOptions({
    this.accuracy = LocationAccuracy.high,
    this.includeAddress = true,
    this.includeMapPreview = true,
    this.mapStyle = 'standard',
    this.mapZoomLevel = 15,
    this.includeTimestamp = true,
    this.includeAccuracy = true,
  });

  /// Convert to map for storage
  Map<String, dynamic> toMap() {
    return {
      'accuracy': accuracy.name,
      'include_address': includeAddress,
      'include_map_preview': includeMapPreview,
      'map_style': mapStyle,
      'map_zoom_level': mapZoomLevel,
      'include_timestamp': includeTimestamp,
      'include_accuracy': includeAccuracy,
    };
  }
}

/// Enum for location accuracy
enum LocationAccuracy {
  low, // ~1000m
  medium, // ~100m
  high, // ~10m
  best, // ~1m
}

/// Enum for location source
enum LocationSource {
  gps,
  network,
  mapSelection,
  addressSearch,
  manual,
  unknown,
}

/// Enum for location update type
enum LocationUpdateType {
  started,
  success,
  error,
  timeout,
}

/// Enum for location processing status
enum LocationProcessingStatus {
  started,
  processing,
  completed,
  failed,
  cancelled,
}

/// Enum for location operations
enum LocationOperation {
  locationDetection,
  geocoding,
  mapPreviewGeneration,
  reverseGeocoding,
}
