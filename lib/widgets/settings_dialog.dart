import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:litertlm/litertlm.dart';

import '../model/catalog.dart';
import '../services/model.dart';
import '../services/sediment.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.modelService});

  final ModelService modelService;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late ModelInfo _model;
  late Backend _backend;
  Backend? _visionBackend;
  Backend? _audioBackend;
  final Map<String, TransportTask> _transportRequests = {};

  ModelService get modelService => widget.modelService;

  @override
  void dispose() {
    for (final request in _transportRequests.values) {
      request.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final setup = modelService.preference;
    _model = setup?.model ?? modelService.models.first;
    _backend = setup?.backend ?? _backendsFor(_model.backends).first;
    _visionBackend =
        setup?.visionBackend ?? _backendsFor(_model.visionBackends).firstOrNull;
    _audioBackend =
        setup?.audioBackend ?? _backendsFor(_model.audioBackends).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: modelService,
      builder: (context, _) {
        final backendOptions = _backendsFor(_model.backends);
        final visionBackendOptions = _backendsFor(_model.visionBackends);
        final audioBackendOptions = _backendsFor(_model.audioBackends);
        return AlertDialog(
          title: const Text('Settings'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Models', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  for (final model in modelService.models)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ModelRow(
                        model: model,
                        selected: model.id == _model.id,
                        ready: modelService.isModelReady(model),
                        transportRequest: _transportRequests[model.id],
                        onSelect: () => _selectModel(model),
                        onDownload: () => _downloadModel(model),
                        onUpload: () => _uploadModel(context, model),
                        onDelete: () => modelService.deleteModel(model),
                      ),
                    ),
                  const SizedBox(height: 4),
                  _BackendSection(
                    label: 'Backend',
                    options: backendOptions,
                    selected: _backend,
                    onSelected: (backend) => setState(() => _backend = backend),
                  ),
                  const SizedBox(height: 12),
                  _BackendSection(
                    label: 'Vision Backend',
                    options: visionBackendOptions,
                    selected: _visionBackend,
                    onSelected: (backend) =>
                        setState(() => _visionBackend = backend),
                  ),
                  const SizedBox(height: 12),
                  _BackendSection(
                    label: 'Audio Backend',
                    options: audioBackendOptions,
                    selected: _audioBackend,
                    onSelected: (backend) =>
                        setState(() => _audioBackend = backend),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () async {
                await modelService.savePreference(
                  ModelPreference(
                    model: _model,
                    backend: _backend,
                    visionBackend: _visionBackend,
                    audioBackend: _audioBackend,
                  ),
                );
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _selectModel(ModelInfo model) {
    setState(() {
      _model = model;
      _backend = _backendsFor(model.backends).first;
      _visionBackend = _backendsFor(model.visionBackends).firstOrNull;
      _audioBackend = _backendsFor(model.audioBackends).firstOrNull;
    });
  }

  Future<void> _downloadModel(ModelInfo model) async {
    final request = modelService.createUriTransportTask(model);
    _setTransportRequest(model, request);
    try {
      await modelService.sedimentService.transportFromInternet(request);
      _clearTransportRequest(model);
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _uploadModel(BuildContext context, ModelInfo model) async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final stream = file.readStream;
    if (stream == null) {
      throw StateError(
        'Selected file handle does not provide a readable stream.',
      );
    }

    final request = modelService.createStreamTransportTask(
      model,
      stream: stream,
      estimatedSize: file.size,
    );
    _setTransportRequest(model, request);
    try {
      await modelService.sedimentService.transportFromStream(request);
      _clearTransportRequest(model);
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  void _setTransportRequest(ModelInfo model, TransportTask request) {
    setState(() {
      _transportRequests.remove(model.id)?.dispose();
      _transportRequests[model.id] = request;
    });
  }

  void _clearTransportRequest(ModelInfo model) {
    if (!mounted) return;
    setState(() {
      _transportRequests.remove(model.id)?.dispose();
    });
  }

  static List<Backend> _backendsFor(List<String> names) {
    return [
      for (final backend in Backend.values)
        if (names.contains(backend.name)) backend,
    ];
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    required this.selected,
    required this.ready,
    required this.transportRequest,
    required this.onSelect,
    required this.onDownload,
    required this.onUpload,
    required this.onDelete,
  });

  final ModelInfo model;
  final bool selected;
  final bool ready;
  final TransportTask? transportRequest;
  final VoidCallback onSelect;
  final VoidCallback onDownload;
  final VoidCallback onUpload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final request = transportRequest;
    if (request != null) {
      return AnimatedBuilder(
        animation: request,
        builder: (context, _) => _build(context, request),
      );
    }
    return _build(context, null);
  }

  Widget _build(BuildContext context, TransportTask? request) {
    final transportError = request?.error;
    final transporting = request != null && transportError == null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: Text('${model.provider} ${model.name}'),
                selected: selected,
                onSelected: (_) => onSelect(),
              ),
            ),
            if (ready && !transporting)
              IconButton(
                tooltip: 'Delete local model',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              )
            else ...[
              IconButton(
                tooltip: 'Download model',
                onPressed: transporting ? null : onDownload,
                icon: const Icon(Icons.download),
              ),
              IconButton(
                tooltip: 'Upload local model',
                onPressed: transporting ? null : onUpload,
                icon: const Icon(Icons.upload_file),
              ),
            ],
          ],
        ),
        if (transporting)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: LinearProgressIndicator(value: request.progress),
          )
        else if (transportError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              transportError,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _BackendSection extends StatelessWidget {
  const _BackendSection({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final List<Backend> options;
  final Backend? selected;
  final ValueChanged<Backend> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        if (options.isEmpty)
          Text(
            'This feature is disabled',
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final backend in options)
                ChoiceChip(
                  label: Text(backend.name.toUpperCase()),
                  selected: backend.name == selected?.name,
                  onSelected: (_) => onSelected(backend),
                ),
            ],
          ),
      ],
    );
  }
}
