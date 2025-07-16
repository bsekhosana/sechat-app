import 'package:flutter/material.dart';
import '../../../core/services/socket_service.dart';

class SocketTestScreen extends StatefulWidget {
  const SocketTestScreen({super.key});

  @override
  State<SocketTestScreen> createState() => _SocketTestScreenState();
}

class _SocketTestScreenState extends State<SocketTestScreen> {
  final List<String> _logMessages = [];
  final SocketService _socketService = SocketService.instance;

  @override
  void initState() {
    super.initState();
    _setupSocketListeners();
    _addLogMessage('Socket test screen initialized');
  }

  void _setupSocketListeners() {
    _socketService.onConnected = () {
      _addLogMessage('✅ Connected to Socket.IO server');
    };

    _socketService.onDisconnected = () {
      _addLogMessage('❌ Disconnected from Socket.IO server');
    };

    _socketService.onError = (error) {
      _addLogMessage('⚠️ Socket error: $error');
    };

    _socketService.onChatMessageReceived = (data) {
      _addLogMessage('💬 Message received: ${data['message']}');
    };

    _socketService.onUserOnline = (data) {
      _addLogMessage('🟢 User online: ${data['userId']}');
    };

    _socketService.onUserOffline = (data) {
      _addLogMessage('🔴 User offline: ${data['userId']}');
    };
  }

  void _addLogMessage(String message) {
    setState(() {
      _logMessages
          .add('${DateTime.now().toString().substring(11, 19)}: $message');
      if (_logMessages.length > 50) {
        _logMessages.removeAt(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Socket.IO Test'),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: Column(
        children: [
          // Connection status
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Icon(
                  _socketService.isConnected ? Icons.wifi : Icons.wifi_off,
                  color: _socketService.isConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  _socketService.isConnected ? 'Connected' : 'Disconnected',
                  style: TextStyle(
                    color:
                        _socketService.isConnected ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_socketService.isAuthenticated)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Authenticated',
                      style: TextStyle(color: Colors.green, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),

          // Control buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      _addLogMessage('🔄 Connecting...');
                      await _socketService.manualConnect();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Connect'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      _addLogMessage('🛑 Disconnecting...');
                      _socketService.manualDisconnect();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Disconnect'),
                  ),
                ),
              ],
            ),
          ),

          // Test buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      _addLogMessage('📤 Sending test message...');
                      _socketService.sendTestMessage();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Send Test Message'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _logMessages.clear();
                      });
                      _addLogMessage('🧹 Log cleared');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Clear Log'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Log messages
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Event Log:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _logMessages.length,
                      itemBuilder: (context, index) {
                        final message =
                            _logMessages[_logMessages.length - 1 - index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            message,
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
