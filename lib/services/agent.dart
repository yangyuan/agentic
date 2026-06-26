import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:litertlm/litertlm.dart';

import '../agent/agent.dart';
import '../agent/config.dart';
import '../agent/event.dart';
import 'agent/isolate.dart'
    if (dart.library.io) 'agent/isolate_io.dart'
    as isolated_agent;
import 'chat_compose.dart';
import 'model.dart';

enum AgentState { init, preparing, standby, inferencing }

class AgentService extends ChangeNotifier {
  AgentService({required this.modelService}) {
    modelService.addListener(_handleModelChanged);
    unawaited(_syncAgent());
  }

  final ModelService modelService;

  Agent? _agent;
  AgentConfig? _agentConfig;
  AgentState state = AgentState.init;
  final List<Message> _messages = [];
  Message? _streamingMessage;
  String? _error;

  List<Message> get messages => List.unmodifiable(_messages);
  Message? get streamingMessage => _streamingMessage;
  String? get error => _error;

  Future<void> send(
    String text, {
    List<PhotoAttachment> photoAttachments = const [],
    List<AudioAttachment> audioAttachments = const [],
  }) async {
    final trimmed = text.trim();
    if ((trimmed.isEmpty &&
            photoAttachments.isEmpty &&
            audioAttachments.isEmpty) ||
        state != AgentState.standby) {
      return;
    }

    final agent = _agent!;
    state = AgentState.inferencing;
    _error = null;
    notifyListeners();

    final message = Message.userContents(
      Contents([
        if (trimmed.isNotEmpty) Content.text(trimmed),
        for (final attachment in photoAttachments)
          Content.imageBytes(attachment.bytes),
        for (final attachment in audioAttachments)
          Content.audioBytes(attachment.bytes),
      ]),
    );
    try {
      _messages.add(message);
      notifyListeners();

      await for (final event in agent.sendMessage(message)) {
        switch (event) {
          case AgentStreamChunkEvent(:final message):
            _streamingMessage = message;
          case AgentStreamMessageEvent(:final message):
            _streamingMessage = null;
            _messages.add(message);
        }
        notifyListeners();
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      _streamingMessage = null;
      state = _agent == null ? AgentState.init : AgentState.standby;
      notifyListeners();
    }
  }

  void clearConversation() {
    _messages.clear();
    _streamingMessage = null;
    state = AgentState.init;
    unawaited(() async {
      await _disposeAgent();
      await _syncAgent();
      notifyListeners();
    }());
  }

  void _handleModelChanged() {
    unawaited(_syncAgent());
  }

  Future<void> _syncAgent() async {
    final preference = modelService.preference;
    final modelPath = preference == null
        ? null
        : modelService.pathForModel(preference.model);

    if (preference == null ||
        !_supportsPreference(preference) ||
        modelPath == null) {
      if (_agent == null) {
        state = AgentState.init;
        return;
      }
      await _disposeAgent();
      state = AgentState.init;
      notifyListeners();
      return;
    }
    final config = AgentConfig(
      modelPath: modelPath,
      backend: preference.backend,
      visionBackend: preference.visionBackend,
      audioBackend: preference.audioBackend,
      initialMessages: _messages,
    );

    if (_agent != null &&
        _agentConfig != null &&
        _sameAgentConfig(_agentConfig!, config)) {
      return;
    }

    state = AgentState.preparing;
    _error = null;
    notifyListeners();

    Agent? nextAgent;
    try {
      await _disposeAgent();
      notifyListeners();
      nextAgent = isolated_agent.createAgent(config);
      await nextAgent.initialize();
      _agent = nextAgent;
      _agentConfig = config;
      state = AgentState.standby;
    } catch (error) {
      _error = error.toString();
      state = AgentState.init;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _disposeAgent() async {
    final agent = _agent;
    _agent = null;
    _agentConfig = null;
    await agent?.dispose();
  }

  static bool _sameAgentConfig(AgentConfig left, AgentConfig right) {
    return left.modelPath == right.modelPath &&
        left.backend.name == right.backend.name &&
        left.visionBackend?.name == right.visionBackend?.name &&
        left.audioBackend?.name == right.audioBackend?.name;
  }

  static bool _supportsPreference(ModelPreference preference) {
    return _usesSupportedBackend(
          preference.model.backends,
          preference.backend,
        ) &&
        _allowsBackend(
          preference.model.visionBackends,
          preference.visionBackend,
        ) &&
        _allowsBackend(preference.model.audioBackends, preference.audioBackend);
  }

  static bool _allowsBackend(List<String> names, Backend? backend) {
    return backend == null || _usesSupportedBackend(names, backend);
  }

  static bool _usesSupportedBackend(List<String> names, Backend? backend) {
    return backend != null && names.contains(backend.name);
  }

  @override
  void dispose() {
    modelService.removeListener(_handleModelChanged);
    unawaited(_disposeAgent());
    super.dispose();
  }
}
