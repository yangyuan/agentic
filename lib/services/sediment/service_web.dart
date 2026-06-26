import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'contract.dart';
import 'service.dart';

const _partialSuffix = '.download';

SedimentService createPlatformSedimentService() => _SedimentService();

class _SedimentService extends SedimentService {
  final Map<String, String> _objectUrls = {};

  Future<web.Cache> _categoryCache(String category) {
    return web.window.caches.open(category).toDart;
  }

  @override
  Future<List<SedimentResource>> listResources({
    required String category,
    String? suffix,
  }) async {
    final cache = await _categoryCache(category);
    final requests = (await cache.keys().toDart).toDart;
    final resources = <SedimentResource>[];

    for (final request in requests) {
      final uri = Uri.tryParse(request.url);
      final name = Uri.decodeComponent(uri!.pathSegments.last);
      if (name.endsWith(_partialSuffix)) continue;
      if (suffix != null && !name.endsWith(suffix)) continue;

      resources.add(SedimentResource(category: category, name: name));
    }

    resources.sort((left, right) => left.name.compareTo(right.name));
    return resources;
  }

  @override
  Future<String?> pathFor(SedimentResource resource) async {
    final objectUrl = _objectUrls[resource.id];
    if (objectUrl != null) return objectUrl;

    final cache = await _categoryCache(resource.category);
    final cachedResponse = await cache.match(resource.name.toJS).toDart;
    if (cachedResponse == null) return null;
    return _objectUrlFromBlob(resource, await cachedResponse.blob().toDart);
  }

  @override
  Future<void> transportFromInternet(UriTransportTask request) async {
    final uri = request.uri;
    final cache = await _categoryCache(request.resource.category);
    final cacheKey = request.resource.name;
    final completedResponse = await cache.match(cacheKey.toJS).toDart;
    if (completedResponse != null) {
      await cache.delete(cacheKey.toJS).toDart;
      _revokeObjectUrl(request.resource);
      notifyListeners();
    }
    final partialKey = '$cacheKey$_partialSuffix';
    final partialResponse = await cache.match(partialKey.toJS).toDart;
    var partialBlob = partialResponse == null
        ? null
        : await partialResponse.blob().toDart;
    var receivedBytes = partialBlob?.size.toInt() ?? 0;
    setTransportProgress(request, null);

    try {
      var response = receivedBytes == 0
          ? await web.window.fetch(uri.toString().toJS).toDart
          : await web.window
                .fetch(
                  uri.toString().toJS,
                  web.RequestInit(
                    headers: web.Headers()
                      ..set('range', 'bytes=$receivedBytes-'),
                  ),
                )
                .toDart;
      if (receivedBytes > 0 && response.status != 206) {
        await cache.delete(partialKey.toJS).toDart;
        partialBlob = null;
        receivedBytes = 0;
        response = await web.window.fetch(uri.toString().toJS).toDart;
      }

      if (response.status < 200 || response.status >= 300) {
        throw StateError('Download failed with HTTP ${response.status}');
      }

      int? estimatedSize;
      if (response.status == 206) {
        estimatedSize = contentLengthFromRange(
          response.headers.get('content-range'),
        );
        if (estimatedSize == null) {
          final contentLength = int.tryParse(
            response.headers.get('content-length') ?? '',
          );
          estimatedSize = contentLength != null
              ? receivedBytes + contentLength
              : null;
        }
      } else {
        estimatedSize = int.tryParse(
          response.headers.get('content-length') ?? '',
        );
      }
      await _writeCacheResource(
        request: request,
        resource: request.resource,
        stream: _responseByteStream(response),
        estimatedSize: estimatedSize,
        initialBytes: receivedBytes,
        initialBlob: partialBlob,
        cachePartial: true,
      );
    } catch (error) {
      setTransportError(request, error);
      rethrow;
    }
  }

  @override
  Future<void> transportFromStream(StreamTransportTask request) async {
    await _writeCacheResource(
      request: request,
      resource: request.resource,
      stream: request.stream,
      estimatedSize: request.estimatedSize,
    );
  }

  Future<void> _writeCacheResource({
    required TransportTask request,
    required SedimentResource resource,
    required Stream<List<int>> stream,
    int? estimatedSize,
    int initialBytes = 0,
    web.Blob? initialBlob,
    bool cachePartial = false,
  }) async {
    final cache = await _categoryCache(resource.category);
    final cacheKey = resource.name;
    final partialKey = '$cacheKey$_partialSuffix';
    final parts = <JSAny>[];
    if (initialBlob != null) parts.add(initialBlob);
    var receivedBytes = initialBytes;

    setTransportProgress(request, null);

    try {
      if (_objectUrls.containsKey(resource.id)) {
        await cache.delete(cacheKey.toJS).toDart;
        _revokeObjectUrl(resource);
        notifyListeners();
      } else {
        await cache.delete(cacheKey.toJS).toDart;
      }
      await for (final chunk in stream) {
        final bytes = Uint8List.fromList(chunk);
        parts.add(bytes.toJS);
        receivedBytes += bytes.length;
        if (cachePartial) {
          await cache
              .put(partialKey.toJS, web.Response(web.Blob(parts.toJS)))
              .toDart;
        }
        setTransportProgress(
          request,
          estimatedSize != null && estimatedSize > 0
              ? receivedBytes / estimatedSize
              : null,
        );
      }

      final blob = web.Blob(parts.toJS);
      await cache.put(cacheKey.toJS, web.Response(blob)).toDart;
      await cache.delete(partialKey.toJS).toDart;
      notifyListeners();
    } catch (error) {
      setTransportError(request, error);
      rethrow;
    }
  }

  @override
  Future<void> delete(SedimentResource resource) async {
    final cache = await _categoryCache(resource.category);
    final cacheKey = resource.name;
    await cache.delete(cacheKey.toJS).toDart;
    await cache.delete('$cacheKey$_partialSuffix'.toJS).toDart;
    _revokeObjectUrl(resource);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final objectUrl in _objectUrls.values) {
      web.URL.revokeObjectURL(objectUrl);
    }
    _objectUrls.clear();
    super.dispose();
  }

  Stream<List<int>> _responseByteStream(web.Response response) async* {
    final body = response.body;
    if (body == null) {
      throw StateError('Download response does not provide a readable stream.');
    }

    final reader = body.getReader() as web.ReadableStreamDefaultReader;
    try {
      while (true) {
        final readResult = await reader.read().toDart;
        if (readResult.done) break;

        final value = readResult.value;
        if (value == null) continue;

        yield (value as JSUint8Array).toDart;
      }
    } finally {
      reader.releaseLock();
    }
  }

  String _objectUrlFromBlob(SedimentResource resource, web.Blob blob) {
    _revokeObjectUrl(resource);
    final objectUrl = web.URL.createObjectURL(blob);
    _objectUrls[resource.id] = objectUrl;
    return objectUrl;
  }

  void _revokeObjectUrl(SedimentResource resource) {
    final objectUrl = _objectUrls.remove(resource.id);
    if (objectUrl != null) {
      web.URL.revokeObjectURL(objectUrl);
    }
  }
}
