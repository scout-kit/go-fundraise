import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:go_fundraise/core/database/database.dart';

/// Provider for photos by fundraiser
final photosProvider =
    StreamProvider.family<List<Photo>, String>((ref, fundraiserId) {
  final db = ref.watch(databaseProvider);
  return db.watchPhotosByFundraiser(fundraiserId);
});

/// Provider for photo by fundraiser item ID (returns single photo or null)
final photoByItemIdProvider =
    StreamProvider.family<Photo?, String>((ref, fundraiserItemId) {
  final db = ref.watch(databaseProvider);
  return db.watchPhotoByFundraiserItemId(fundraiserItemId);
});

/// Provider for photo counts by item ID for a fundraiser
final photoCountsByItemIdProvider =
    FutureProvider.family<Map<String, int>, String>((ref, fundraiserId) async {
  final db = ref.watch(databaseProvider);
  return db.getPhotoCountsByItemId(fundraiserId);
});

/// Provider for photo operations
final photoServiceProvider = Provider((ref) {
  final db = ref.watch(databaseProvider);
  return PhotoService(db);
});

class PhotoService {
  final AppDatabase _db;
  final _uuid = const Uuid();
  final _picker = ImagePicker();

  PhotoService(this._db);

  /// Get the photos directory for a fundraiser (native only)
  Future<Directory> _getPhotosDir(String fundraiserId) async {
    if (kIsWeb) {
      throw UnsupportedError('File system not available on web');
    }
    final appDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${appDir.path}/photos/$fundraiserId');
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    return photosDir;
  }

  /// Get full path or data URL for a photo
  Future<String> getPhotoPath(String fundraiserId, String relativePath) async {
    if (kIsWeb) {
      // On web, the path is already a data URL
      return relativePath;
    }
    final photosDir = await _getPhotosDir(fundraiserId);
    return '${photosDir.path}/$relativePath';
  }

  /// Check if a path is a data URL (for web)
  bool isDataUrl(String path) {
    return path.startsWith('data:');
  }

  /// Get image bytes from path or data URL
  Future<Uint8List?> getPhotoBytes(String fundraiserId, String path) async {
    if (isDataUrl(path)) {
      // Parse base64 from data URL
      final base64Data = path.split(',').last;
      return base64Decode(base64Data);
    } else if (!kIsWeb) {
      final fullPath = await getPhotoPath(fundraiserId, path);
      final file = File(fullPath);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    }
    return null;
  }

  /// Take a photo with the camera (or pick from gallery on web)
  Future<Photo?> takePhoto(
    String fundraiserId, {
    String? caption,
    String? fundraiserItemId,
  }) async {
    final XFile? image;

    if (kIsWeb) {
      // On web, camera may not work well, use gallery as fallback
      image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
      );
    } else {
      image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
      );
    }

    if (image == null) return null;

    return _savePhotoFromXFile(
      fundraiserId,
      image,
      caption: caption,
      fundraiserItemId: fundraiserItemId,
    );
  }

  /// Pick a photo from gallery
  Future<Photo?> pickPhoto(
    String fundraiserId, {
    String? caption,
    String? fundraiserItemId,
  }) async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );

    if (image == null) return null;

    return _savePhotoFromXFile(
      fundraiserId,
      image,
      caption: caption,
      fundraiserItemId: fundraiserItemId,
    );
  }

  /// Save a photo from XFile (works on both web and native)
  Future<Photo> _savePhotoFromXFile(
    String fundraiserId,
    XFile xFile, {
    String? caption,
    String? fundraiserItemId,
  }) async {
    final photoId = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    String filePath;
    String? thumbnailPath;

    if (kIsWeb) {
      // On web, store as base64 data URL
      final bytes = await xFile.readAsBytes();
      final base64Data = base64Encode(bytes);
      filePath = 'data:image/jpeg;base64,$base64Data';
      // Use same data for thumbnail on web (no compression)
      thumbnailPath = filePath;
    } else {
      // On native, save to file system
      final photosDir = await _getPhotosDir(fundraiserId);
      final fileName = '$photoId.jpg';
      final targetPath = '${photosDir.path}/$fileName';

      // Copy file to photos directory
      final bytes = await xFile.readAsBytes();
      await File(targetPath).writeAsBytes(bytes);

      // Generate thumbnail (just copy for now)
      final thumbFileName = '${photoId}_thumb.jpg';
      final thumbPath = '${photosDir.path}/$thumbFileName';
      await File(thumbPath).writeAsBytes(bytes);

      filePath = fileName;
      thumbnailPath = thumbFileName;
    }

    // Save to database
    await _db.insertPhoto(PhotosCompanion.insert(
      id: photoId,
      fundraiserId: fundraiserId,
      filePath: filePath,
      caption: Value(caption),
      fundraiserItemId: Value(fundraiserItemId),
      thumbnailPath: Value(thumbnailPath),
      createdAt: now,
    ));

    return Photo(
      id: photoId,
      fundraiserId: fundraiserId,
      filePath: filePath,
      caption: caption,
      fundraiserItemId: fundraiserItemId,
      thumbnailPath: thumbnailPath,
      createdAt: now,
    );
  }

  /// Update photo caption
  Future<void> updateCaption(Photo photo, String? caption) async {
    await _db.updatePhoto(photo.copyWith(caption: Value(caption)));
  }

  /// Update photo's fundraiser item association
  Future<void> updateFundraiserItemId(
    Photo photo,
    String? fundraiserItemId,
  ) async {
    await _db.updatePhotoFundraiserItemId(photo.id, fundraiserItemId);
  }

  /// Delete a photo
  Future<void> deletePhoto(Photo photo) async {
    if (!kIsWeb) {
      // Delete files on native
      final photosDir = await _getPhotosDir(photo.fundraiserId);
      final file = File('${photosDir.path}/${photo.filePath}');
      if (await file.exists()) {
        await file.delete();
      }
      if (photo.thumbnailPath != null && !isDataUrl(photo.thumbnailPath!)) {
        final thumb = File('${photosDir.path}/${photo.thumbnailPath}');
        if (await thumb.exists()) {
          await thumb.delete();
        }
      }
    }

    // Delete from database
    await _db.deletePhoto(photo.id);
  }

  /// Delete existing photo for an item and take a new one (replace)
  Future<Photo?> replacePhotoForItem(
    String fundraiserId,
    String fundraiserItemId,
  ) async {
    // First, get and delete existing photo for this item
    final existingPhoto = await _db.getPhotoByFundraiserItemId(fundraiserItemId);

    if (existingPhoto != null) {
      // Delete file on native
      if (!kIsWeb) {
        final photosDir = await _getPhotosDir(fundraiserId);
        if (!isDataUrl(existingPhoto.filePath)) {
          final file = File('${photosDir.path}/${existingPhoto.filePath}');
          if (await file.exists()) {
            await file.delete();
          }
        }
        if (existingPhoto.thumbnailPath != null &&
            !isDataUrl(existingPhoto.thumbnailPath!)) {
          final thumb = File('${photosDir.path}/${existingPhoto.thumbnailPath}');
          if (await thumb.exists()) {
            await thumb.delete();
          }
        }
      }

      // Delete from database
      await _db.deletePhoto(existingPhoto.id);
    }

    // Now take the new photo
    return takePhoto(
      fundraiserId,
      fundraiserItemId: fundraiserItemId,
    );
  }
}
