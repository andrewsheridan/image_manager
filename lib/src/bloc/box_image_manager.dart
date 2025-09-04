import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:hive_ce/hive.dart';
import 'package:image/image.dart';
import 'package:image_manager/src/bloc/byte_count_formatter.dart';
import 'package:image_manager/src/bloc/string_extensions.dart';
import 'package:image_manager/src/model/image_result.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';

import '../model/compression_settings.dart';

class BoxImageManager extends ChangeNotifier {
  final FirebaseStorage _storage;
  final Box _box;
  final ImagePicker _imagePicker;

  final Logger _logger = Logger("ImageManager");

  /// The key for this will always be unix style path.
  /// Local images will just be the file name, firebase images will have the full path to the image.
  final Map<String, Uint8List> _imagesInMemory = {};
  final Set<String> _retrievingFromFirebase = {};
  final Map<String, int> _failedToRetrieveFiles = {};

  BoxImageManager({
    required FirebaseStorage storage,
    required Box imageCacheBox,
    required ImagePicker imagePicker,
  }) : _storage = storage,
       _box = imageCacheBox,
       _imagePicker = imagePicker;

  void _markFailed(String path) {
    _failedToRetrieveFiles[path] = (_failedToRetrieveFiles[path] ?? 0) + 1;
  }

  Uint8List? getLocalImage(String filePath) {
    final fileName = basename(filePath);

    _logger.fine("Retrieving image $fileName at $filePath");

    if (_imagesInMemory[fileName] != null) {
      _logger.fine("Using cached version of image $fileName.");
      return _imagesInMemory[fileName]!;
    }

    try {
      final boxBytes = _box.get(fileName);
      if (boxBytes is Uint8List) {
        _logger.fine("Successfully loaded $fileName from image cache box.");
        _imagesInMemory[fileName] = boxBytes;

        notifyListeners();
        return boxBytes;
      }

      if (boxBytes != null) {
        _logger.warning(
          "Retreived cache data at $fileName was not the correct format.",
        );
      }
    } catch (ex) {
      _markFailed(fileName);
      _logger.severe(
        "Failed to retrieve image $fileName from local storage.",
        ex,
      );
    }

    return null;
  }

  Future<Uint8List?> getFirebaseImage(String firebasePath) async {
    firebasePath = firebasePath.toUnixStyleSeparators();

    final localCopy = getLocalImage(firebasePath);

    if (localCopy != null) return localCopy;

    if ((_failedToRetrieveFiles[firebasePath] ?? 0) > 3) {
      _logger.warning(("Max retries hit for $firebasePath, not retrieving."));
      return null;
    }

    try {
      _retrievingFromFirebase.add(firebasePath);

      _logger.fine("Grabbing file $firebasePath from Firebase.");
      final ref = _storage.ref(firebasePath);
      final data = await ref.getData();

      if (data == null) {
        throw ("Could not find Firebase Storage entry at $firebasePath.");
      }

      await saveImageLocal(data, filePath: firebasePath);

      _logger.fine("Image for $firebasePath retrieved from database.");
      _retrievingFromFirebase.remove(firebasePath);
      return data;
    } catch (ex) {
      _logger.severe("Failed to import image $firebasePath from Firebase.", ex);
      _markFailed(firebasePath);
      _retrievingFromFirebase.remove(firebasePath);
      return null;
    }
  }

  Future<void> deleteLocalImage(String filePath) async {
    final fileName = basename(filePath);
    _logger.info("Deleting locally stored file $fileName at $filePath");

    _imagesInMemory.remove(fileName);
    notifyListeners();

    try {
      await _box.delete(fileName);
    } catch (ex) {
      _logger.severe("Failed to delete local file $fileName", ex);
    }
  }

  Future<void> deleteFirebaseImage(String firebasePath) async {
    _logger.info("Deleting cloud file at $firebasePath");
    await deleteLocalImage(firebasePath);

    try {
      await _storage.ref(firebasePath.toUnixStyleSeparators()).delete();
    } catch (ex) {
      _logger.severe("Failed to delete cloud file at $firebasePath", ex);
    }
  }

  Future<void> insertFirebaseFile(File file, String firebasePath) async {
    firebasePath = firebasePath.toUnixStyleSeparators();
    try {
      final bytes = await file.readAsBytes();
      _imagesInMemory[basename(firebasePath)] = bytes;
      notifyListeners();

      await _storage.ref(firebasePath.toUnixStyleSeparators()).putFile(file);
    } catch (ex) {
      _logger.severe(
        "Failed to upload file ${file.path} to $firebasePath.",
        ex,
      );
    }
  }

  Future<void> insertFirebaseData(
    Uint8List data,
    String firebasePath,
    String contentType,
  ) async {
    firebasePath = firebasePath.toUnixStyleSeparators();

    try {
      _imagesInMemory[basename(firebasePath)] = data;
      saveImageLocal(data, filePath: firebasePath);
      notifyListeners();
    } catch (ex) {
      _logger.warning(
        "Failed to cache and save image in uploadData() locally.",
      );
    }

    try {
      _logger.fine("Uploading data to $firebasePath of type $contentType.");

      final metadata = SettableMetadata(contentType: contentType);
      final ref = _storage.ref(firebasePath.toUnixStyleSeparators());
      await ref.putData(data, metadata);
    } catch (ex) {
      _logger.severe("Failed to upload data to $firebasePath.", ex);
    }
  }

  Future<void> insertFirebaseImage(Uint8List data, String firebasePath) async {
    return insertFirebaseData(
      data,
      firebasePath,
      getImageContentType(firebasePath),
    );
  }

  static String getImageContentType(
    String filePath, [
    String extensionFallback = ".png",
  ]) =>
      "image/${extension(filePath).withFallback(extensionFallback).split(".").last}";

  Future<bool> firebaseFileExists(String firebasePath) async {
    try {
      await _storage.ref(firebasePath).getDownloadURL();
      return true;
    } catch (ex) {
      return false;
    }
  }

  Future<Uint8List?> pickImageAsBytes() async {
    final pickedFile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
    );
    if (pickedFile == null) return null;

    return pickedFile.readAsBytes();
  }

  Future<ImageResult?> pickAndCopyImage({
    String? fileNameOverride,
    CompressionSettings? compressionSettings,
  }) async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (pickedFile == null) return null;

      Uint8List bytes = await pickedFile.readAsBytes();

      if (compressionSettings != null) {
        bytes = await compressImage(
          image: bytes,
          settings: compressionSettings,
        );
      }

      final fileName = fileNameOverride ?? basename(pickedFile.path);
      await _box.put(fileName, bytes);
      _imagesInMemory[fileName] = bytes;
      notifyListeners();

      return ImageResult(
        fileName: basename(pickedFile.path),
        imagePath: pickedFile.path,
        bytes: bytes,
      );
    } catch (ex) {
      _logger.severe("Failed to pick and copy image.", ex);
      rethrow;
    }
  }

  Future<ImageResult> saveImageLocal(
    Uint8List imageData, {
    String? filePath,
  }) async {
    final fileName = filePath == null
        ? "${DateTime.now().microsecondsSinceEpoch}.png"
        : basename(filePath);

    await _box.put(fileName, imageData);
    _imagesInMemory[fileName] = imageData;
    notifyListeners();

    _logger.fine("Successfully put $fileName in image cache box.");

    return ImageResult(
      fileName: fileName,
      imagePath: filePath ?? fileName,
      bytes: imageData,
    );
  }

  /// Throws String
  Future<Uint8List> compressImage({
    required Uint8List image,
    required CompressionSettings settings,
  }) async {
    Future<Size?> computeSize() async {
      final sizeRatio = settings.sizeRatio;
      if (sizeRatio != null) {
        final decoded = decodeImage(image);
        if (decoded == null) {
          return null;
        }
        return Size((decoded.width * sizeRatio), (decoded.height * sizeRatio));
      }
      return null;
    }

    final size = await computeSize();

    final result = await FlutterImageCompress.compressWithList(
      image,
      minHeight: size?.height.floor() ?? settings.minHeight ?? 128,
      minWidth: size?.width.floor() ?? settings.minWidth ?? 128,
      quality: settings.quality,
      format: settings.format.format,
    );

    final beforeLength = image.lengthInBytes;
    final afterLength = result.lengthInBytes;

    _logger.info(
      "Compressed from ${ByteCountFormatter.formatBytes(beforeLength)} to ${ByteCountFormatter.formatBytes(afterLength)}.",
    );

    if (beforeLength < afterLength) return image;

    return result;
  }
}
