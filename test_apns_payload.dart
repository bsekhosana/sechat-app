// Test file to verify APNS payload structure
// This simulates how the AirNotifier service creates payloads

import 'dart:convert';

void main() {
  // Test the new simplified payload structure
  testAPNSPayload();
}

void testAPNSPayload() {
  print('🧪 Testing APNS Payload Structure...\n');

  // Simulate invitation accepted notification
  final payload = createInvitationAcceptedPayload();

  print('📱 Generated Payload:');
  print(json.encode(payload));
  print('');

  // Validate the structure
  validateAPNSPayload(payload);
}

Map<String, dynamic> createInvitationAcceptedPayload() {
  // This simulates what _formatNotificationPayload would create
  final Map<String, dynamic> payload = {
    'session_id': 'session_789',
  };

  // iOS APNS: aps dictionary with system-defined keys only
  final Map<String, dynamic> aps = {
    'alert': {
      'title': 'Invitation Accepted',
      'body': 'Jane accepted your invitation'
    },
    'sound': 'default',
    'badge': 1
  };

  // Add aps to payload
  payload['aps'] = aps;

  // Add custom metadata OUTSIDE the aps dictionary (Apple's requirement)
  payload['type'] = 'invitation';
  payload['invitationId'] = 'inv_123';
  payload['chatGuid'] = 'chat_456';

  return payload;
}

void validateAPNSPayload(Map<String, dynamic> payload) {
  print('🔍 Validating APNS Payload Structure...');

  // Check if aps exists
  if (!payload.containsKey('aps')) {
    print('❌ Missing aps dictionary');
    return;
  }

  final aps = payload['aps'] as Map<String, dynamic>;
  print('✅ aps dictionary found');

  // Check aps contains only valid keys
  final validKeys = [
    'alert',
    'badge',
    'sound',
    'category',
    'content-available'
  ];
  bool hasInvalidKeys = false;

  aps.forEach((key, value) {
    if (!validKeys.contains(key)) {
      print('❌ Invalid key in aps: $key');
      hasInvalidKeys = true;
    }
  });

  if (!hasInvalidKeys) {
    print('✅ aps contains only valid system keys');
  }

  // Check custom data is outside aps
  final customKeys =
      payload.keys.where((key) => key != 'aps' && key != 'session_id');
  if (customKeys.isNotEmpty) {
    print('✅ Custom data found outside aps: ${customKeys.join(', ')}');
  }

  // Check payload size
  final jsonString = json.encode(payload);
  final sizeInBytes = utf8.encode(jsonString).length;
  print('📏 Payload size: $sizeInBytes bytes');

  if (sizeInBytes < 4000) {
    print('✅ Payload size is within 4KB limit');
  } else {
    print('⚠️ Payload size exceeds 4KB limit');
  }

  print('\n🎉 APNS Payload validation complete!');
}
