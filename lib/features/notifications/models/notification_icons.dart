import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Icon mapping for notification types using FontAwesome icons
class NotificationIcons {
  // Welcome notifications
  static const welcome = FontAwesomeIcons.hand;

  // Key Exchange Request notifications
  static const kerSent = FontAwesomeIcons.key;
  static const kerReceived = FontAwesomeIcons.key;
  static const kerAccepted = FontAwesomeIcons.check;
  static const kerDeclined = FontAwesomeIcons.xmark;
  static const kerResent = FontAwesomeIcons.rotateRight;

  // Message notifications
  static const messageReceived = FontAwesomeIcons.message;
  static const messageDelivered = FontAwesomeIcons.checkDouble;
  static const messageRead = FontAwesomeIcons.eye;

  // Connection notifications
  static const connectionStatus = FontAwesomeIcons.wifi;
  static const userOnline = FontAwesomeIcons.circle;
  static const userOffline = FontAwesomeIcons.circle;

  /// Get icon for notification type
  static IconData getIconForType(String type) {
    switch (type) {
      case 'welcome':
        return welcome;
      case 'ker_sent':
        return kerSent;
      case 'ker_received':
        return kerReceived;
      case 'ker_accepted':
        return kerAccepted;
      case 'ker_declined':
        return kerDeclined;
      case 'ker_resent':
        return kerResent;
      case 'message_received':
        return messageReceived;
      case 'message_delivered':
        return messageDelivered;
      case 'message_read':
        return messageRead;
      case 'connection_status':
        return connectionStatus;
      case 'user_online':
        return userOnline;
      case 'user_offline':
        return userOffline;
      default:
        return FontAwesomeIcons.bell; // Default icon
    }
  }

  /// Get icon name as string for database storage
  static String getIconNameForType(String type) {
    switch (type) {
      case 'welcome':
        return 'handWave';
      case 'ker_sent':
        return 'key';
      case 'ker_received':
        return 'key';
      case 'ker_accepted':
        return 'check';
      case 'ker_declined':
        return 'xmark';
      case 'ker_resent':
        return 'rotateRight';
      case 'message_received':
        return 'message';
      case 'message_delivered':
        return 'checkDouble';
      case 'message_read':
        return 'eye';
      case 'connection_status':
        return 'wifi';
      case 'user_online':
        return 'circle';
      case 'user_offline':
        return 'circle';
      default:
        return 'bell';
    }
  }

  /// Get FontAwesome icon from icon name
  static IconData getIconFromName(String iconName) {
    switch (iconName) {
      case 'hand':
        return welcome;
      case 'key':
        return kerSent;
      case 'check':
        return kerAccepted;
      case 'xmark':
        return kerDeclined;
      case 'rotateRight':
        return kerResent;
      case 'message':
        return messageReceived;
      case 'checkDouble':
        return messageDelivered;
      case 'eye':
        return messageRead;
      case 'wifi':
        return connectionStatus;
      case 'circle':
        return userOnline;
      default:
        return FontAwesomeIcons.bell;
    }
  }
}
