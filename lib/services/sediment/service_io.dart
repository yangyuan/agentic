import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'contract.dart';
import 'service.dart';

const _partialSuffix = '.download';

SedimentService createPlatformSedimentService() => _SedimentService();

class _SedimentService extends SedimentService {
  Future<Directory> _categoryDirectory(String category) async {
    final supportDirectory = await getApplicationSupportDirectory();
    final directory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}$category',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<String> _resourcePath(SedimentResource resource) async {
    final directory = await _categoryDirectory(resource.category);
    return '${directory.path}${Platform.pathSeparator}${resource.name}';
  }

  @override
  Future<List<SedimentResource>> listResources({
    required String category,
    String? suffix,
  }) async {
    final directory = await _categoryDirectory(category);
    final resources = <SedimentResource>[];

    await for (final entity in directory.list(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is! File) continue;

      final name = entity.uri.pathSegments.last;
      if (name.endsWith(_partialSuffix)) continue;
      if (suffix != null && !name.endsWith(suffix)) continue;

      resources.add(SedimentResource(category: category, name: name));
    }

    resources.sort((left, right) => left.name.compareTo(right.name));
    return resources;
  }

  @override
  Future<String?> pathFor(SedimentResource resource) async {
    final path = await _resourcePath(resource);
    return await File(path).exists() ? path : null;
  }

  @override
  Future<void> transportFromInternet(UriTransportTask request) async {
    final uri = request.uri;
    final destinationPath = await _resourcePath(request.resource);
    final destinationFile = File(destinationPath);
    if (await destinationFile.exists()) {
      await destinationFile.delete();
      notifyListeners();
    }
    final partialFile = File('$destinationPath$_partialSuffix');
    final client = HttpClient();
    final partialBytes = await partialFile.exists()
        ? await partialFile.length()
        : 0;

    setTransportProgress(request, null);

    try {
      final httpRequest = await client.getUrl(uri);
      if (partialBytes > 0) {
        httpRequest.headers.add(
          HttpHeaders.rangeHeader,
          'bytes=$partialBytes-',
        );
      }
      final response = await httpRequest.close();

      var appendToPartialFile = false;
      var receivedBytes = 0;
      int? estimatedSize;

      if (partialBytes > 0 &&
          response.statusCode == HttpStatus.partialContent) {
        appendToPartialFile = true;
        receivedBytes = partialBytes;
        estimatedSize = contentLengthFromRange(
          response.headers.value('content-range'),
        );
        if (estimatedSize == null && response.contentLength > 0) {
          estimatedSize = partialBytes + response.contentLength;
        }
      } else if (response.statusCode == HttpStatus.ok) {
        estimatedSize = response.contentLength > 0
            ? response.contentLength
            : null;
      } else if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Download failed with HTTP ${response.statusCode}',
          uri: uri,
        );
      } else {
        estimatedSize = response.contentLength > 0
            ? response.contentLength
            : null;
      }

      await _writeLocalFile(
        request: request,
        resource: request.resource,
        stream: response,
        estimatedSize: estimatedSize,
        initialBytes: receivedBytes,
        append: appendToPartialFile,
      );
    } catch (error) {
      setTransportError(request, error);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> transportFromStream(StreamTransportTask request) async {
    await _writeLocalFile(
      request: request,
      resource: request.resource,
      stream: request.stream,
      estimatedSize: request.estimatedSize,
    );
  }

  Future<void> _writeLocalFile({
    required TransportTask request,
    required SedimentResource resource,
    required Stream<List<int>> stream,
    int? estimatedSize,
    int initialBytes = 0,
    bool append = false,
  }) async {
    final destinationPath = await _resourcePath(resource);
    final destinationFile = File(destinationPath);
    final partialFile = File('$destinationPath$_partialSuffix');
    var receivedBytes = initialBytes;

    setTransportProgress(request, null);

    try {
      if (await destinationFile.exists()) {
        await destinationFile.delete();
        notifyListeners();
      }
      if (!append && await partialFile.exists()) {
        await partialFile.delete();
      }

      final sink = partialFile.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );
      try {
        await for (final chunk in stream) {
          receivedBytes += chunk.length;
          sink.add(chunk);
          setTransportProgress(
            request,
            estimatedSize != null && estimatedSize > 0
                ? receivedBytes / estimatedSize
                : null,
          );
        }
      } finally {
        await sink.close();
      }

      await partialFile.rename(destinationPath);
      notifyListeners();
    } catch (error) {
      setTransportError(request, error);
      rethrow;
    }
  }

  @override
  Future<void> delete(SedimentResource resource) async {
    final destinationFile = File(await _resourcePath(resource));
    final partialFile = File('${destinationFile.path}$_partialSuffix');
    if (await destinationFile.exists()) {
      await destinationFile.delete();
      notifyListeners();
    }
    if (await partialFile.exists()) {
      await partialFile.delete();
    }
  }
}
