import 'package:flutter/foundation.dart';

import 'contract.dart';

abstract class SedimentService extends ChangeNotifier {
  Future<List<SedimentResource>> listResources({
    required String category,
    String? suffix,
  });

  Future<String?> pathFor(SedimentResource resource);

  Future<void> transportFromInternet(UriTransportTask request);

  Future<void> transportFromStream(StreamTransportTask request);

  Future<void> delete(SedimentResource resource);

  @protected
  void setTransportProgress(TransportTask request, double? progress) {
    request.setProgress(progress);
  }

  @protected
  void setTransportError(TransportTask request, Object error) {
    request.setError(error);
  }

  @protected
  int? contentLengthFromRange(String? contentRange) {
    final slashIndex = contentRange?.lastIndexOf('/') ?? -1;
    return slashIndex == -1
        ? null
        : int.tryParse(contentRange!.substring(slashIndex + 1));
  }
}
