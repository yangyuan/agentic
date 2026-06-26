import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';

import '../services/agent.dart';
import '../services/chat_compose.dart';
import '../services/model.dart';
import 'chat/composer.dart';
import 'chat/message.dart';
import 'settings_dialog.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.modelService,
    required this.agentService,
    required this.chatComposeService,
  });

  final ModelService modelService;
  final AgentService agentService;
  final ChatComposeService chatComposeService;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();
  var _lastMessageCount = 0;
  var _hadStreamingMessage = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.modelService, widget.agentService]),
      builder: (context, _) {
        final modelService = widget.modelService;
        final agentService = widget.agentService;
        final error = agentService.error;
        final messages = [
          ...agentService.messages,
          if (agentService.streamingMessage != null)
            agentService.streamingMessage!,
        ];
        final forceScroll = messages.length > _lastMessageCount;
        _lastMessageCount = messages.length;
        final hasStreamingMessage = agentService.streamingMessage != null;
        final streamingMessageEnded =
            _hadStreamingMessage && !hasStreamingMessage;
        _hadStreamingMessage = hasStreamingMessage;
        if (messages.isNotEmpty) {
          _scrollToBottom(force: forceScroll || streamingMessageEnded);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Agentic'),
            actions: [
              IconButton(
                tooltip: 'Refresh chat',
                onPressed: agentService.messages.isEmpty
                    ? null
                    : agentService.clearConversation,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () => _showSettings(context),
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: messages.isEmpty
                      ? const Center(child: Text('Ask anything.'))
                      : SelectionArea(
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              return MessageBubble(message: messages[index]);
                            },
                          ),
                        ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ChatBox(
                  modelService: modelService,
                  agentService: agentService,
                  chatComposeService: widget.chatComposeService,
                  textController: _textController,
                  onPickPhoto: _pickPhoto,
                  onStartRecording: _startRecording,
                  onStopRecording: _stopRecordingAndSend,
                  onCancelRecording: _cancelRecording,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSettings(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(modelService: widget.modelService),
    );
  }

  Future<void> _pickPhoto() async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    widget.chatComposeService.addPhotoAttachment(
      PhotoAttachment(name: image.name, bytes: await image.readAsBytes()),
    );
  }

  Future<void> _startRecording() async {
    try {
      await widget.chatComposeService.startRecording();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _stopRecordingAndSend() async {
    try {
      final attachment = await widget.chatComposeService.stopRecording();
      if (attachment == null) return;
      await widget.agentService.send('', audioAttachments: [attachment]);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _cancelRecording() async {
    await widget.chatComposeService.cancelRecording();
  }

  bool _isAtBottom() {
    if (!_scrollController.hasClients) {
      return true;
    }
    final position = _scrollController.position;
    return position.pixels >= position.maxScrollExtent - 60;
  }

  void _scrollToBottom({bool force = false}) {
    if (!force && !_isAtBottom()) {
      return;
    }

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }
}
