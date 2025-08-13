import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import '../../core/utils/guid_generator.dart';
import '../../core/services/se_session_service.dart';
import '../../core/services/qr_code_service.dart';
import '../../features/key_exchange/providers/key_exchange_request_provider.dart';
import '../widgets/custom_textfield.dart';
import '../widgets/custom_elevated_button.dart';
import 'qr_scanner_screen.dart';

class KeyExchangeRequestDialog extends StatefulWidget {
  const KeyExchangeRequestDialog({super.key});

  @override
  State<KeyExchangeRequestDialog> createState() =>
      _KeyExchangeRequestDialogState();
}

class _KeyExchangeRequestDialogState extends State<KeyExchangeRequestDialog> {
  final TextEditingController _sessionIdController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String _selectedMethod = 'session_id';
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
      // Validate session ID if using session_id method
      if (_selectedMethod == 'session_id') {
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
      }

      // Check for self-request
      final currentSessionId = SeSessionService().currentSessionId;
      if (_selectedMethod == 'session_id' &&
          _sessionIdController.text.trim() == currentSessionId) {
        setState(() {
          _sessionIdError = 'Cannot send key exchange request to yourself';
        });
        return;
      }

      // Send key exchange request
      final keyExchangeProvider = KeyExchangeRequestProvider();
      final success = await keyExchangeProvider.sendKeyExchangeRequest(
        _selectedMethod == 'session_id'
            ? _sessionIdController.text.trim()
            : '', // Will be set by QR processing
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

  Future<void> _scanQRCode() async {
    try {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => QRScannerScreen(
            onQRCodeScanned: (qrData) async {
              await _processQRData(qrData);
            },
            onCancel: () {
              // Handle cancellation
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening QR scanner: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadQRCode() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        await _processQRImage(image);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading QR code: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _processQRImage(XFile image) async {
    try {
      setState(() {
        _isLoading = true;
      });

      print('📱 InviteContactDialog: Processing QR image: ${image.path}');

      // Use real QR code processing service
      final String? qrData =
          await QRCodeService.instance.extractQRCodeFromImage(image.path);

      if (qrData != null) {
        print('📱 InviteContactDialog: QR code extracted: $qrData');

        // Process the QR data
        await _processQRData(qrData);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'No QR code found in the image. Please try a different image.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('📱 InviteContactDialog: Error processing QR image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing QR code: ${e.toString()}'),
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

  Future<void> _processQRData(String qrData) async {
    try {
      print('📱 InviteContactDialog: Processing QR data: $qrData');

      // Use QR code service to extract session ID
      final String? sessionId =
          await QRCodeService.instance.processQRCodeData(qrData);

      if (sessionId != null) {
        print('📱 InviteContactDialog: Valid session ID found: $sessionId');

        // Update the form
        setState(() {
          _sessionIdController.text = sessionId;
          _selectedMethod = 'session_id';
        });

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Session ID extracted: $sessionId'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        print('📱 InviteContactDialog: Invalid QR code data');

        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Invalid QR code. Please scan a valid SeChat QR code.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('📱 InviteContactDialog: Error processing QR data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing QR code: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildMethodOption(
      String method, IconData icon, String title, String subtitle) {
    final isSelected = _selectedMethod == method;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMethod = method;
        });

        // Handle QR code methods
        if (method == 'scan_qr') {
          _scanQRCode();
        } else if (method == 'upload_qr') {
          _uploadQRCode();
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF6B35).withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF6B35) : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFFF6B35).withValues(alpha: 0.2)
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isSelected ? const Color(0xFFFF6B35) : Colors.grey[600],
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFFFF6B35)
                          : Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: const Color(0xFFFF6B35),
                size: 20,
              ),
          ],
        ),
      ),
    );
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Icon
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(30),
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
                    // Method Selection
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
                          Column(
                            children: [
                              _buildMethodOption(
                                'session_id',
                                Icons.person,
                                'Session ID',
                                'Enter session ID manually',
                              ),
                              SizedBox(height: height * 0.02),
                              _buildMethodOption(
                                'scan_qr',
                                Icons.qr_code_scanner,
                                'Scan QR Code',
                                'Scan QR code with camera',
                              ),
                              SizedBox(height: height * 0.02),
                              _buildMethodOption(
                                'upload_qr',
                                Icons.upload_file,
                                'Upload QR Code',
                                'Upload QR code from gallery',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: height * 0.02),

                    // Session ID Field (only show for session_id method)
                    if (_selectedMethod == 'session_id')
                      Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                                bottom:
                                    MediaQuery.of(context).viewInsets.bottom),
                            child: CustomTextfield(
                              controller: _sessionIdController,
                              label: 'Session ID',
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

                            // dropdown meanu bg whit

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
