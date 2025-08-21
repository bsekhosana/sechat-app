# SeChat Privacy Policy

**Last updated:** August 20, 2025

## Introduction
SeChat ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how we handle your information when you use our mobile application and how our new channel-based architecture ensures complete privacy.

## Important: Complete Privacy Protection
**SeChat provides complete end-to-end encryption with zero data access by our servers.** Our new channel-based architecture ensures that all user data remains completely private and encrypted.

## How SeChat Works

### Channel-Based Real-Time Communication
- **Session Channels**: Each user joins their personal session channel for secure communication
- **Targeted Delivery**: Events are only sent to relevant recipients, not broadcast globally
- **No Data Storage**: Messages are transmitted in real-time but never stored on our servers
- **End-to-End Encryption**: All user data is encrypted before transmission
- **Server Privacy**: Our servers cannot read encrypted message content or user status

### Encryption Architecture
- **Local Encryption**: All user data is encrypted on your device before sending
- **KER Handshake**: Only key exchange events are unencrypted for public key sharing
- **Encrypted Events**: Typing indicators, messages, and presence updates are fully encrypted
- **Server Blindness**: Our servers act as secure routers without access to message content
- **Local Decryption**: All data is decrypted locally on recipient devices

### Local Notifications
- **Background Wake-up**: SeChat can wake up from background using Flutter local notifications
- **No Push Services**: We do not use FCM (Firebase Cloud Messaging) or APNS (Apple Push Notification Service)
- **Device-Only**: Notifications are generated and displayed entirely on your device
- **No External Services**: No third-party notification services are involved

## What We Do NOT Do
- ❌ **No data collection** from your device
- ❌ **No message storage** on our servers
- ❌ **No user profiling** or tracking
- ❌ **No analytics** or usage statistics
- ❌ **No third-party data sharing**
- ❌ **No camera or media access**
- ❌ **No file uploads** to external servers
- ❌ **No reading of encrypted content** by our servers

## What We Do
- ✅ **Channel-based messaging** via secure Socket.IO connection
- ✅ **End-to-end encryption** for all user data
- ✅ **Targeted event delivery** to specific recipients only
- ✅ **Local data storage** on your device only
- ✅ **Local notifications** for new messages
- ✅ **Secure routing** without data access
- ✅ **No external dependencies** for core functionality

## Data Security & Privacy

### Encryption Levels
- **User Data**: 100% encrypted (messages, typing indicators, presence updates)
- **Routing Data**: Only conversation IDs visible to servers for message delivery
- **KER Events**: Unencrypted public keys for establishing encrypted communication
- **Server Access**: Zero access to encrypted message content or user status

### Channel Security
- **Session Isolation**: Users only receive events for their authorized channels
- **No Cross-Channel Access**: Events cannot be accessed by unauthorized users
- **Automatic Cleanup**: Old events are automatically removed for performance
- **Connection Validation**: All events validated against user sessions

### Server Role
- **Secure Router**: Servers only handle event routing, not content
- **No Data Access**: Cannot read, store, or analyze encrypted payloads
- **Privacy by Design**: Built to respect user privacy at every level
- **Audit Trail**: Only logs routing information, never content

## Your Privacy Rights
Since we don't collect any data and cannot access encrypted content:
- **No data to access** - everything stays on your device
- **No data to correct** - you control all your information
- **No data to delete** - we have nothing to delete
- **No data to transfer** - we have nothing to transfer
- **Complete encryption** - we cannot read your messages

## Children's Privacy
SeChat is not intended for children under 13. Since we don't collect any data and all communication is encrypted, there are no privacy concerns for any age group.

## Changes to This Policy
We may update this Privacy Policy from time to time. We will notify you of any changes by posting the new policy in the app.

## Contact Us
If you have questions about this Privacy Policy, please contact us at:
- Email: [Your Contact Email]
- Website: [Your Website]

## Consent
By using SeChat, you acknowledge that:
1. No personal data is collected or transmitted
2. All user data is encrypted end-to-end
3. Our servers cannot read encrypted message content
4. All data remains on your device
5. We use only local notifications (no push services)
6. Communication is via encrypted channel-based WebSocket only

## Technical Summary

### New Channel-Based Architecture
- **App Type**: Local messaging application with channel-based WebSocket bridge
- **Data Storage**: 100% local device storage
- **Notifications**: Flutter local notifications only
- **Communication**: Encrypted channel-based Socket.IO real-time messaging
- **Privacy**: Zero data collection, zero external storage, zero server access to content

### Security Features
- **Channel Isolation**: Events only delivered to authorized recipients
- **End-to-End Encryption**: All user data encrypted before transmission
- **Server Privacy**: Servers act as secure routers without data access
- **Session Management**: Secure user session tracking and validation
- **Event Logging**: Only routing information logged, never content

### Encryption Details
- **Algorithm**: AES-256-CBC with PKCS7 padding
- **Key Exchange**: RSA-based public key sharing for encrypted communication
- **Local Processing**: All encryption/decryption happens on user devices
- **Integrity Checks**: SHA-256 checksums for data integrity verification

This architecture ensures that SeChat provides the highest level of privacy and security while maintaining real-time communication capabilities.
