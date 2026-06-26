import 'package:litertlm/litertlm.dart';

sealed class AgentStreamEvent {
  const AgentStreamEvent(this.message);

  final Message message;
}

final class AgentStreamChunkEvent extends AgentStreamEvent {
  const AgentStreamChunkEvent(super.message);
}

final class AgentStreamMessageEvent extends AgentStreamEvent {
  const AgentStreamMessageEvent(super.message);
}
