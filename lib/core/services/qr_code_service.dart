import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../utils/guid_generator.dart';

class QRCodeService {
  static QRCodeService? _instance;
  static QRCodeService get instance => _instance ??= QRCodeService._();

  QRCodeService._();

  /// Extract QR code data from an image file
  Future<String?> extractQRCodeFromImage(String imagePath) async {
    try {
      print('🔍 QRCodeService: Processing image: $imagePath');

      // Read the image file
      final File imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        print('🔍 QRCodeService: ❌ Image file does not exist');
        return null;
      }

      // Read image bytes
      final Uint8List imageBytes = await imageFile.readAsBytes();

      // Decode image
      final img.Image? image = img.decodeImage(imageBytes);
      if (image == null) {
        print('🔍 QRCodeService: ❌ Failed to decode image');
        return null;
      }

      print(
          '🔍 QRCodeService: Image decoded successfully (${image.width}x${image.height})');

      // Convert to grayscale for better QR detection
      final img.Image grayscaleImage = img.grayscale(image);

      // Try to detect QR code using image processing
      final String? qrData = await _detectQRCodeFromImage(grayscaleImage);

      if (qrData != null) {
        print('🔍 QRCodeService: ✅ QR code detected: $qrData');
        return qrData;
      }

      // If image processing fails, try with original image
      final String? qrDataOriginal = await _detectQRCodeFromImage(image);

      if (qrDataOriginal != null) {
        print(
            '🔍 QRCodeService: ✅ QR code detected (original): $qrDataOriginal');
        return qrDataOriginal;
      }

      print('🔍 QRCodeService: ❌ No QR code found in image');
      return null;
    } catch (e) {
      print('🔍 QRCodeService: ❌ Error processing image: $e');
      return null;
    }
  }

  /// Detect QR code from image using image processing
  Future<String?> _detectQRCodeFromImage(img.Image image) async {
    try {
      // Convert image to bytes for processing
      final Uint8List imageBytes = img.encodePng(image);

      // Create a temporary file for the processed image
      final Directory tempDir = Directory.systemTemp;
      final File tempFile = File('${tempDir.path}/temp_qr_image.png');
      await tempFile.writeAsBytes(imageBytes);

      // Try to scan QR code from the image
      final String? qrData = await _scanQRFromFile(tempFile.path);

      // Clean up temp file
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      return qrData;
    } catch (e) {
      print('🔍 QRCodeService: ❌ Error in QR detection: $e');
      return null;
    }
  }

  /// Scan QR code from file using QR scanner
  Future<String?> _scanQRFromFile(String filePath) async {
    try {
      // This is a simplified approach - in a real implementation,
      // you would use a more sophisticated QR detection library

      // For now, we'll use a basic approach to detect QR patterns
      final File file = File(filePath);
      final Uint8List bytes = await file.readAsBytes();

      // Convert to image and look for QR code patterns
      final img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;

      // Look for QR code finder patterns (the three corner squares)
      final String? qrData = _findQRPatterns(image);

      return qrData;
    } catch (e) {
      print('🔍 QRCodeService: ❌ Error scanning QR from file: $e');
      return null;
    }
  }

  /// Basic QR pattern detection (simplified)
  String? _findQRPatterns(img.Image image) {
    try {
      // This is a simplified QR detection
      // In a real implementation, you would use a proper QR library

      // For now, we'll look for high contrast patterns that might be QR codes
      final int width = image.width;
      final int height = image.height;

      // Look for potential QR code corners (high contrast areas)
      final List<Point> potentialCorners = _findPotentialCorners(image);

      if (potentialCorners.length >= 3) {
        // This might be a QR code - try to extract data
        return _extractQRDataFromCorners(image, potentialCorners);
      }

      return null;
    } catch (e) {
      print('🔍 QRCodeService: ❌ Error in QR pattern detection: $e');
      return null;
    }
  }

  /// Find potential QR code corners
  List<Point> _findPotentialCorners(img.Image image) {
    final List<Point> corners = [];
    final int width = image.width;
    final int height = image.height;

    // Look for high contrast areas that might be QR code corners
    for (int y = 0; y < height; y += 10) {
      for (int x = 0; x < width; x += 10) {
        if (_isPotentialCorner(image, x, y)) {
          corners.add(Point(x, y));
        }
      }
    }

    return corners;
  }

  /// Check if a point might be a QR code corner
  bool _isPotentialCorner(img.Image image, int x, int y) {
    try {
      if (x < 5 || y < 5 || x >= image.width - 5 || y >= image.height - 5) {
        return false;
      }

      // Check for high contrast in a small area
      final int centerPixel = _getPixelBrightness(image, x, y);
      int contrastCount = 0;

      for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
          if (dx == 0 && dy == 0) continue;

          final int neighborPixel = _getPixelBrightness(image, x + dx, y + dy);
          final int contrast = (centerPixel - neighborPixel).abs();

          if (contrast > 50) {
            // High contrast threshold
            contrastCount++;
          }
        }
      }

      return contrastCount >= 8; // At least 8 high-contrast neighbors
    } catch (e) {
      return false;
    }
  }

  /// Get pixel brightness (0-255)
  int _getPixelBrightness(img.Image image, int x, int y) {
    try {
      final img.Pixel pixel = image.getPixel(x, y);
      final int r = pixel.r.toInt();
      final int g = pixel.g.toInt();
      final int b = pixel.b.toInt();

      // Convert to grayscale brightness
      return (r * 0.299 + g * 0.587 + b * 0.114).round();
    } catch (e) {
      return 0;
    }
  }

  /// Extract QR data from detected corners (simplified)
  String? _extractQRDataFromCorners(img.Image image, List<Point> corners) {
    try {
      // This is a simplified approach
      // In a real implementation, you would decode the actual QR code data

      // For now, we'll return a placeholder
      // In practice, you would use a proper QR decoding library
      return null;
    } catch (e) {
      print('🔍 QRCodeService: ❌ Error extracting QR data: $e');
      return null;
    }
  }

  /// Validate if extracted data is a valid session ID
  bool isValidSessionId(String? data) {
    if (data == null || data.isEmpty) {
      return false;
    }

    // Check if it looks like a session ID
    if (data.startsWith('session_')) {
      return GuidGenerator.isValidSessionGuid(data);
    }

    // Try to extract session ID from JSON
    try {
      final Map<String, dynamic> jsonData = json.decode(data);
      final String? sessionId = jsonData['sessionId'] as String?;
      if (sessionId != null) {
        return GuidGenerator.isValidSessionGuid(sessionId);
      }
    } catch (e) {
      // Not JSON, continue checking
    }

    // Check if it's a valid session GUID directly
    return GuidGenerator.isValidSessionGuid(data);
  }

  /// Extract session ID from QR data
  String? extractSessionId(String qrData) {
    try {
      // Try to parse as JSON first
      final Map<String, dynamic> jsonData = json.decode(qrData);
      final String? sessionId = jsonData['sessionId'] as String?;
      if (sessionId != null && GuidGenerator.isValidSessionGuid(sessionId)) {
        return sessionId;
      }
    } catch (e) {
      // Not JSON, continue checking
    }

    // Check if the QR data itself is a session ID
    if (GuidGenerator.isValidSessionGuid(qrData)) {
      return qrData;
    }

    // Look for session ID pattern in the data
    final RegExp sessionPattern = RegExp(r'session_[a-zA-Z0-9\-_]+');
    final Match? match = sessionPattern.firstMatch(qrData);
    if (match != null) {
      final String sessionId = match.group(0)!;
      if (GuidGenerator.isValidSessionGuid(sessionId)) {
        return sessionId;
      }
    }

    return null;
  }

  /// Process QR code data and extract session ID
  Future<String?> processQRCodeData(String qrData) async {
    try {
      print('🔍 QRCodeService: Processing QR data: $qrData');

      // Extract session ID from QR data
      final String? sessionId = extractSessionId(qrData);

      if (sessionId != null) {
        print('🔍 QRCodeService: ✅ Valid session ID extracted: $sessionId');
        return sessionId;
      }

      print('🔍 QRCodeService: ❌ No valid session ID found in QR data');
      return null;
    } catch (e) {
      print('🔍 QRCodeService: ❌ Error processing QR data: $e');
      return null;
    }
  }
}

/// Simple Point class for coordinates
class Point {
  final int x;
  final int y;

  Point(this.x, this.y);

  @override
  String toString() => 'Point($x, $y)';
}
