import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:litertlm/litertlm.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/catalog.dart';
import 'sediment.dart';

const _modelsCategory = 'models';
const _modelPreferenceKey = 'model';

class ModelPreference {
  const ModelPreference({
    required this.model,
    required this.backend,
    required this.visionBackend,
    required this.audioBackend,
  });

  final ModelInfo model;
  final Backend backend;
  final Backend? visionBackend;
  final Backend? audioBackend;

  String toJson() {
    return jsonEncode({
      'model': model.id,
      'backend': backend.name,
      'visionBackend': visionBackend?.name,
      'audioBackend': audioBackend?.name,
    });
  }

  static ModelPreference fromJson(String json, List<ModelInfo> models) {
    final setup = jsonDecode(json);

    return ModelPreference(
      model: models.firstWhere((model) => model.id == setup['model']),
      backend: Backend.values.firstWhere(
        (backend) => backend.name == setup['backend'],
      ),
      visionBackend: setup['visionBackend'] == null
          ? null
          : Backend.values.firstWhere(
              (backend) => backend.name == setup['visionBackend'],
            ),
      audioBackend: setup['audioBackend'] == null
          ? null
          : Backend.values.firstWhere(
              (backend) => backend.name == setup['audioBackend'],
            ),
    );
  }
}

class ModelService extends ChangeNotifier {
  ModelService()
    : catalog = const ModelCatalog(),
      sedimentService = createSedimentService() {
    sedimentService.addListener(_handleSedimentChanged);
    unawaited(_initialize());
  }

  final ModelCatalog catalog;
  final SedimentService sedimentService;
  final SharedPreferencesAsync _sharedPreferences = SharedPreferencesAsync();

  ModelPreference? _preference;
  final Map<String, String> _readyModelPaths = {};

  List<ModelInfo> get models => catalog.availableModels;
  ModelPreference? get preference => _preference;

  String? pathForModel(ModelInfo model) {
    return _readyModelPaths[model.id];
  }

  bool isModelReady(ModelInfo model) {
    return _readyModelPaths.containsKey(model.id);
  }

  UriTransportTask createUriTransportTask(ModelInfo model) {
    return UriTransportTask(
      resource: _modelResource(model),
      uri: Uri.parse(model.downloadUrl),
    );
  }

  StreamTransportTask createStreamTransportTask(
    ModelInfo model, {
    required Stream<List<int>> stream,
    required int estimatedSize,
  }) {
    return StreamTransportTask(
      resource: _modelResource(model),
      stream: stream,
      estimatedSize: estimatedSize,
    );
  }

  Future<void> savePreference(ModelPreference preference) async {
    await _sharedPreferences.setString(
      _modelPreferenceKey,
      preference.toJson(),
    );

    _preference = preference;
    notifyListeners();
  }

  Future<void> deleteModel(ModelInfo model) async {
    notifyListeners();
    try {
      await sedimentService.delete(_modelResource(model));
      _readyModelPaths.remove(model.id);
    } finally {
      notifyListeners();
    }
  }

  Future<void> _initialize() async {
    for (final model in models) {
      await _refreshModelPath(model);
    }
    final json = await _sharedPreferences.getString(_modelPreferenceKey);
    if (json != null) _preference = ModelPreference.fromJson(json, models);
    notifyListeners();
  }

  Future<void> _refreshModelPath(ModelInfo model) async {
    final modelPath = await sedimentService.pathFor(_modelResource(model));
    if (modelPath == null) {
      _readyModelPaths.remove(model.id);
    } else {
      _readyModelPaths[model.id] = modelPath;
    }
  }

  void _handleSedimentChanged() async {
    for (final model in models) {
      await _refreshModelPath(model);
    }
    notifyListeners();
  }

  SedimentResource _modelResource(ModelInfo model) {
    return SedimentResource(category: _modelsCategory, name: model.fileName);
  }

  @override
  void dispose() {
    sedimentService.removeListener(_handleSedimentChanged);
    sedimentService.dispose();
    super.dispose();
  }
}
