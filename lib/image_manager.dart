import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart';
import 'package:image_manager/string_extensions.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';

import 'file_factory.dart';
import 'pick_and_copy_image_result.dart';
import 'storage_directory_provider.dart';

class ImageManager extends ChangeNotifier {
  final FirebaseStorage _storage;
  final StorageDirectoryProvider _storageDirectoryProvider;
  final FileFactory _fileFactory;
  final Logger _logger = Logger("ImageManager");

  /// The key for this will always be whatever format for the local filesystem is.
  final Map<String, Uint8List> _imagesInMemory = {};
  final Set<String> _retrievingFiles = {};

  ImageManager({
    required FirebaseStorage storage,
    required StorageDirectoryProvider storageDirectoryProvider,
    required FileFactory fileFactory,
  }) : _storage = storage,
       _storageDirectoryProvider = storageDirectoryProvider,
       _fileFactory = fileFactory;

  Uint8List? getLocalSync({
    required String fileName,
    required bool retrieveIfMissing,
  }) {
    final output = _imagesInMemory[fileName.toLocalPlatformSeparators()];
    if (output == null && retrieveIfMissing) {
      getLocalAsync(fileName);
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

  /// I don't like the API for this.
  ///
  /// I think I'd hopefully know if I'm grabbing from firebase or if I'm grabbing locally.
  ///
  /// If it comes from firebase, then the key will be that full firebase location.
  ///
  /// If I'm grabbing locally, then it'll just be the name of the file.
  ///
  ///
  /// RULES: When getting local file, file name/path is not manipulated at all.
  /// When getting a firebase image, the version retrieved from Firebase will have path manipulated for unix, and the local copy will be updated to local platform separators.
  /// The firebase image path as a key to the cache will remain unchanged.

  Future<Uint8List?> getLocalAsync(String fileName) async {
    _logger.finest("getLocalAsync $fileName");
    final localPath = fileName.toLocalPlatformSeparators();
    if (_retrievingFiles.contains(localPath)) {
      _logger.fine(
        "Retrieval already initiated for image $localPath. Returning.",
      );
      return null;
    }

    Uint8List? bytes;

    try {
      _logger.fine("Retrieving image at $localPath.");

      if (_imagesInMemory[localPath] != null) {
        _logger.fine("Using cached version of image $localPath.");
        return _imagesInMemory[localPath]!;
      }

      _retrievingFiles.add(localPath);

      // Future work: If web, cache locally somehow.
      if (!kIsWeb) {
        final localStoragePath = _storageDirectoryProvider.relativePath(
          localPath,
        );
        final localStorageFile = _fileFactory.fromPath(localStoragePath);

        if (await localStorageFile.exists()) {
          _logger.fine("Image for $localPath found locally.");
          bytes = await localStorageFile.readAsBytes();
          _imagesInMemory[localPath] = bytes;
          notifyListeners();
        }
      }
    } catch (ex) {
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

      if (!kIsWeb) {
        await importImage(data, fileName: localPath);
      }

      _logger.fine("Image for $firebasePath retrieved from database.");
    } catch (ex) {
      _logger.severe("Failed to import image $firebasePath from Firebase.", ex);
    } finally {
      _retrievingFiles.remove(unixStylePath);
    }

    return data;
  }

  Future<void> removeLocalFile(String fileName) async {
    _logger.info("Deleting locally stored file at $fileName");
    _imagesInMemory.remove(fileName.toLocalPlatformSeparators());
    notifyListeners();

    try {
      final file = _fileFactory.fromPath(fileName.toLocalPlatformSeparators());
      if (await file.exists()) {
        await file.delete();
      }
    } catch (ex) {
      _logger.severe("Failed to delete local file $fileName");
    }
  }

  Future<void> removeFirebaseFile(String firebasePath) async {
    _logger.info("Deleting cloud file at $firebasePath");
    await removeLocalFile(firebasePath);

    try {
      await _storage.ref(firebasePath.toUnixStyleSeparators()).delete();
    } catch (ex) {
      _logger.severe("Failed to delete cloud file at $firebasePath");
    }
  }

  Future<void> insertFile(File file, String firebasePath) async {
    try {
      _imagesInMemory[basename(firebasePath)] = await file.readAsBytes();
      notifyListeners();

      await _storage.ref(firebasePath).putFile(file);
    } catch (ex) {
      _logger.severe("Failed to upload file ${file.path} to $firebasePath.");
    }
  }

  Future<void> insertData(
    Uint8List data,
    String firebasePath,
    String contentType,
  ) async {
    try {
      _logger.fine("Inserting data to $firebasePath of type $contentType.");
      _imagesInMemory[basename(firebasePath)] = data;
      notifyListeners();

      await _storage
          .ref(firebasePath)
          .putData(data, SettableMetadata(contentType: contentType));
    } catch (ex) {
      _logger.severe("Failed to upload data to $firebasePath.");
    }
  }

  Future<void> insertImage(Uint8List data, String firebasePath) async {
    return insertData(data, firebasePath, getImageContentType(firebasePath));
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

  Future<PickAndCopyImageResult?> pickAndCopyImage({
    String? fileNameOverride,
    String? Function(User? user, String filePath)? firebasePathCallback,
  }) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return null;

      final bytes = await pickedFile.readAsBytes();

      if (kIsWeb) {
        return PickAndCopyImageResult(
          fileName: basename(pickedFile.path),
          imagePath: pickedFile.path,
          bytes: bytes,
        );
      }

      final directory = _storageDirectoryProvider.directory;
      final fileName = fileNameOverride == null
          ? basename(pickedFile.path)
          : "$fileNameOverride${extension(pickedFile.path)}";

      final originalFile = File(pickedFile.path);
      final destinationPath = join(directory.path, fileName);
      final destinationFile = File(destinationPath);
      if (await destinationFile.exists()) {
        await destinationFile.delete();
      }
      final copiedImage = await originalFile.copy(destinationPath);
      final copiedImagePath = copiedImage.path;

      return PickAndCopyImageResult(
        fileName: fileName,
        imagePath: copiedImagePath,
        bytes: bytes,
      );
    } catch (ex) {
      _logger.severe("Failed to pick and copy image.", ex);
    }

    return null;
  }

  Future<File> importImage(Uint8List imageData, {String? fileName}) async {
    final directory = _storageDirectoryProvider.directory;

    fileName ??= "${DateTime.now().millisecondsSinceEpoch}.png";
    String path = join(directory.path, fileName).toLocalPlatformSeparators();
    final imageFile = _fileFactory.fromPath(path);

    await imageFile.create(recursive: true);
    await imageFile.writeAsBytes(imageData);
    return imageFile;
  }

  /// Throws String
  Future<Uint8List> compressImage({
    required Uint8List image,
    int? minHeight,
    int? minWidth,
    double? sizeRatio,
    required int quality,
    required CompressFormat format,
  }) async {
    Future<Size?> computeSize() async {
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
      minHeight: size?.height.floor() ?? 128,
      minWidth: size?.width.floor() ?? 128,
      quality: quality,
      format: format,
    );

    final beforeLength = image.length;
    final afterLength = result.length;

    _logger.finer("Compressed from $beforeLength to $afterLength.");

    if (beforeLength < afterLength) return image;

    return result;
  }
}
