import 'package:flutter/foundation.dart';

class ModelCatalog {
  const ModelCatalog();

  static const models = [
    ModelInfo(
      id: 'gemma-4-E2B-it',
      provider: 'Google',
      name: 'Gemma 4 E2B IT',
      fileName: 'gemma-4-E2B-it.litertlm',
      downloadUrl:
          'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
      platforms: ['mobile', 'desktop'],
      backends: ['cpu', 'gpu', 'npu'],
      visionBackends: ['cpu', 'gpu'],
      audioBackends: ['cpu'],
    ),
    ModelInfo(
      id: 'gemma-4-E2B-it-web',
      provider: 'Google',
      name: 'Gemma 4 E2B IT (Web)',
      fileName: 'gemma-4-E2B-it-web.litertlm',
      downloadUrl:
          'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it-web.litertlm',
      platforms: ['mobile', 'desktop', 'web'],
      backends: ['gpu'],
      visionBackends: [],
      audioBackends: [],
    ),
    ModelInfo(
      id: 'gemma-4-E4B-it',
      provider: 'Google',
      name: 'Gemma 4 E4B IT',
      fileName: 'gemma-4-E4B-it.litertlm',
      downloadUrl:
          'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
      platforms: ['mobile', 'desktop'],
      backends: ['cpu', 'gpu', 'npu'],
      visionBackends: ['cpu', 'gpu'],
      audioBackends: ['cpu'],
    ),
    ModelInfo(
      id: 'gemma-4-E4B-it-web',
      provider: 'Google',
      name: 'Gemma 4 E4B IT (Web)',
      fileName: 'gemma-4-E4B-it-web.litertlm',
      downloadUrl:
          'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it-web.litertlm',
      platforms: ['mobile', 'desktop', 'web'],
      backends: ['gpu'],
      visionBackends: [],
      audioBackends: [],
    ),
    ModelInfo(
      id: 'gemma-4-12B-it',
      provider: 'Google',
      name: 'Gemma 4 12B IT',
      fileName: 'gemma-4-12B-it.litertlm',
      downloadUrl:
          'https://huggingface.co/litert-community/gemma-4-12B-it-litert-lm/blob/main/gemma-4-12B-it.litertlm',
      platforms: ['desktop'],
      backends: ['gpu'],
      visionBackends: [],
      audioBackends: ['gpu'],
    ),
  ];

  List<ModelInfo> get availableModels {
    return [
      for (final model in models)
        if (model.platforms.contains(_currentPlatform)) model,
    ];
  }

  ModelInfo get defaultModel => availableModels.first;

  String get _currentPlatform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => 'mobile',
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => 'desktop',
    };
  }
}

class ModelInfo {
  const ModelInfo({
    required this.id,
    required this.provider,
    required this.name,
    required this.fileName,
    required this.downloadUrl,
    required this.platforms,
    required this.backends,
    required this._visionBackends,
    required this.audioBackends,
  });

  final String id;
  final String provider;
  final String name;
  final String fileName;
  final String downloadUrl;
  final List<String> platforms;
  final List<String> backends;
  final List<String> _visionBackends;
  final List<String> audioBackends;

  List<String> get visionBackends {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return _visionBackends;
    }

    return [
      for (final backend in _visionBackends)
        if (backend != 'gpu') backend,
    ];
  }
}
