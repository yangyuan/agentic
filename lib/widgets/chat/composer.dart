import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:litertlm/litertlm.dart';

import '../../services/agent.dart';
import '../../services/chat_compose.dart';
import '../../services/model.dart';

class ChatBox extends StatefulWidget {
  const ChatBox({
    super.key,
    required this.modelService,
    required this.agentService,
    required this.chatComposeService,
    required this.textController,
    required this.onPickPhoto,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onCancelRecording,
  });

  final ModelService modelService;
  final AgentService agentService;
  final ChatComposeService chatComposeService;
  final TextEditingController textController;
  final VoidCallback onPickPhoto;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onCancelRecording;

  @override
  State<ChatBox> createState() => _ChatBoxState();
}

class _ChatBoxState extends State<ChatBox> {
  bool _voiceMode = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.chatComposeService,
      builder: (context, _) {
        final photoAttachments = widget.chatComposeService.photoAttachments;
        final agentState = widget.agentService.state;
        final preference = widget.modelService.preference;
        final visionAvailable =
            preference != null &&
            _usesSupportedBackend(
              preference.model.visionBackends,
              preference.visionBackend,
            );
        final audioAvailable =
            preference != null &&
            _usesSupportedBackend(
              preference.model.audioBackends,
              preference.audioBackend,
            );
        void submit() {
          if (agentState != AgentState.standby) {
            return;
          }

          final text = widget.textController.text;
          if (text.trim().isEmpty && photoAttachments.isEmpty) {
            return;
          }

          widget.textController.clear();
          widget.agentService.send(text, photoAttachments: photoAttachments);
          widget.chatComposeService.clear();
        }

        final voiceMode = _voiceMode && audioAvailable;
        final composerEnabled = agentState == AgentState.standby;
        final colorScheme = Theme.of(context).colorScheme;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (photoAttachments.isNotEmpty)
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: photoAttachments.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final attachment = photoAttachments[index];
                      return _PhotoPreview(
                        attachment: attachment,
                        onRemove: () => widget.chatComposeService
                            .removePhotoAttachment(attachment),
                      );
                    },
                  ),
                ),
              if (photoAttachments.isNotEmpty) const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(48),
                      fixedSize: const Size.square(48),
                    ),
                    tooltip: visionAvailable
                        ? 'Attach photo'
                        : 'Vision is not available for this model',
                    onPressed: !composerEnabled || !visionAvailable
                        ? null
                        : widget.onPickPhoto,
                    icon: const Icon(Icons.photo_outlined),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.fromLTRB(4, 4, voiceMode ? 4 : 6, 4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.72,
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: voiceMode
                                ? 'Switch to keyboard'
                                : audioAvailable
                                ? 'Switch to voice'
                                : 'Audio is not available for this model',
                            onPressed: !composerEnabled || !audioAvailable
                                ? null
                                : () =>
                                      setState(() => _voiceMode = !_voiceMode),
                            icon: Icon(
                              voiceMode
                                  ? Icons.keyboard_alt_outlined
                                  : Icons.mic_none_outlined,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: voiceMode
                                ? _HoldToSpeakButton(
                                    recording:
                                        widget.chatComposeService.recording,
                                    disabled: !composerEnabled,
                                    onStart: widget.onStartRecording,
                                    onStop: widget.onStopRecording,
                                    onCancel: widget.onCancelRecording,
                                  )
                                : CallbackShortcuts(
                                    bindings: {
                                      const SingleActivator(
                                        LogicalKeyboardKey.enter,
                                      ): submit,
                                    },
                                    child: TextField(
                                      controller: widget.textController,
                                      minLines: 1,
                                      maxLines: 5,
                                      textInputAction: TextInputAction.newline,
                                      enabled: composerEnabled,
                                      decoration: InputDecoration(
                                        hintText: switch (agentState) {
                                          AgentState.preparing =>
                                            'Preparing model...',
                                          AgentState.init =>
                                            'Choose a model in settings',
                                          AgentState.standby ||
                                          AgentState.inferencing => 'Message',
                                        },
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 12,
                                            ),
                                      ),
                                    ),
                                  ),
                          ),
                          if (!voiceMode) ...[
                            const SizedBox(width: 4),
                            IconButton.filled(
                              tooltip: 'Send',
                              onPressed: !composerEnabled ? null : submit,
                              icon: switch (agentState) {
                                AgentState.preparing ||
                                AgentState.inferencing => const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                AgentState.init || AgentState.standby =>
                                  const Icon(Icons.arrow_upward),
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static bool _usesSupportedBackend(List<String> names, Backend? backend) {
    return backend != null && names.contains(backend.name);
  }
}

class _HoldToSpeakButton extends StatelessWidget {
  const _HoldToSpeakButton({
    required this.recording,
    required this.disabled,
    required this.onStart,
    required this.onStop,
    required this.onCancel,
  });

  final bool recording;
  final bool disabled;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = disabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : recording
        ? colorScheme.error
        : colorScheme.onSurface;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: disabled ? null : (_) => onStart(),
      onPointerUp: disabled ? null : (_) => onStop(),
      onPointerCancel: disabled ? null : (_) => onCancel(),
      child: Center(
        child: Text(
          recording ? 'Release to send' : 'Hold to speak',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: foregroundColor,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.attachment, required this.onRemove});

  final PhotoAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            attachment.bytes,
            width: 80,
            height: 80,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton.filledTonal(
            style: IconButton.styleFrom(
              minimumSize: const Size.square(28),
              fixedSize: const Size.square(28),
              padding: EdgeInsets.zero,
            ),
            tooltip: 'Remove photo',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 16),
          ),
        ),
      ],
    );
  }
}
