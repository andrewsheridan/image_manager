import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:hive_ce/hive.dart';
import 'package:image/image.dart';
import 'package:image_manager/src/image_result.dart';
import 'package:image_manager/src/string_extensions.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';

import 'compression_settings.dart';
import 'file_factory.dart';

class ImageManager extends ChangeNotifier {
  final FirebaseStorage _storage;
  final Directory? _directory;
  final FileFactory _fileFactory;
  final Box? _box;

  final Logger _logger = Logger("ImageManager");

  /// The key for this will always be whatever format for the local filesystem is.
  final Map<String, Uint8List> _imagesInMemory = {};
  final Set<String> _retrievingFiles = {};
  final Map<String, int> _failedToRetrieveFiles = {};

  ImageManager({
    required FirebaseStorage storage,
    required Directory? directory,
    required FileFactory fileFactory,
    Box? imageCacheBox,
  }) : _storage = storage,
       _directory = directory,
       _fileFactory = fileFactory,
       _box = imageCacheBox;

  String getFullLocalFilePath(String fileName) => _directory == null
      ? fileName
      : join(_directory.path, fileName).toLocalPlatformSeparators();

  void _markFailed(String path) {
    _failedToRetrieveFiles[path] = (_failedToRetrieveFiles[path] ?? 0) + 1;
  }

  Uint8List? getLocalSync({
    required String fileName,
    required bool retrieveIfMissing,
  }) {
    final localFileName = fileName.toLocalPlatformSeparators();
    final output = _imagesInMemory[localFileName];
    if (output == null && retrieveIfMissing) {
      getLocalAsync(localFileName);
    }
    return output;
  }

  Uint8List? getFirebaseSync({
    required String firebasePath,
    required bool retrieveIfMissing,
  }) {
    final output = _imagesInMemory[firebasePath.toLocalPlatformSeparators()];
    if (output == null && retrieveIfMissing) {
      getFirebaseAsync(firebasePath);
    }
    return output;
  }

  Future<Uint8List?> getLocalAsync(String fileName) async {
    _logger.finest("getLocalAsync $fileName");
    final localPath = fileName.toLocalPlatformSeparators();

    Uint8List? bytes;

    try {
      _logger.fine("Retrieving image at $localPath.");

      if (_imagesInMemory[localPath] != null) {
        _logger.fine("Using cached version of image $localPath.");
        return _imagesInMemory[localPath]!;
      }

      if (_retrievingFiles.contains(localPath)) {
        _logger.fine(
          "Retrieval already initiated for image $localPath. Returning.",
        );
        return null;
      }

      _retrievingFiles.add(localPath);

      if (kIsWeb) {
        final boxBytes = _box!.get(localPath);
        if (boxBytes is Uint8List) {
          _logger.fine("Successfully loaded $fileName from image cache box.");
          _imagesInMemory[localPath] = boxBytes;
          bytes = boxBytes;
          notifyListeners();
        } else if (boxBytes == null) {
        } else {
          _logger.warning(
            "Retreived cache data at $fileName was not the correct format.",
          );
        }
      } else {
        final localStoragePath = getFullLocalFilePath(localPath);
        final localStorageFile = _fileFactory.fromPath(localStoragePath);

        if (await localStorageFile.exists()) {
          _logger.fine("Image for $localPath found locally.");
          bytes = await localStorageFile.readAsBytes();
          _imagesInMemory[localPath] = bytes;
          notifyListeners();
        }
      }
    } catch (ex) {
      _markFailed(localPath);
      _logger.severe(
        "Failed to retrieve image $localPath from local storage.",
        ex,
      );
    } finally {
      _retrievingFiles.remove(localPath);
    }

    return bytes;
  }

  Future<Uint8List?> getFirebaseAsync(String firebasePath) async {
    final localCopy = await getLocalAsync(firebasePath);

    if (localCopy != null) return localCopy;

    final localPath = firebasePath.toLocalPlatformSeparators();
    final unixStylePath = firebasePath.toUnixStyleSeparators();

    if ((_failedToRetrieveFiles[localPath] ?? 0) > 3) {
      _logger.warning(("Max retries hit for $localPath, not retrieving."));
      return null;
    }

    Uint8List? data;

    try {
      _retrievingFiles.add(unixStylePath);

      _logger.fine("Grabbing file $unixStylePath from Firebase.");
      final ref = _storage.ref(unixStylePath);
      data = await ref.getData();

      if (data == null) {
        throw ("Could not find Firebase Storage entry at $unixStylePath.");
      }

      _imagesInMemory[localPath] = data;
      notifyListeners();

      await saveImage(data, fileName: localPath);

      _logger.fine("Image for $firebasePath retrieved from database.");
    } catch (ex) {
      _logger.severe("Failed to import image $firebasePath from Firebase.", ex);
      _markFailed(localPath);
    } finally {
      _retrievingFiles.remove(unixStylePath);
    }

    return data;
  }

  Future<void> removeLocalFile(String fileName) async {
    _logger.info("Deleting locally stored file at $fileName");
    final localPath = fileName.toLocalPlatformSeparators();
    _imagesInMemory.remove(localPath);
    notifyListeners();

    try {
      if (kIsWeb) {
        await _box!.delete(localPath);
      } else {
        final file = _fileFactory.fromPath(getFullLocalFilePath(fileName));

        if (await file.exists()) {
          await file.delete();
        } else {
          _logger.warning(
            "Attepting to clear local file, but file was not found at ${file.path}",
          );
        }
      }
    } catch (ex) {
      _logger.severe("Failed to delete local file $fileName", ex);
    }
  }

  Future<void> removeFirebaseFile(String firebasePath) async {
    _logger.info("Deleting cloud file at $firebasePath");
    await removeLocalFile(firebasePath);

    try {
      await _storage.ref(firebasePath.toUnixStyleSeparators()).delete();
    } catch (ex) {
      _logger.severe("Failed to delete cloud file at $firebasePath", ex);
    }
  }

  Future<void> uploadFile(File file, String firebasePath) async {
    try {
      final bytes = await file.readAsBytes();
      _imagesInMemory[firebasePath.toLocalPlatformSeparators()] = bytes;
      notifyListeners();

      await _storage.ref(firebasePath.toUnixStyleSeparators()).putFile(file);
    } catch (ex) {
      _logger.severe(
        "Failed to upload file ${file.path} to $firebasePath.",
        ex,
      );
    }
  }

  Future<void> uploadData(
    Uint8List data,
    String firebasePath,
    String contentType,
  ) async {
    try {
      _logger.fine("Uploading data to $firebasePath of type $contentType.");
      _imagesInMemory[firebasePath.toLocalPlatformSeparators()] = data;
      notifyListeners();

      final metadata = SettableMetadata(contentType: contentType);
      final ref = _storage.ref(firebasePath.toUnixStyleSeparators());
      await ref.putData(data, metadata);
    } catch (ex) {
      _logger.severe("Failed to upload data to $firebasePath.", ex);
    }
  }

  Future<void> uploadImage(Uint8List data, String firebasePath) async {
    return uploadData(data, firebasePath, getImageContentType(firebasePath));
  }

  static String getImageContentType(String filePath) =>
      "image/${extension(filePath).withFallback(".jpeg").split(".").last}";

  Future<bool> fileExists(String firebasePath) async {
    try {
      await _storage.ref(firebasePath).getDownloadURL();
      return true;
    } catch (ex) {
      return false;
    }
  }

  Future<Uint8List?> pickImageAsBytes() async {
    final picker = ImagePicker();

    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return null;

    return pickedFile.readAsBytes();
  }

  Future<ImageResult?> pickAndCopyImage({
    String? fileNameOverride,
    CompressionSettings? compressionSettings,
  }) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return null;
      _logger.finer("pickAndCopyImage() - Image picked.");

      Uint8List bytes = await pickedFile.readAsBytes();
      _logger.finer("pickAndCopyImage() - Image bytes successfully loaded.");
      if (compressionSettings != null) {
        bytes = await compressImage(
          image: bytes,
          settings: compressionSettings,
        );
        _logger.finer("pickAndCopyImage() - Image compressed.");
      }

      if (kIsWeb) {
        await _box!.put(basename(pickedFile.path), bytes);
        _logger.finer("pickAndCopyImage() - Put image in box.");

        return ImageResult(
          fileName: basename(pickedFile.path),
          imagePath: pickedFile.path,
          bytes: bytes,
        );
      }

      final directory = _directory;
      final fileName = fileNameOverride == null
          ? basename(pickedFile.path)
          : "$fileNameOverride${extension(pickedFile.path)}";

      final destinationPath = join(directory!.path, fileName);
      final destinationFile = File(destinationPath);
      if (await destinationFile.exists()) {
        await destinationFile.delete();
      }
      await destinationFile.create(recursive: true);
      await destinationFile.writeAsBytes(bytes);

      return ImageResult(
        fileName: fileName,
        imagePath: destinationPath,
        bytes: bytes,
      );
    } catch (ex) {
      _logger.severe("Failed to pick and copy image.", ex);
      rethrow;
    }
  }

  Future<ImageResult> saveImage(Uint8List imageData, {String? fileName}) async {
    fileName ??= "${DateTime.now().millisecondsSinceEpoch}.png";

    if (kIsWeb) {
      await _box!.put(fileName, imageData);

      _logger.fine("Successfully put $fileName in image cache box.");

      return ImageResult(
        fileName: fileName,
        imagePath: fileName,
        bytes: imageData,
      );
    } else {
      if (_directory == null) {
        throw ("Directory was null when attempting to import image.");
      }
      String path = join(_directory.path, fileName).toLocalPlatformSeparators();
      final imageFile = _fileFactory.fromPath(path);

      await imageFile.create(recursive: true);
      await imageFile.writeAsBytes(imageData);

      return ImageResult(fileName: fileName, imagePath: path, bytes: imageData);
    }
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

    final beforeLength = image.length;
    final afterLength = result.length;

    _logger.finer("Compressed from $beforeLength to $afterLength.");

    if (beforeLength < afterLength) return image;

    return result;
  }
}
