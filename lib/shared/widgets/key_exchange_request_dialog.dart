import 'package:flutter/material.dart';
import 'dart:convert';
import '../../core/utils/guid_generator.dart';
import '../../core/services/se_session_service.dart';
import '../../features/key_exchange/providers/key_exchange_request_provider.dart';
import '../widgets/custom_textfield.dart';
import '../widgets/custom_elevated_button.dart';

class KeyExchangeRequestDialog extends StatefulWidget {
  const KeyExchangeRequestDialog({super.key});

  @override
  State<KeyExchangeRequestDialog> createState() =>
      _KeyExchangeRequestDialogState();
}

class _KeyExchangeRequestDialogState extends State<KeyExchangeRequestDialog> {
  final TextEditingController _sessionIdController = TextEditingController();

  String _selectedPhrase = 'Footsteps in familiar rain';
  bool _isLoading = false;
  String? _sessionIdError;

  // Key request body phrases
  final List<String> _keyRequestPhrases = [
    'Footsteps in familiar rain',
    'The echo of shared laughter',
    'Shadows know my secret path',
    'Between the lines we spoke',
    'A song only you recall',
    'Lantern in the midnight fog',
    'Traces of yesterday\'s promise',
    'Whispers from our hidden shore',
    'The compass points to us',
    'Pages from our quiet story',
    'Star that marked our night',
    'Where the river met the sky',
    'Leaves falling where we stood',
    'The bridge we never crossed',
    'Coffee at the corner table',
    'A tune we both forgot',
    'The smile behind the mask',
    'Our footprints fade, but remain',
    'The key under the doormat',
    'Light in the locked room',
  ];

  @override
  void dispose() {
    _sessionIdController.dispose();
    super.dispose();
  }

  Future<void> _validateAndSubmit() async {
    setState(() {
      _isLoading = true;
      _sessionIdError = null;
    });

    try {
      // Validate session ID
      if (_sessionIdController.text.trim().isEmpty) {
        setState(() {
          _sessionIdError = 'Session ID is required';
        });
        return;
      }

      if (!GuidGenerator.isValidSessionGuid(
          _sessionIdController.text.trim())) {
        setState(() {
          _sessionIdError = 'Invalid session ID format';
        });
        return;
      }

      // Check for self-request
      final currentSessionId = SeSessionService().currentSessionId;
      if (_sessionIdController.text.trim() == currentSessionId) {
        setState(() {
          _sessionIdError = 'Cannot send key exchange request to yourself';
        });
        return;
      }

      // Send key exchange request
      final keyExchangeProvider = KeyExchangeRequestProvider();
      final success = await keyExchangeProvider.sendKeyExchangeRequest(
        _sessionIdController.text.trim(),
        requestPhrase: _selectedPhrase,
      );

      if (success && mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Key exchange request sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending invitation: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double height = MediaQuery.of(context).size.height;
    double width = MediaQuery.of(context).size.width;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: height * 0.95,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            // Header - Fixed at top
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  // Close button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.grey,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Icon
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.person_add,
                      color: Color(0xFFFF6B35),
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Title
                  Text(
                    'Send Key Exchange Request',
                    style: TextStyle(
                      fontSize: width * 0.06,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Subtitle
                  Text(
                    'Request a secure connection with another user',
                    style: TextStyle(
                      fontSize: width * 0.04,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // Content - Scrollable
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  children: [
                    // Session ID Field
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Session ID',
                            style: TextStyle(
                              fontSize: width * 0.035,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 16),
                          CustomTextfield(
                            controller: _sessionIdController,
                            label: 'Enter Session ID',
                            icon: Icons.person,
                            validator: (value) {
                              if (_sessionIdError != null)
                                return _sessionIdError;
                              return null;
                            },
                            onChanged: (value) {
                              if (_sessionIdError != null) {
                                setState(() {
                                  _sessionIdError = null;
                                });
                              }
                            },
                          ),

                          // Error display for session ID
                          if (_sessionIdError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _sessionIdError!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                ),
                              ),
                            ),

                          const SizedBox(height: 16),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Key Request Phrase Selection
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Request Phrase',
                            style: TextStyle(
                              fontSize: width * 0.035,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            icon: Icon(
                              Icons.arrow_drop_down,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            value: _selectedPhrase,
                            dropdownColor: Colors.white,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            items: _keyRequestPhrases.map((String phrase) {
                              return DropdownMenuItem<String>(
                                value: phrase,
                                child: Text(
                                  phrase,
                                  style: TextStyle(
                                    fontSize: width * 0.035,
                                    color: Colors.black.withValues(alpha: 0.8),
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedPhrase = newValue;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // Action Buttons - Fixed at bottom
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: CustomElevatedButton(
                      text: 'Cancel',
                      icon: Icons.close,
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      isPrimary: false,
                      isLoading: false,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: CustomElevatedButton(
                      text: 'Send Request',
                      icon: Icons.key,
                      onPressed: _isLoading
                          ? () {}
                          : () {
                              _validateAndSubmit().catchError((error) {
                                // Error handling is already done in _validateAndSubmit
                              });
                            },
                      isLoading: _isLoading,
                      isPrimary: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
