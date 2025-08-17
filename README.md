# SeChat - Secure Text Messaging App

SeChat is a streamlined, secure text messaging application built with Flutter. It provides a clean, intuitive interface for private conversations with end-to-end encryption.

## Features

- **Text Messaging**: Send and receive text messages with a clean, modern interface
- **Keyboard Optimization**: Keyboard automatically hides after sending messages
- **Message Status**: Track when messages are sent, delivered, and read
- **Typing Indicators**: See when your contacts are typing
- **Conversation Management**: Easily manage your chat conversations
- **Notification Support**: Receive notifications for new messages
- **Dark Mode**: Comfortable dark theme for all screens

## Technical Details

- **Framework**: Flutter
- **Architecture**: Provider pattern for state management
- **Storage**: Local SQLite database for message persistence
- **Notifications**: Flutter Local Notifications + AirNotifier for push notifications
- **Security**: Text message encryption for privacy

## Getting Started

### Prerequisites

- Flutter 3.0.0 or higher
- Dart 2.17.0 or higher
- Android Studio / VS Code with Flutter extensions

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/sechat_app.git
```

2. Install dependencies:
```bash
cd sechat_app
flutter pub get
```

3. Run the app:
```bash
flutter run
```

## Project Structure

```
lib/
├── core/
│   ├── config/
│   └── services/
├── features/
│   ├── auth/
│   ├── chat/
│   │   ├── models/
│   │   ├── providers/
│   │   ├── screens/
│   │   ├── services/
│   │   └── widgets/
│   ├── key_exchange/
│   ├── notifications/
│   ├── profile/
│   └── settings/
└── shared/
    ├── models/
    └── widgets/
```

## License

This project is proprietary and confidential. Unauthorized copying, distribution, or use is strictly prohibited.

## Contact

For support or inquiries, please contact support@sechat.com.
