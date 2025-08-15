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

/// Service for handling contact message sharing, vCard parsing, and management
class ContactMessageService {
  static ContactMessageService? _instance;
  static ContactMessageService get instance =>
      _instance ??= ContactMessageService._();

  final MessageStorageService _storageService = MessageStorageService.instance;
  final ChatEncryptionService _encryptionService =
      ChatEncryptionService.instance;
  final MessageStatusTrackingService _statusTrackingService =
      MessageStatusTrackingService.instance;

  // Contact state
  bool _isProcessing = false;
  StreamController<ContactProcessingProgress>? _processingProgressController;

  // Contact cache
  List<ContactData> _recentContacts = [];
  List<FavoriteContact> _favoriteContacts = [];

  ContactMessageService._();

  /// Stream for contact processing progress updates
  Stream<ContactProcessingProgress>? get processingProgressStream =>
      _processingProgressController?.stream;

  /// Check if currently processing
  bool get isProcessing => _isProcessing;

  /// Get recent contacts
  List<ContactData> get recentContacts => List.unmodifiable(_recentContacts);

  /// Get favorite contacts
  List<FavoriteContact> get favoriteContacts =>
      List.unmodifiable(_favoriteContacts);

  /// Select contact from address book
  Future<Message?> selectContact({
    required String conversationId,
    required String recipientId,
    ContactSelectionOptions options = const ContactSelectionOptions(),
  }) async {
    try {
      print(
          '👤 ContactMessageService: Selecting contact with options: $options');

      // In real implementation, this would open the contact picker
      // For now, we'll simulate contact selection
      final contact = await _simulateContactSelection(options);
      if (contact == null) {
        print('👤 ContactMessageService: ❌ Contact selection failed');
        return null;
      }

      // Share the selected contact
      final message = await _shareContact(
        conversationId: conversationId,
        recipientId: recipientId,
        contact: contact,
        options: ContactSharingOptions(
          includePhoneNumbers: options.includePhoneNumbers,
          includeEmailAddresses: options.includeEmailAddresses,
          includeCompanyInfo: options.includeCompanyInfo,
          includeBirthday: options.includeBirthday,
          includeNotes: options.includeNotes,
        ),
      );

      print(
          '👤 ContactMessageService: ✅ Contact selected and shared successfully');
      return message;
    } catch (e) {
      print('👤 ContactMessageService: ❌ Failed to select contact: $e');
      rethrow;
    }
  }

  /// Share contact from vCard file
  Future<Message?> shareContactFromVCard({
    required String conversationId,
    required String recipientId,
    required String vCardFilePath,
    ContactSharingOptions options = const ContactSharingOptions(),
  }) async {
    try {
      print(
          '👤 ContactMessageService: Sharing contact from vCard: $vCardFilePath');

      // Parse vCard file
      final contact = await _parseVCardFile(vCardFilePath);
      if (contact == null) {
        print('👤 ContactMessageService: ❌ Failed to parse vCard file');
        return null;
      }

      // Share the parsed contact
      final message = await _shareContact(
        conversationId: conversationId,
        recipientId: recipientId,
        contact: contact,
        options: options,
      );

      print('👤 ContactMessageService: ✅ vCard contact shared successfully');
      return message;
    } catch (e) {
      print('👤 ContactMessageService: ❌ Failed to share vCard contact: $e');
      rethrow;
    }
  }

  /// Share contact from contact data
  Future<Message?> shareContact({
    required String conversationId,
    required String recipientId,
    required ContactData contact,
    ContactSharingOptions options = const ContactSharingOptions(),
  }) async {
    try {
      print(
          '👤 ContactMessageService: Sharing contact: ${contact.displayName}');

      final message = await _shareContact(
        conversationId: conversationId,
        recipientId: recipientId,
        contact: contact,
        options: options,
      );

      print('👤 ContactMessageService: ✅ Contact shared successfully');
      return message;
    } catch (e) {
      print('👤 ContactMessageService: ❌ Failed to share contact: $e');
      rethrow;
    }
  }

  /// Share multiple contacts
  Future<List<Message>> shareMultipleContacts({
    required String conversationId,
    required String recipientId,
    required List<ContactData> contacts,
    ContactSharingOptions options = const ContactSharingOptions(),
  }) async {
    try {
      print('👤 ContactMessageService: Sharing ${contacts.length} contacts');

      final messages = <Message>[];

      for (final contact in contacts) {
        final message = await _shareContact(
          conversationId: conversationId,
          recipientId: recipientId,
          contact: contact,
          options: options,
        );

        if (message != null) {
          messages.add(message);
        }
      }

      print(
          '👤 ContactMessageService: ✅ ${messages.length} contacts shared successfully');
      return messages;
    } catch (e) {
      print(
          '👤 ContactMessageService: ❌ Failed to share multiple contacts: $e');
      rethrow;
    }
  }

  /// Add contact to favorites
  Future<bool> addToFavorites(ContactData contact, {String? nickname}) async {
    try {
      print(
          '👤 ContactMessageService: Adding contact to favorites: ${contact.displayName}');

      final favoriteContact = FavoriteContact(
        id: const Uuid().v4(),
        contact: contact,
        nickname: nickname ?? contact.displayName,
        addedAt: DateTime.now(),
      );

      _favoriteContacts.add(favoriteContact);

      print('👤 ContactMessageService: ✅ Contact added to favorites');
      return true;
    } catch (e) {
      print(
          '👤 ContactMessageService: ❌ Failed to add contact to favorites: $e');
      return false;
    }
  }

  /// Remove contact from favorites
  Future<bool> removeFromFavorites(String favoriteId) async {
    try {
      print(
          '👤 ContactMessageService: Removing contact from favorites: $favoriteId');

      _favoriteContacts.removeWhere((favorite) => favorite.id == favoriteId);

      print('👤 ContactMessageService: ✅ Contact removed from favorites');
      return true;
    } catch (e) {
      print(
          '👤 ContactMessageService: ❌ Failed to remove contact from favorites: $e');
      return false;
    }
  }

  /// Get contact statistics
  Future<Map<String, dynamic>> getContactStats() async {
    try {
      return {
        'total_contacts_shared': 0,
        'total_favorite_contacts': _favoriteContacts.length,
        'recent_contacts_count': _recentContacts.length,
        'most_shared_contact': null,
        'contact_sharing_frequency': 'daily',
        'vcard_parsing_success_rate': 1.0,
      };
    } catch (e) {
      print('👤 ContactMessageService: ❌ Failed to get contact stats: $e');
      return {};
    }
  }

  /// Delete a contact message
  Future<bool> deleteContactMessage(String messageId) async {
    try {
      print('👤 ContactMessageService: Deleting contact message: $messageId');

      // Get the message
      final message = await _getMessageById(messageId);
      if (message == null) {
        print('👤 ContactMessageService: ❌ Message not found: $messageId');
        return false;
      }

      // Check if it's a contact message
      if (message.type != MessageType.contact) {
        print(
            '👤 ContactMessageService: ❌ Not a contact message: ${message.type}');
        return false;
      }

      // Mark message as deleted
      final deletedMessage = message.copyWith(
        status: MessageStatus.deleted,
        deletedAt: DateTime.now(),
      );

      await _storageService.saveMessage(deletedMessage);

      print('👤 ContactMessageService: ✅ Contact message deleted: $messageId');
      return true;
    } catch (e) {
      print('👤 ContactMessageService: ❌ Failed to delete contact message: $e');
      return false;
    }
  }

  /// Share contact internally
  Future<Message?> _shareContact({
    required String conversationId,
    required String recipientId,
    required ContactData contact,
    required ContactSharingOptions options,
  }) async {
    try {
      // Generate contact preview
      final contactPreviewPath =
          await _generateContactPreview(contact, options);

      // Create vCard file
      final vCardPath = await _createVCardFile(contact);

      // Create media message for contact preview
      final mediaMessage = MediaMessage(
        messageId: const Uuid().v4(),
        type: MediaType.image, // Contact preview is an image
        filePath: contactPreviewPath ?? '',
        fileName:
            'contact_preview_${DateTime.now().millisecondsSinceEpoch}.png',
        mimeType: 'image/png',
        fileSize: 0, // Will be updated after file creation
        duration: null,
        isCompressed: false,
        thumbnailPath: contactPreviewPath,
        metadata: {
          'contact_data': contact.toMap(),
          'sharing_options': options.toMap(),
          'vcard_path': vCardPath,
        },
      );

      // Save media message to storage if preview exists
      if (contactPreviewPath != null) {
        final previewFile = File(contactPreviewPath);
        if (await previewFile.exists()) {
          final previewData = await previewFile.readAsBytes();
          final fileSize = previewData.length;

          // Update media message with actual file size
          final updatedMediaMessage = mediaMessage.copyWith(fileSize: fileSize);
          await _storageService.saveMediaMessage(
              updatedMediaMessage, previewData);
        }
      }

      // Create contact message
      final message = Message(
        conversationId: conversationId,
        senderId: _getCurrentUserId(),
        recipientId: recipientId,
        type: MessageType.contact,
        content: {
          'display_name': contact.displayName,
          'phone_numbers': contact.phoneNumbers,
          'email_addresses': contact.emailAddresses,
          'company': contact.company,
          'job_title': contact.jobTitle,
          'contact_preview_path': contactPreviewPath,
          'vcard_path': vCardPath,
          'sharing_options': options.toMap(),
        },
        status: MessageStatus.sending,
        fileSize: contactPreviewPath != null ? 0 : 0,
        mimeType: 'application/contact',
        replyToMessageId: null,
        metadata: {
          'contact_data': contact.toMap(),
          'sharing_options': options.toMap(),
        },
      );

      // Save message to storage
      await _storageService.saveMessage(message);

      // Update conversation with new message
      await _updateConversationWithMessage(message);

      // Mark message as sent
      await _statusTrackingService.markMessageAsSent(message.id);

      // Add to recent contacts
      _addToRecentContacts(contact);

      return message;
    } catch (e) {
      print('👤 ContactMessageService: ❌ Failed to share contact: $e');
      rethrow;
    }
  }

  /// Generate contact preview
  Future<String?> _generateContactPreview(
      ContactData contact, ContactSharingOptions options) async {
    try {
      print('👤 ContactMessageService: Generating contact preview');

      // In real implementation, this would generate a contact card image
      // For now, we'll create a placeholder preview

      final tempDir = await getTemporaryDirectory();
      final previewFileName =
          'contact_preview_${DateTime.now().millisecondsSinceEpoch}.png';
      final previewPath = path.join(tempDir.path, previewFileName);

      // Simulate preview creation (in real implementation, this would generate a contact card)
      // For now, we'll create a placeholder file
      final previewFile = File(previewPath);
      await previewFile.writeAsBytes(Uint8List(0)); // Empty file as placeholder

      print(
          '👤 ContactMessageService: ✅ Contact preview generated: $previewPath');
      return previewPath;
    } catch (e) {
      print(
          '👤 ContactMessageService: ❌ Failed to generate contact preview: $e');
      return null;
    }
  }

  /// Create vCard file
  Future<String?> _createVCardFile(ContactData contact) async {
    try {
      print('👤 ContactMessageService: Creating vCard file');

      final tempDir = await getTemporaryDirectory();
      final vCardFileName =
          'contact_${DateTime.now().millisecondsSinceEpoch}.vcf';
      final vCardPath = path.join(tempDir.path, vCardFileName);

      // Generate vCard content
      final vCardContent = _generateVCardContent(contact);

      // Write vCard file
      final vCardFile = File(vCardPath);
      await vCardFile.writeAsString(vCardContent);

      print('👤 ContactMessageService: ✅ vCard file created: $vCardPath');
      return vCardPath;
    } catch (e) {
      print('👤 ContactMessageService: ❌ Failed to create vCard file: $e');
      return null;
    }
  }

  /// Generate vCard content
  String _generateVCardContent(ContactData contact) {
    final buffer = StringBuffer();

    buffer.writeln('BEGIN:VCARD');
    buffer.writeln('VERSION:3.0');
    buffer.writeln('FN:${contact.displayName}');

    if (contact.firstName.isNotEmpty) {
      buffer.writeln('N:${contact.lastName};${contact.firstName};;;');
    }

    if (contact.company.isNotEmpty) {
      buffer.writeln('ORG:${contact.company}');
    }

    if (contact.jobTitle.isNotEmpty) {
      buffer.writeln('TITLE:${contact.jobTitle}');
    }

    for (final phone in contact.phoneNumbers) {
      buffer
          .writeln('TEL;TYPE=${phone.type.name.toUpperCase()}:${phone.number}');
    }

    for (final email in contact.emailAddresses) {
      buffer.writeln(
          'EMAIL;TYPE=${email.type.name.toUpperCase()}:${email.address}');
    }

    if (contact.birthday != null) {
      buffer
          .writeln('BDAY:${contact.birthday!.toIso8601String().split('T')[0]}');
    }

    if (contact.notes.isNotEmpty) {
      buffer.writeln('NOTE:${contact.notes}');
    }

    buffer.writeln('REV:${DateTime.now().toUtc().toIso8601String()}');
    buffer.writeln('END:VCARD');

    return buffer.toString();
  }

  /// Parse vCard file
  Future<ContactData?> _parseVCardFile(String vCardFilePath) async {
    try {
      print('👤 ContactMessageService: Parsing vCard file: $vCardFilePath');

      final vCardFile = File(vCardFilePath);
      if (!await vCardFile.exists()) {
        print('👤 ContactMessageService: ❌ vCard file not found');
        return null;
      }

      final vCardContent = await vCardFile.readAsString();
      final contact = _parseVCardContent(vCardContent);

      if (contact != null) {
        print('👤 ContactMessageService: ✅ vCard parsed successfully');
        return contact;
      } else {
        print('👤 ContactMessageService: ❌ Failed to parse vCard content');
        return null;
      }
    } catch (e) {
      print('👤 ContactMessageService: ❌ Failed to parse vCard file: $e');
      return null;
    }
  }

  /// Parse vCard content
  ContactData? _parseVCardContent(String vCardContent) {
    try {
      final lines = vCardContent.split('\n');
      String? displayName;
      String firstName = '';
      String lastName = '';
      String company = '';
      String jobTitle = '';
      String notes = '';
      DateTime? birthday;
      final phoneNumbers = <PhoneNumber>[];
      final emailAddresses = <EmailAddress>[];

      for (final line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;

        if (trimmedLine.startsWith('FN:')) {
          displayName = trimmedLine.substring(3);
        } else if (trimmedLine.startsWith('N:')) {
          final parts = trimmedLine.substring(2).split(';');
          if (parts.length >= 2) {
            lastName = parts[0];
            firstName = parts[1];
          }
        } else if (trimmedLine.startsWith('ORG:')) {
          company = trimmedLine.substring(4);
        } else if (trimmedLine.startsWith('TITLE:')) {
          jobTitle = trimmedLine.substring(6);
        } else if (trimmedLine.startsWith('TEL;')) {
          final parts = trimmedLine.split(':');
          if (parts.length >= 2) {
            final type = _parsePhoneType(parts[0]);
            final number = parts[1];
            phoneNumbers.add(PhoneNumber(number: number, type: type));
          }
        } else if (trimmedLine.startsWith('EMAIL;')) {
          final parts = trimmedLine.split(':');
          if (parts.length >= 2) {
            final type = _parseEmailType(parts[0]);
            final address = parts[1];
            emailAddresses.add(EmailAddress(address: address, type: type));
          }
        } else if (trimmedLine.startsWith('BDAY:')) {
          final dateStr = trimmedLine.substring(5);
          try {
            birthday = DateTime.parse(dateStr);
          } catch (e) {
            // Ignore invalid date
          }
        } else if (trimmedLine.startsWith('NOTE:')) {
          notes = trimmedLine.substring(5);
        }
      }

      if (displayName == null || displayName.isEmpty) {
        displayName = '$firstName $lastName'.trim();
        if (displayName.isEmpty) return null;
      }

      return ContactData(
        displayName: displayName,
        firstName: firstName,
        lastName: lastName,
        company: company,
        jobTitle: jobTitle,
        phoneNumbers: phoneNumbers,
        emailAddresses: emailAddresses,
        birthday: birthday,
        notes: notes,
      );
    } catch (e) {
      print('👤 ContactMessageService: ❌ Error parsing vCard content: $e');
      return null;
    }
  }

  /// Parse phone type from vCard
  PhoneType _parsePhoneType(String typeString) {
    if (typeString.contains('CELL')) return PhoneType.mobile;
    if (typeString.contains('WORK')) return PhoneType.work;
    if (typeString.contains('HOME')) return PhoneType.home;
    if (typeString.contains('FAX')) return PhoneType.fax;
    return PhoneType.other;
  }

  /// Parse email type from vCard
  EmailType _parseEmailType(String typeString) {
    if (typeString.contains('WORK')) return EmailType.work;
    if (typeString.contains('HOME')) return EmailType.personal;
    if (typeString.contains('OTHER')) return EmailType.other;
    return EmailType.personal;
  }

  /// Simulate contact selection (placeholder for contact picker integration)
  Future<ContactData?> _simulateContactSelection(
      ContactSelectionOptions options) async {
    try {
      // In real implementation, this would open the contact picker
      // For now, we'll create a simulated contact

      final contact = ContactData(
        displayName: 'John Doe',
        firstName: 'John',
        lastName: 'Doe',
        company: 'Tech Company',
        jobTitle: 'Software Engineer',
        phoneNumbers: [
          PhoneNumber(number: '+1-555-0123', type: PhoneType.mobile),
          PhoneNumber(number: '+1-555-0124', type: PhoneType.work),
        ],
        emailAddresses: [
          EmailAddress(
              address: 'john.doe@techcompany.com', type: EmailType.work),
          EmailAddress(
              address: 'johndoe@personal.com', type: EmailType.personal),
        ],
        birthday: DateTime(1990, 1, 1),
        notes: 'Met at conference',
      );

      print(
          '👤 ContactMessageService: ✅ Simulated contact selection: ${contact.displayName}');
      return contact;
    } catch (e) {
      print(
          '👤 ContactMessageService: ❌ Simulated contact selection failed: $e');
      return null;
    }
  }

  /// Add contact to recent contacts
  void _addToRecentContacts(ContactData contact) {
    // Remove if already exists
    _recentContacts.removeWhere((c) => c.displayName == contact.displayName);

    // Add to beginning
    _recentContacts.insert(0, contact);

    // Keep only last 20 contacts
    if (_recentContacts.length > 20) {
      _recentContacts = _recentContacts.take(20).toList();
    }
  }

  /// Send contact message
  Future<Message?> sendContactMessage({
    required String conversationId,
    required String recipientId,
    required ContactData contact,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      print(
          '👤 ContactMessageService: Sending contact message to $recipientId');

      // Create message
      final message = Message(
        conversationId: conversationId,
        senderId: _getCurrentUserId(),
        recipientId: recipientId,
        type: MessageType.contact,
        content: {
          'display_name': contact.displayName,
          'first_name': contact.firstName,
          'last_name': contact.lastName,
          'company': contact.company,
          'job_title': contact.jobTitle,
          'phone_numbers': contact.phoneNumbers.map((p) => p.number).toList(),
          'email_addresses':
              contact.emailAddresses.map((e) => e.address).toList(),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
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

      print(
          '👤 ContactMessageService: ✅ Contact message sent successfully: ${message.id}');
      return message;
    } catch (e) {
      print('👤 ContactMessageService: ❌ Failed to send contact message: $e');
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
      print('👤 ContactMessageService: ❌ Failed to update conversation: $e');
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
      print('👤 ContactMessageService: ❌ Failed to get message: $e');
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
    _isProcessing = false;
    _processingProgressController?.close();
    print('👤 ContactMessageService: ✅ Service disposed');
  }
}

/// Data class for contact data
class ContactData {
  final String displayName;
  final String firstName;
  final String lastName;
  final String company;
  final String jobTitle;
  final List<PhoneNumber> phoneNumbers;
  final List<EmailAddress> emailAddresses;
  final DateTime? birthday;
  final String notes;

  ContactData({
    required this.displayName,
    this.firstName = '',
    this.lastName = '',
    this.company = '',
    this.jobTitle = '',
    this.phoneNumbers = const [],
    this.emailAddresses = const [],
    this.birthday,
    this.notes = '',
  });

  /// Convert to map for storage
  Map<String, dynamic> toMap() {
    return {
      'display_name': displayName,
      'first_name': firstName,
      'last_name': lastName,
      'company': company,
      'job_title': jobTitle,
      'phone_numbers': phoneNumbers.map((p) => p.toMap()).toList(),
      'email_addresses': emailAddresses.map((e) => e.toMap()).toList(),
      'birthday': birthday?.millisecondsSinceEpoch,
      'notes': notes,
    };
  }

  /// Create from map
  factory ContactData.fromMap(Map<String, dynamic> map) {
    return ContactData(
      displayName: map['display_name'] as String,
      firstName: map['first_name'] as String? ?? '',
      lastName: map['last_name'] as String? ?? '',
      company: map['company'] as String? ?? '',
      jobTitle: map['job_title'] as String? ?? '',
      phoneNumbers: (map['phone_numbers'] as List<dynamic>?)
              ?.map((p) => PhoneNumber.fromMap(p as Map<String, dynamic>))
              .toList() ??
          [],
      emailAddresses: (map['email_addresses'] as List<dynamic>?)
              ?.map((e) => EmailAddress.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      birthday: map['birthday'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['birthday'] as int)
          : null,
      notes: map['notes'] as String? ?? '',
    );
  }
}

/// Data class for phone number
class PhoneNumber {
  final String number;
  final PhoneType type;

  PhoneNumber({
    required this.number,
    this.type = PhoneType.other,
  });

  /// Convert to map for storage
  Map<String, dynamic> toMap() {
    return {
      'number': number,
      'type': type.name,
    };
  }

  /// Create from map
  factory PhoneNumber.fromMap(Map<String, dynamic> map) {
    return PhoneNumber(
      number: map['number'] as String,
      type: PhoneType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => PhoneType.other,
      ),
    );
  }
}

/// Data class for email address
class EmailAddress {
  final String address;
  final EmailType type;

  EmailAddress({
    required this.address,
    this.type = EmailType.personal,
  });

  /// Convert to map for storage
  Map<String, dynamic> toMap() {
    return {
      'address': address,
      'type': type.name,
    };
  }

  /// Create from map
  factory EmailAddress.fromMap(Map<String, dynamic> map) {
    return EmailAddress(
      address: map['address'] as String,
      type: EmailType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => EmailType.personal,
      ),
    );
  }
}

/// Data class for favorite contact
class FavoriteContact {
  final String id;
  final ContactData contact;
  final String nickname;
  final DateTime addedAt;

  FavoriteContact({
    required this.id,
    required this.contact,
    required this.nickname,
    required this.addedAt,
  });
}

/// Data class for contact processing progress
class ContactProcessingProgress {
  final double progress; // 0.0 to 1.0
  final ContactProcessingStatus status;
  final String message;
  final ContactOperation operation;

  ContactProcessingProgress({
    required this.progress,
    required this.status,
    required this.message,
    required this.operation,
  });
}

/// Options for contact selection
class ContactSelectionOptions {
  final bool allowMultiple;
  final bool includePhoneNumbers;
  final bool includeEmailAddresses;
  final bool includeCompanyInfo;
  final bool includeBirthday;
  final bool includeNotes;

  const ContactSelectionOptions({
    this.allowMultiple = false,
    this.includePhoneNumbers = true,
    this.includeEmailAddresses = true,
    this.includeCompanyInfo = true,
    this.includeBirthday = true,
    this.includeNotes = true,
  });
}

/// Options for contact sharing
class ContactSharingOptions {
  final bool includePhoneNumbers;
  final bool includeEmailAddresses;
  final bool includeCompanyInfo;
  final bool includeBirthday;
  final bool includeNotes;
  final bool includeProfilePicture;
  final bool createVCard;

  const ContactSharingOptions({
    this.includePhoneNumbers = true,
    this.includeEmailAddresses = true,
    this.includeCompanyInfo = true,
    this.includeBirthday = true,
    this.includeNotes = true,
    this.includeProfilePicture = true,
    this.createVCard = true,
  });

  /// Convert to map for storage
  Map<String, dynamic> toMap() {
    return {
      'include_phone_numbers': includePhoneNumbers,
      'include_email_addresses': includeEmailAddresses,
      'include_company_info': includeCompanyInfo,
      'include_birthday': includeBirthday,
      'include_notes': includeNotes,
      'include_profile_picture': includeProfilePicture,
      'create_vcard': createVCard,
    };
  }
}

/// Enum for phone types
enum PhoneType {
  mobile,
  work,
  home,
  fax,
  other,
}

/// Enum for email types
enum EmailType {
  work,
  personal,
  other,
}

/// Enum for contact processing status
enum ContactProcessingStatus {
  started,
  processing,
  completed,
  failed,
  cancelled,
}

/// Enum for contact operations
enum ContactOperation {
  contactSelection,
  vCardParsing,
  contactPreviewGeneration,
  vCardCreation,
}
