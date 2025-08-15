import 'package:flutter/material.dart';
import '../services/contact_message_service.dart'
    show ContactData, PhoneNumber, PhoneType, EmailAddress, EmailType;

/// Widget for selecting different media types to share
class InputMediaSelector extends StatelessWidget {
  final Function(String) onImageSelected;
  final Function(String) onVideoSelected;
  final Function(String) onDocumentSelected;
  final Function(double, double) onLocationShared;
  final Function(ContactData) onContactShared;
  final VoidCallback onClose;

  const InputMediaSelector({
    super.key,
    required this.onImageSelected,
    required this.onVideoSelected,
    required this.onDocumentSelected,
    required this.onLocationShared,
    required this.onContactShared,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  'Share Media',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onClose,
                  icon: Icon(
                    Icons.close,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),

          // Media options grid
          Expanded(
            child: GridView.count(
              crossAxisCount: 4,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: [
                _buildMediaOption(
                  context,
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  color: Colors.blue,
                  onTap: () => _selectFromCamera(context),
                ),
                _buildMediaOption(
                  context,
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  color: Colors.green,
                  onTap: () => _selectFromGallery(context),
                ),
                _buildMediaOption(
                  context,
                  icon: Icons.videocam,
                  label: 'Video',
                  color: Colors.red,
                  onTap: () => _selectVideo(context),
                ),
                _buildMediaOption(
                  context,
                  icon: Icons.description,
                  label: 'Document',
                  color: Colors.orange,
                  onTap: () => _selectDocument(context),
                ),
                _buildMediaOption(
                  context,
                  icon: Icons.location_on,
                  label: 'Location',
                  color: Colors.purple,
                  onTap: () => _shareLocation(context),
                ),
                _buildMediaOption(
                  context,
                  icon: Icons.person_add,
                  label: 'Contact',
                  color: Colors.teal,
                  onTap: () => _shareContact(context),
                ),
                _buildMediaOption(
                  context,
                  icon: Icons.folder,
                  label: 'Files',
                  color: Colors.indigo,
                  onTap: () => _selectFiles(context),
                ),
                _buildMediaOption(
                  context,
                  icon: Icons.more_horiz,
                  label: 'More',
                  color: Colors.grey,
                  onTap: () => _showMoreOptions(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build individual media option
  Widget _buildMediaOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withOpacity(0.3),
              ),
            ),
            child: Icon(
              icon,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Select image from camera
  void _selectFromCamera(BuildContext context) {
    // TODO: Integrate with camera service
    print('📷 Opening camera...');

    // Simulate camera selection
    Future.delayed(const Duration(seconds: 1), () {
      onImageSelected('/path/to/captured/image.jpg');
    });
  }

  /// Select image from gallery
  void _selectFromGallery(BuildContext context) {
    // TODO: Integrate with gallery picker service
    print('🖼️ Opening gallery...');

    // Simulate gallery selection
    Future.delayed(const Duration(seconds: 1), () {
      onImageSelected('/path/to/selected/image.jpg');
    });
  }

  /// Select video
  void _selectVideo(BuildContext context) {
    // TODO: Integrate with video picker service
    print('🎥 Opening video picker...');

    // Simulate video selection
    Future.delayed(const Duration(seconds: 1), () {
      onVideoSelected('/path/to/selected/video.mp4');
    });
  }

  /// Select document
  void _selectDocument(BuildContext context) {
    // TODO: Integrate with document picker service
    print('📄 Opening document picker...');

    // Simulate document selection
    Future.delayed(const Duration(seconds: 1), () {
      onDocumentSelected('/path/to/selected/document.pdf');
    });
  }

  /// Share location
  void _shareLocation(BuildContext context) {
    // TODO: Integrate with location service
    print('📍 Getting current location...');

    // Simulate location sharing
    Future.delayed(const Duration(seconds: 1), () {
      onLocationShared(37.7749, -122.4194); // San Francisco coordinates
    });
  }

  /// Share contact
  void _shareContact(BuildContext context) {
    // TODO: Integrate with contact picker service
    print('👤 Opening contact picker...');

    // Simulate contact selection
    Future.delayed(const Duration(seconds: 1), () {
      onContactShared(ContactData(
        displayName: 'John Doe',
        firstName: 'John',
        lastName: 'Doe',
        phoneNumbers: [
          PhoneNumber(number: '+1234567890', type: PhoneType.mobile)
        ],
        emailAddresses: [
          EmailAddress(
              address: 'john.doe@example.com', type: EmailType.personal)
        ],
      ));
    });
  }

  /// Select files
  void _selectFiles(BuildContext context) {
    // TODO: Integrate with file picker service
    print('📁 Opening file picker...');

    // Simulate file selection
    Future.delayed(const Duration(seconds: 1), () {
      onDocumentSelected('/path/to/selected/file.txt');
    });
  }

  /// Show more options
  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _buildMoreOptionsSheet(context),
    );
  }

  /// Build more options bottom sheet
  Widget _buildMoreOptionsSheet(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // More options
          ListTile(
            leading: Icon(
              Icons.poll,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Poll'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement poll creation
              print('📊 Creating poll...');
            },
          ),

          ListTile(
            leading: Icon(
              Icons.schedule,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Schedule Message'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement message scheduling
              print('⏰ Scheduling message...');
            },
          ),

          ListTile(
            leading: Icon(
              Icons.gif,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('GIF'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement GIF selection
              print('🎭 Selecting GIF...');
            },
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
