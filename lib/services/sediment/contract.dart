import 'package:flutter/foundation.dart';

class SedimentResource {
  const SedimentResource({required this.category, required this.name});

  final String category;
  final String name;

  String get id => '$category/$name';
}

abstract class TransportTask extends ChangeNotifier {
  TransportTask({required this.resource});

  final SedimentResource resource;

  double? _progress;
  String? _error;

  double? get progress => _progress;
  String? get error => _error;

  void setProgress(double? progress) {
    _progress = progress;
    _error = null;
    notifyListeners();
  }

  void setError(Object error) {
    _error = error.toString();
    notifyListeners();
  }
}

class UriTransportTask extends TransportTask {
  UriTransportTask({required super.resource, required this.uri});

  final Uri uri;
}

class StreamTransportTask extends TransportTask {
  StreamTransportTask({
    required super.resource,
    required this.stream,
    required this.estimatedSize,
  });

  final Stream<List<int>> stream;
  final int estimatedSize;
}
