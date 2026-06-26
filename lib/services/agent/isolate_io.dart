import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:litertlm/litertlm.dart';

import '../../agent/config.dart';
import '../../agent/agent.dart';
import '../../agent/event.dart';

Agent createAgent(AgentConfig config) {
  return _IsolatedAgent(config, rootIsolateToken: RootIsolateToken.instance);
}

class _IsolatedAgent implements Agent {
  _IsolatedAgent(this._config, {required this.rootIsolateToken})
    : _messages = List.of(_config.initialMessages);

  final AgentConfig _config;
  final RootIsolateToken? rootIsolateToken;
  final List<Message> _messages;

  ReceivePort? _receivePort;
  StreamSubscription<Object?>? _receiveSubscription;
  Isolate? _isolate;
  SendPort? _worker;
  Completer<void>? _ready;
  Completer<void>? _disposing;
  StreamController<AgentStreamEvent>? _activeStream;
  bool _initialized = false;
  bool _disposed = false;

  @override
  List<Message> get conversation => List.unmodifiable(_messages);

  @override
  Future<void> initialize() async {
    if (_initialized) throw StateError('Agent is already initialized.');
    _checkNotDisposed();

    await _startWorker();
    _initialized = true;
  }

  @override
  Stream<AgentStreamEvent> sendMessage(
    Message message, {
    Map<String, Object?>? extraContext,
  }) {
    if (!_initialized) {
      throw StateError('Call initialize() before sending messages.');
    }
    _checkNotDisposed();

    final worker = _worker;
    if (worker == null) throw StateError('Agent worker is not ready.');
    if (_activeStream != null) throw StateError('Agent is already streaming.');

    late StreamController<AgentStreamEvent> controller;
    controller = StreamController<AgentStreamEvent>(
      onListen: () {
        _activeStream = controller;
        worker.send(_SendAgentMessage(message, extraContext));
      },
      onCancel: () {
        if (identical(_activeStream, controller)) _activeStream = null;
        worker.send(const _CancelAgentMessage());
      },
    );
    _messages.add(message);
    return controller.stream;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    final activeStream = _activeStream;
    _activeStream = null;
    if (activeStream != null) unawaited(activeStream.close());

    final worker = _worker;
    if (worker != null) {
      final disposing = Completer<void>();
      _disposing = disposing;
      worker.send(const _DisposeAgent());
      try {
        await disposing.future;
      } catch (_) {}
    }

    final disposing = _disposing;
    if (disposing != null && !disposing.isCompleted) {
      disposing.completeError(StateError('Agent has been disposed.'));
    }
    _disposing = null;

    await _receiveSubscription?.cancel();
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
  }

  Future<void> _startWorker() async {
    if (_ready case final ready?) return ready.future;

    final ready = Completer<void>();
    _ready = ready;
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    _receiveSubscription = receivePort.listen(_handleWorkerMessage);

    try {
      _isolate = await Isolate.spawn(
        _agentWorker,
        _WorkerStart(receivePort.sendPort, _config, rootIsolateToken),
        debugName: 'agentic-agent',
      );
    } catch (error, stackTrace) {
      if (!ready.isCompleted) ready.completeError(error, stackTrace);
    }

    return ready.future;
  }

  void _handleWorkerMessage(Object? message) {
    switch (message) {
      case _WorkerReady(:final sendPort):
        _worker = sendPort;
        if (!(_ready?.isCompleted ?? true)) _ready?.complete();
      case _AgentError(:final error, :final stackTrace):
        final remoteError = RemoteError(error, stackTrace);
        if (!(_ready?.isCompleted ?? true)) {
          _ready?.completeError(remoteError);
          return;
        }
        if (_disposing case final disposing?) {
          disposing.completeError(remoteError);
          return;
        }
        final stream = _activeStream;
        _activeStream = null;
        stream?.addError(remoteError);
        if (stream != null) unawaited(stream.close());
      case AgentStreamChunkEvent():
        _activeStream?.add(message);
      case AgentStreamMessageEvent(:final message):
        _messages.add(message);
        _activeStream?.add(AgentStreamMessageEvent(message));
      case _AgentDone():
        if (_disposing case final disposing?) {
          disposing.complete();
          return;
        }
        final stream = _activeStream;
        _activeStream = null;
        if (stream != null) unawaited(stream.close());
    }
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('Agent has been disposed.');
  }
}

final class _WorkerStart {
  const _WorkerStart(this.sendPort, this.config, this.rootIsolateToken);

  final SendPort sendPort;
  final AgentConfig config;
  final RootIsolateToken? rootIsolateToken;
}

final class _SendAgentMessage {
  const _SendAgentMessage(this.message, this.extraContext);

  final Message message;
  final Map<String, Object?>? extraContext;
}

final class _CancelAgentMessage {
  const _CancelAgentMessage();
}

final class _DisposeAgent {
  const _DisposeAgent();
}

final class _WorkerReady {
  const _WorkerReady(this.sendPort);

  final SendPort sendPort;
}

final class _AgentError {
  const _AgentError(this.error, this.stackTrace);

  final String error;
  final String stackTrace;
}

final class _AgentDone {
  const _AgentDone();
}

Future<void> _agentWorker(_WorkerStart start) async {
  if (start.rootIsolateToken case final rootIsolateToken?) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
  }

  final receivePort = ReceivePort();
  late final Agent agent;
  StreamSubscription<AgentStreamEvent>? subscription;

  try {
    agent = Agent.create(start.config);
    await agent.initialize();
    start.sendPort.send(_WorkerReady(receivePort.sendPort));
  } catch (error, stackTrace) {
    start.sendPort.send(_AgentError(error.toString(), stackTrace.toString()));
    receivePort.close();
    return;
  }

  await for (final request in receivePort) {
    switch (request) {
      case _SendAgentMessage(:final message, :final extraContext):
        try {
          subscription = agent
              .sendMessage(message, extraContext: extraContext)
              .listen(
                (event) {
                  start.sendPort.send(event);
                },
                onError: (Object error, StackTrace stackTrace) {
                  start.sendPort.send(
                    _AgentError(error.toString(), stackTrace.toString()),
                  );
                },
                onDone: () {
                  subscription = null;
                  start.sendPort.send(const _AgentDone());
                },
              );
        } catch (error, stackTrace) {
          start.sendPort.send(
            _AgentError(error.toString(), stackTrace.toString()),
          );
        }
      case _CancelAgentMessage():
        await subscription?.cancel();
        subscription = null;
        start.sendPort.send(const _AgentDone());
      case _DisposeAgent():
        await subscription?.cancel();
        subscription = null;
        try {
          await agent.dispose();
          start.sendPort.send(const _AgentDone());
        } catch (error, stackTrace) {
          start.sendPort.send(
            _AgentError(error.toString(), stackTrace.toString()),
          );
        }
        receivePort.close();
    }
  }
}
