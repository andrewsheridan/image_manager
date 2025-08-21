import 'dart:async';

import 'package:cubit_pool/hybrid_pool.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:image_manager/src/compression_format.dart';
import 'package:image_manager/src/compression_settings.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import 'image_manager.dart' as im;

abstract class PoolImageManager<T> extends ChangeNotifier {
  @protected
  final FirebaseAuth auth;
  @protected
  final im.ImageManager imageManager;
  @protected
  final HybridPool<T> hybridPool;
  @protected
  final Uuid uuid;
  @protected
  final Logger logger = Logger("PoolImageManager<$T>");

  final CompressionSettings compressionSettings;

  late final StreamSubscription _itemUpdatedSubscription;
  late final StreamSubscription _itemDeletedSubscription;
  late final StreamSubscription _authSubscription;

  User? _user;

  PoolImageManager({
    required this.imageManager,
    required this.hybridPool,
    required FirebaseAuth firebaseAuth,
    required this.compressionSettings,
    required this.uuid,
  }) : auth = firebaseAuth {
    _itemUpdatedSubscription = hybridPool.itemUpdatedStream.listen(
      _onItemUpdated,
    );
    _itemDeletedSubscription = hybridPool.itemDeletedStream.listen(
      _onItemDeleted,
    );
    _authSubscription = auth.userChanges().listen(handleUserChanged);
    imageManager.addListener(_handleCacheChanged);
    _user = auth.currentUser;
  }

  void _handleCacheChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _itemUpdatedSubscription.cancel();
    _itemDeletedSubscription.cancel();
    _authSubscription.cancel();
    imageManager.removeListener(_handleCacheChanged);
    super.dispose();
  }

  Future<void> _onItemUpdated(ItemUpdatedEvent<T> event) async {
    final user = auth.currentUser;
    if (user == null) return;

    final before = event.before;
    final after = event.after;
    // Not doing this anymore because web requires me to have the bytes on hand for upserting.
    // Just having the file name will not work.
    // await uploadImagesForItem(after, before, user);
    await onItemChanged(after, before, user);
  }

  void _onItemDeleted(T event) async {
    final user = auth.currentUser;
    if (user == null) return;

    await removeImagesForItem(event, user);
  }

  @protected
  Future<void> uploadImagesForItem(T item, T? oldItem, User user);

  @protected
  Future<void> removeImagesForItem(T item, User user);

  @protected
  Future<void> onItemChanged(T newItem, T oldItem, User user);

  @protected
  Future<void> handleUserChanged(User? user) async {
    if (user?.uid == _user?.uid) return;

    if (user == null) {
      _user = user;
      notifyListeners();
      return;
    }

    logger.info(
      "Uploading images for type $T user ${user.displayName} ${user.uid}.",
    );

    for (final item in hybridPool.state.values) {
      await uploadImagesForItem(item, null, user);
    }

    _user = user;
    notifyListeners();
  }

  Future<void> uploadImage(String fileName, String firebasePath) async {
    try {
      logger.fine("Uploading image $fileName to $firebasePath");

      final bytes = await imageManager.getLocalAsync(fileName);

      if (bytes == null) throw ("Image bytes not found for upload.");

      return uploadImageBytes(bytes, firebasePath);
    } catch (ex) {
      logger.severe("Failed to upload image $fileName to $firebasePath.", ex);
    }
  }

  Future<void> uploadImageBytes(Uint8List bytes, String firebasePath) async {
    try {
      final compressed = await compressImage(bytes);
      await imageManager.uploadImage(compressed, firebasePath);
    } catch (ex) {
      logger.severe("Failed to upload image to $firebasePath.", ex);
    }
  }

  Future<Uint8List> compressImage(
    Uint8List bytes, {
    CompressionFormat format = CompressionFormat.jpeg,
  }) {
    return imageManager.compressImage(
      image: bytes,
      settings: compressionSettings,
    );
  }
}
