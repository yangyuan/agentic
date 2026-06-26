import 'dart:async';

import 'package:agentic/agent/config.dart';
import 'package:litertlm/litertlm.dart';
import 'event.dart';
import 'toolbox.dart';

abstract interface class Agent {
  Future<void> initialize();

  Future<void> dispose();

  List<Message> get conversation;

  Stream<AgentStreamEvent> sendMessage(
    Message message, {
    Map<String, Object?>? extraContext,
  });

  factory Agent.create(AgentConfig config) {
    final engine = Engine(
      engineConfig: EngineConfig(
        modelPath: config.modelPath,
        backend: config.backend,
        visionBackend: config.visionBackend,
        audioBackend: config.audioBackend,
      ),
    );

    return LiteRtLmAgent(
      toolBox: ToolBox(),
      engine: engine,
      systemInstruction: config.systemInstruction,
      initialMessages: config.initialMessages,
    );
  }
}

class LiteRtLmAgent implements Agent {
  LiteRtLmAgent({
    required this.toolBox,
    required this._engine,
    this.systemInstruction,
    List<Message> initialMessages = const [],
  }) : _messages = List.of(initialMessages);

  final ToolBox toolBox;
  final Engine _engine;
  final String? systemInstruction;

  Conversation? _conversation;
  final List<Message> _messages;

  @override
  List<Message> get conversation => List.unmodifiable(_messages);

  @override
  Future<void> initialize() async {
    if (_conversation != null) {
      throw StateError('Agent is already initialized.');
    }
    await _engine.initialize();
    final trimmedSystemInstruction = systemInstruction?.trim();
    _conversation = await _engine.createConversation(
      ConversationConfig(
        systemMessage:
            trimmedSystemInstruction == null || trimmedSystemInstruction.isEmpty
            ? null
            : Message.system(trimmedSystemInstruction),
        initialMessages: List<Message>.unmodifiable(_messages),
        tools: toolBox.tools,
      ),
    );
  }

  @override
  Stream<AgentStreamEvent> sendMessage(
    Message message, {
    Map<String, Object?>? extraContext,
  }) {
    final activeConversation = _conversation;
    if (activeConversation == null) {
      throw StateError('Call initialize() before sending messages.');
    }
    _messages.add(message);
    late StreamController<AgentStreamEvent> controller;

    final text = StringBuffer();
    final toolCalls = <ToolCall>[];
    final channels = <String, String>{};
    var receivedResponse = false;

    controller = StreamController<AgentStreamEvent>(
      onListen: () {
        activeConversation
            .sendMessageWithCallback(
              message,
              MessageCallback.from(
                onMessage: (chunk) {
                  receivedResponse = true;
                  text.write(chunk.text);
                  if (chunk.toolCalls.isNotEmpty) {
                    toolCalls
                      ..clear()
                      ..addAll(chunk.toolCalls);
                  }
                  channels.addAll(chunk.channels);
                  controller.add(
                    AgentStreamChunkEvent(
                      Message.model(
                        contents: Contents.text(text.toString()),
                        toolCalls: List<ToolCall>.unmodifiable(toolCalls),
                        channels: Map<String, String>.unmodifiable(channels),
                      ),
                    ),
                  );
                },
                onMessageDone: () {
                  if (!receivedResponse) return;
                  final response = Message.model(
                    contents: Contents.text(text.toString()),
                    toolCalls: List<ToolCall>.unmodifiable(toolCalls),
                    channels: Map<String, String>.unmodifiable(channels),
                  );
                  _messages.add(response);
                  controller.add(AgentStreamMessageEvent(response));
                  text.clear();
                  toolCalls.clear();
                  channels.clear();
                  receivedResponse = false;
                },
                onDone: () {
                  unawaited(controller.close());
                },
                onError: (error, stackTrace) {
                  controller.addError(error, stackTrace);
                  unawaited(controller.close());
                },
              ),
              extraContext: extraContext,
            )
            .ignore();
      },
      onCancel: () async {
        await activeConversation.cancel();
      },
    );

    return controller.stream;
  }

  @override
  Future<void> dispose() async {
    final activeConversation = _conversation;
    _conversation = null;
    await activeConversation?.dispose();
    await _engine.dispose();
  }
}
