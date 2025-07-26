import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class QRImageUploadWidget extends StatefulWidget {
  final Function(String) onQRCodeExtracted;
  final VoidCallback? onCancel;

  const QRImageUploadWidget({
    Key? key,
    required this.onQRCodeExtracted,
    this.onCancel,
  }) : super(key: key);

  @override
  State<QRImageUploadWidget> createState() => _QRImageUploadWidgetState();
}

class _QRImageUploadWidgetState extends State<QRImageUploadWidget> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Upload QR Code'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            print('📱 QRImageUploadWidget: Close button pressed');
            // Call the onCancel callback first if provided
            try {
              widget.onCancel?.call();
            } catch (e) {
              print('Error in onCancel callback: $e');
            }

            // Then navigate back
            if (context.mounted) {
              print('📱 QRImageUploadWidget: Navigating back');
              Navigator.of(context).pop();
            } else {
              print(
                  '📱 QRImageUploadWidget: Context not mounted, cannot navigate');
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Instructions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF232323),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFF6B35).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.upload_file,
                    size: 48,
                    color: const Color(0xFFFF6B35),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Upload QR Code Image',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select an image containing a QR code to extract contact information',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Upload Options
            Row(
              children: [
                Expanded(
                  child: _buildUploadOption(
                    icon: Icons.photo_library,
                    title: 'Gallery',
                    subtitle: 'Choose from photos',
                    onTap: _pickFromGallery,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildUploadOption(
                    icon: Icons.camera_alt,
                    title: 'Camera',
                    subtitle: 'Take a photo',
                    onTap: _pickFromCamera,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Selected Image Preview
            if (_selectedImage != null) ...[
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: const Color(0xFF232323),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.grey.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    _selectedImage!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Error Message
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Buttons
            if (_selectedImage != null) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _processImage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B35),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Extract QR Code',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isProcessing ? null : _clearSelection,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey,
                        side: const BorderSide(color: Colors.grey),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Clear',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Tips
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF232323),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: Color(0xFFFF6B35),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Tips for better results:',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Ensure the QR code is clearly visible\n'
                    '• Avoid blurry or low-quality images\n'
                    '• Make sure the QR code is not partially cut off\n'
                    '• Good lighting helps with accuracy',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
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

  Widget _buildUploadOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isProcessing ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isProcessing
                ? Colors.grey.withOpacity(0.1)
                : Colors.grey.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            _isProcessing
                ? const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
                    ),
                  )
                : Icon(
                    icon,
                    color: const Color(0xFFFF6B35),
                    size: 32,
                  ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: _isProcessing ? Colors.grey : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _isProcessing ? 'Processing...' : subtitle,
              style: TextStyle(
                color:
                    _isProcessing ? Colors.grey.withOpacity(0.7) : Colors.grey,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    try {
      setState(() {
        _isProcessing = true;
        _errorMessage = null;
      });

      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _errorMessage = null;
        });
        print(
            '📱 QRImageUploadWidget: Image selected from gallery: ${image.path}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to pick image: $e';
      });
      print('📱 QRImageUploadWidget: Error picking image from gallery: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      setState(() {
        _isProcessing = true;
        _errorMessage = null;
      });

      // Request camera permission
      final status = await Permission.camera.request();
      if (status != PermissionStatus.granted) {
        setState(() {
          _errorMessage =
              'Camera permission is required. Please enable camera access in Settings.';
        });

        // Show permission dialog
        if (mounted) {
          _showCameraPermissionDialog();
        }
        return;
      }

      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _errorMessage = null;
        });
        print(
            '📱 QRImageUploadWidget: Image captured from camera: ${image.path}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to take photo: $e';
      });
      print('📱 QRImageUploadWidget: Error capturing image from camera: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _processImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // For now, we'll simulate QR code extraction
      // In a real implementation, you would use a QR code detection library
      await Future.delayed(const Duration(seconds: 2));

      // Simulate finding a QR code
      // TODO: Replace with actual QR code extraction
      final qrData =
          '{"sessionId":"4FwwxILKeI1PfI272OO7OyU9Ni5KFmsk4LF5I4pRHDg","displayName":"TestUser","timestamp":1753156120920}';

      // Call the callback with timeout protection
      try {
        await widget.onQRCodeExtracted(qrData).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw Exception('QR processing timeout');
          },
        );

        // Only navigate back if the callback completed successfully
        if (mounted && context.mounted) {
          print(
              '📱 QRImageUploadWidget: QR processing completed, navigating back');
          Navigator.of(context).pop();
        }
      } catch (e) {
        print('QR processing error: $e');
        // Don't navigate back on error, let user try again
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'No QR code found in the image. Please try a different image.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedImage = null;
      _errorMessage = null;
    });
  }

  void _showCameraPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF232323),
        title: const Text(
          'Camera Permission Required',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Camera access is required to take photos of QR codes.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            const Text(
              'To enable camera access:',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Go to Settings > SeChat\n'
              '2. Tap "Camera"\n'
              '3. Enable "Allow SeChat to Access Camera"',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text(
              'Open Settings',
              style: TextStyle(color: Color(0xFFFF6B35)),
            ),
          ),
        ],
      ),
    );
  }
}
