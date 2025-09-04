import 'package:flutter/material.dart';
import 'package:sechat_app//../core/utils/logger.dart';

/// Enum representing different types of encryption errors
enum EncryptionErrorType {
  keyMissing,
  keyExchangeFailed,
  encryptionFailed,
  decryptionFailed,
  checksumVerificationFailed,
  storageError,
  networkError,
  unknownError,
}

/// Class to handle encryption errors in a centralized way
class EncryptionErrorHandler {
  static final EncryptionErrorHandler _instance = EncryptionErrorHandler._();
  static EncryptionErrorHandler get instance => _instance;

  EncryptionErrorHandler._();

  // Error logging callback
  void Function(String message, {EncryptionErrorType type})? _logCallback;

  // Error display callback
  void Function(BuildContext context, String message, {bool isWarning})?
      _displayCallback;

  // Set the logging callback
  void setLogCallback(
      void Function(String message, {EncryptionErrorType type}) callback) {
    _logCallback = callback;
  }

  // Set the display callback
  void setDisplayCallback(
      void Function(BuildContext context, String message, {bool isWarning})
          callback) {
    _displayCallback = callback;
  }

  // Log an encryption error
  void logError(String message,
      {EncryptionErrorType type = EncryptionErrorType.unknownError}) {
    Logger.debug(
        '🔒 Encryption Error [${type.toString().split('.').last}]: $message');

    if (_logCallback != null) {
      _logCallback!(message, type: type);
    }
  }

  // Display an error to the user
  void displayError(BuildContext context, String message,
      {bool isWarning = false}) {
    if (_displayCallback != null) {
      _displayCallback!(context, message, isWarning: isWarning);
    } else {
      // Default implementation using SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isWarning ? Colors.orange : Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // Get user-friendly error message based on error type
  String getUserFriendlyMessage(EncryptionErrorType type, {String? details}) {
    switch (type) {
      case EncryptionErrorType.keyMissing:
        return 'Encryption key not found. Please reconnect with this contact.';
      case EncryptionErrorType.keyExchangeFailed:
        return 'Failed to exchange encryption keys. Please try again later.';
      case EncryptionErrorType.encryptionFailed:
        return 'Failed to encrypt message. Please try again.';
      case EncryptionErrorType.decryptionFailed:
        return 'Failed to decrypt message. The message may be corrupted or using an outdated key.';
      case EncryptionErrorType.checksumVerificationFailed:
        return 'Message integrity check failed. The message may have been tampered with.';
      case EncryptionErrorType.storageError:
        return 'Failed to store encryption keys securely.';
      case EncryptionErrorType.networkError:
        return 'Network error while sending encrypted message. Please check your connection.';
      case EncryptionErrorType.unknownError:
        return details != null
            ? 'Unexpected encryption error: $details'
            : 'An unexpected encryption error occurred.';
    }
  }

  // Handle encryption exceptions and return appropriate error type
  EncryptionErrorType handleException(Exception e) {
    final errorMessage = e.toString().toLowerCase();

    if (errorMessage.contains('key not found') ||
        errorMessage.contains('null key')) {
      return EncryptionErrorType.keyMissing;
    } else if (errorMessage.contains('exchange') ||
        errorMessage.contains('handshake')) {
      return EncryptionErrorType.keyExchangeFailed;
    } else if (errorMessage.contains('encrypt')) {
      return EncryptionErrorType.encryptionFailed;
    } else if (errorMessage.contains('decrypt')) {
      return EncryptionErrorType.decryptionFailed;
    } else if (errorMessage.contains('checksum') ||
        errorMessage.contains('integrity') ||
        errorMessage.contains('verify')) {
      return EncryptionErrorType.checksumVerificationFailed;
    } else if (errorMessage.contains('storage') ||
        errorMessage.contains('store') ||
        errorMessage.contains('save')) {
      return EncryptionErrorType.storageError;
    } else if (errorMessage.contains('network') ||
        errorMessage.contains('connection') ||
        errorMessage.contains('timeout')) {
      return EncryptionErrorType.networkError;
    } else {
      return EncryptionErrorType.unknownError;
    }
  }
}
