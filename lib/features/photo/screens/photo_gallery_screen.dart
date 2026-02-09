import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:go_fundraise/core/database/database.dart';
import 'package:go_fundraise/features/photo/providers/photo_provider.dart';
import 'package:go_fundraise/features/photo/widgets/item_picker_sheet.dart';

/// Provider to get a FundraiserItem by ID
final fundraiserItemByIdProvider =
    FutureProvider.family<FundraiserItem?, String>((ref, itemId) async {
  final db = ref.watch(databaseProvider);
  return db.getFundraiserItemById(itemId);
});

class PhotoGalleryScreen extends ConsumerWidget {
  final String fundraiserId;

  const PhotoGalleryScreen({super.key, required this.fundraiserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photosAsync = ref.watch(photosProvider(fundraiserId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Photos'),
      ),
      body: photosAsync.when(
        data: (photos) =>
            photos.isEmpty ? _buildEmptyState(context) : _buildGrid(context, ref, photos),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'gallery',
            onPressed: () => _pickFromGallery(ref),
            child: const Icon(Icons.photo_library),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'camera',
            onPressed: () => _takePhoto(ref),
            child: const Icon(Icons.camera_alt),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 24),
          Text(
            'No Photos Yet',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Take photos to help identify boxes and items',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, WidgetRef ref, List<Photo> photos) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];
        return _PhotoTile(
          photo: photo,
          fundraiserId: fundraiserId,
          onTap: () => _openViewer(context, ref, photos, index),
          onLongPress: () => _showPhotoOptions(context, ref, photo),
        );
      },
    );
  }

  void _openViewer(
    BuildContext context,
    WidgetRef ref,
    List<Photo> photos,
    int initialIndex,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _PhotoViewerScreen(
          photos: photos,
          initialIndex: initialIndex,
          fundraiserId: fundraiserId,
        ),
      ),
    );
  }

  void _showPhotoOptions(BuildContext context, WidgetRef ref, Photo photo) {
    final hasAssociation = photo.fundraiserItemId != null;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Show current association if exists
              if (hasAssociation)
              Consumer(
                builder: (context, ref, _) {
                  final itemAsync =
                      ref.watch(fundraiserItemByIdProvider(photo.fundraiserItemId!));
                  return itemAsync.when(
                    data: (item) => item != null
                        ? Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.link,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Linked to: ${item.productName}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
              ),
            ListTile(
              leading: Icon(
                Icons.link,
                color: hasAssociation ? null : Theme.of(context).colorScheme.primary,
              ),
              title: Text(hasAssociation ? 'Change Item Link' : 'Link to Item'),
              onTap: () {
                Navigator.pop(context);
                _linkToItem(context, ref, photo);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Caption'),
              onTap: () {
                Navigator.pop(context);
                _editCaption(context, ref, photo);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
              title: Text(
                'Delete Photo',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, ref, photo);
              },
            ),
          ],
          ),
        ),
      ),
    );
  }

  Future<void> _linkToItem(BuildContext context, WidgetRef ref, Photo photo) async {
    final result = await showItemPickerSheet(
      context: context,
      fundraiserId: fundraiserId,
      currentFundraiserItemId: photo.fundraiserItemId,
    );

    if (result != null) {
      final db = ref.read(databaseProvider);
      final photoService = ref.read(photoServiceProvider);

      // Check if unlinking
      if (result.fundraiserItemId == null) {
        await photoService.updateFundraiserItemId(photo, null);
        ref.invalidate(photoCountsByItemIdProvider(fundraiserId));
        return;
      }

      // Check if another photo is already linked to this item
      final existingPhoto =
          await db.getPhotoByFundraiserItemId(result.fundraiserItemId!);

      // If another photo exists (not this one), show confirmation
      if (existingPhoto != null && existingPhoto.id != photo.id) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Replace Existing Link?'),
            content: Text(
              'Another photo is already linked to "${result.displayName}". '
              'Only one photo can be linked per item.\n\n'
              'Do you want to unlink the existing photo and link this one instead?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Replace'),
              ),
            ],
          ),
        );

        if (confirmed != true) return;

        // Unlink the existing photo from this item
        await db.clearPhotoForFundraiserItem(result.fundraiserItemId!);
      }

      // Link the new photo
      await photoService.updateFundraiserItemId(photo, result.fundraiserItemId);

      // Invalidate photo counts to refresh
      ref.invalidate(photoCountsByItemIdProvider(fundraiserId));
    }
  }

  void _editCaption(BuildContext context, WidgetRef ref, Photo photo) {
    final controller = TextEditingController(text: photo.caption);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Caption'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Add a caption...',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(photoServiceProvider).updateCaption(
                    photo,
                    controller.text.isEmpty ? null : controller.text,
                  );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Photo photo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photo?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(photoServiceProvider).deletePhoto(photo);
              // Invalidate photo counts so items view updates
              ref.invalidate(photoCountsByItemIdProvider(fundraiserId));
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _takePhoto(WidgetRef ref) async {
    await ref.read(photoServiceProvider).takePhoto(fundraiserId);
  }

  Future<void> _pickFromGallery(WidgetRef ref) async {
    await ref.read(photoServiceProvider).pickPhoto(fundraiserId);
  }
}

class _PhotoTile extends ConsumerWidget {
  final Photo photo;
  final String fundraiserId;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PhotoTile({
    required this.photo,
    required this.fundraiserId,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasItemAssociation = photo.fundraiserItemId != null;
    final photoService = ref.read(photoServiceProvider);

    // Get item name if associated
    final itemAsync = hasItemAssociation
        ? ref.watch(fundraiserItemByIdProvider(photo.fundraiserItemId!))
        : null;

    return FutureBuilder<String>(
      future: photoService.getPhotoPath(
            fundraiserId,
            photo.thumbnailPath ?? photo.filePath,
          ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final path = snapshot.data!;
        final isDataUrl = photoService.isDataUrl(path);

        Widget imageWidget;
        if (isDataUrl) {
          // Web: decode base64 data URL
          final base64Data = path.split(',').last;
          final bytes = base64Decode(base64Data);
          imageWidget = Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Theme.of(context).colorScheme.errorContainer,
              child: const Icon(Icons.broken_image),
            ),
          );
        } else {
          // Native: use file
          imageWidget = Image.file(
            File(path),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Theme.of(context).colorScheme.errorContainer,
              child: const Icon(Icons.broken_image),
            ),
          );
        }

        return GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imageWidget,
              ),
              // Item association badge (top-left corner)
              if (hasItemAssociation && itemAsync != null)
                itemAsync.when(
                  data: (item) => item != null
                      ? Positioned(
                          top: 4,
                          left: 4,
                          right: 4,
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withOpacity(0.9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.inventory_2,
                                  size: 10,
                                  color:
                                      Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    item.productName,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              // Caption (bottom)
              if (photo.caption != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(8),
                      ),
                    ),
                    child: Text(
                      photo.caption!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PhotoViewerScreen extends ConsumerStatefulWidget {
  final List<Photo> photos;
  final int initialIndex;
  final String fundraiserId;

  const _PhotoViewerScreen({
    required this.photos,
    required this.initialIndex,
    required this.fundraiserId,
  });

  @override
  ConsumerState<_PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<_PhotoViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          photo.caption ?? 'Photo ${_currentIndex + 1} of ${widget.photos.length}',
        ),
      ),
      body: PhotoViewGallery.builder(
        pageController: _pageController,
        itemCount: widget.photos.length,
        builder: (context, index) {
          final photoService = ref.read(photoServiceProvider);
          return PhotoViewGalleryPageOptions.customChild(
            child: FutureBuilder<String>(
              future: photoService.getPhotoPath(
                    widget.fundraiserId,
                    widget.photos[index].filePath,
                  ),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }
                final path = snapshot.data!;
                final isDataUrl = photoService.isDataUrl(path);

                ImageProvider imageProvider;
                if (isDataUrl) {
                  final base64Data = path.split(',').last;
                  final bytes = base64Decode(base64Data);
                  imageProvider = MemoryImage(bytes);
                } else {
                  imageProvider = FileImage(File(path));
                }

                return PhotoView(
                  imageProvider: imageProvider,
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 3,
                );
              },
            ),
          );
        },
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        loadingBuilder: (context, event) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );
  }
}
