// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:ui' show hashValues;

import 'package:mojo/mojo/url_response.mojom.dart';
import 'package:quiver/collection.dart';

import 'fetch.dart';
import 'image_decoder.dart';
import 'image_resource.dart';

/// Implements a way to retrieve an image, for example by fetching it from the
/// network. Also used as a key in the image cache.
///
/// This is the interface implemented by objects that can be used as the
/// argument to [ImageCache.loadProvider].
///
/// The [ImageCache.load] function uses an [ImageProvider] that fetches images
/// described by URLs. One could create an [ImageProvider] that used a custom
/// protocol, e.g. a direct TCP connection to a remote host, or using a
/// screenshot API from the host platform; such an image provider would then
/// share the same cache as all the other image loading codepaths that used the
/// [imageCache].
abstract class ImageProvider { // ignore: one_member_abstracts
  Future<ImageInfo> loadImage();

  /// Subclasses must implement the `==` operator so that the image cache can
  /// distinguish identical requests.
  @override
  bool operator ==(dynamic other);

  /// Subclasses must implement the `hashCode` operator so that the image cache
  /// can efficiently store the providers in a map.
  @override
  int get hashCode;
}

class _UrlFetcher implements ImageProvider {
  _UrlFetcher(this._url, this._scale);

  final String _url;
  final double _scale;

  @override
  Future<ImageInfo> loadImage() async {
    UrlResponse response = await fetchUrl(_url);
    if (response.statusCode >= 400) {
      print("Failed (${response.statusCode}) to load image $_url");
      return null;
    }
    return new ImageInfo(
      image: await decodeImageFromDataPipe(response.body),
      scale: _scale
    );
  }

  @override
  bool operator ==(dynamic other) {
    if (other is! _UrlFetcher)
      return false;
    final _UrlFetcher typedOther = other;
    return _url == typedOther._url && _scale == typedOther._scale;
  }

  @override
  int get hashCode => hashValues(_url, _scale);
}

const int _kDefaultSize = 1000;

/// Class for the [imageCache] object.
///
/// Implements a least-recently-used cache of up to 1000 images. The maximum
/// size can be adjusted using [maximumSize]. Images that are actively in use
/// (i.e. to which the application is holding references, either via
/// [ImageResource] objects, [ImageInfo] objects, or raw [ui.Image] objects) may
/// get evicted from the cache (and thus need to be refetched from the network
/// if they are referenced in the [load] method), but the raw bits are kept in
/// memory for as long as the application is using them.
///
/// The [load] method fetches the image with the given URL and scale.
///
/// For more complicated use cases, the [loadProvider] method can be used with a
/// custom [ImageProvider].
class ImageCache {
  ImageCache._();

  final LruMap<ImageProvider, ImageResource> _cache =
      new LruMap<ImageProvider, ImageResource>(maximumSize: _kDefaultSize);

  /// Maximum number of entries to store in the cache.
  ///
  /// Once this many entries have been cached, the least-recently-used entry is
  /// evicted when adding a new entry.
  int get maximumSize => _cache.maximumSize;
  /// Changes the maximum cache size.
  ///
  /// If the new size is smaller than the current number of elements, the
  /// extraneous elements are evicted immediately. Setting this to zero and then
  /// returning it to its original value will therefore immediately clear the
  /// cache. However, doing this is not very efficient.
  // (the quiver library does it one at a time rather than using clear())
  void set maximumSize(int value) { _cache.maximumSize = value; }

  /// Calls the [ImageProvider.loadImage] method on the given image provider, if
  /// necessary, and returns an [ImageResource] that encapsulates a [Future] for
  /// the given image.
  ///
  /// If the given [ImageProvider] has already been used and is still in the
  /// cache, then the [ImageResource] object is immediately usable and the
  /// provider is not invoked.
  ImageResource loadProvider(ImageProvider provider) {
    return _cache.putIfAbsent(provider, () {
      return new ImageResource(provider.loadImage());
    });
  }

  /// Fetches the given URL, associating it with the given scale.
  ///
  /// The return value is an [ImageResource], which encapsulates a [Future] for
  /// the given image.
  ///
  /// If the given URL has already been fetched for the given scale, and it is
  /// still in the cache, then the [ImageResource] object is immediately usable.
  ImageResource load(String url, { double scale: 1.0 }) {
    assert(url != null);
    assert(scale != null);
    return loadProvider(new _UrlFetcher(url, scale));
  }
}

/// The singleton that implements the Flutter framework's image cache.
///
/// The simplest use of this object is as follows:
///
/// ```dart
/// imageCache.load(myImageUrl).first.then(myImageHandler);
/// ```
///
/// ...where `myImageHandler` is a function with one argument, an [ImageInfo]
/// object.
final ImageCache imageCache = new ImageCache._();
