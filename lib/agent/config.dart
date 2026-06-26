import 'package:litertlm/litertlm.dart';

final class AgentConfig {
  const AgentConfig({
    required this.modelPath,
    required this.backend,
    this.visionBackend,
    this.audioBackend,
    this.systemInstruction,
    this.initialMessages = const [],
  });

  final String modelPath;
  final Backend backend;
  final Backend? visionBackend;
  final Backend? audioBackend;
  final String? systemInstruction;
  final List<Message> initialMessages;
}
