import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

class PhotoAttachment {
  const PhotoAttachment({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class AudioAttachment {
  const AudioAttachment({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class ChatComposeService extends ChangeNotifier {
  static const _audioSampleRate = 16000;
  static const _audioChannels = 1;
  static const _audioBitsPerSample = 16;

  final AudioRecorder _audioRecorder = AudioRecorder();
  final List<PhotoAttachment> _photoAttachments = [];
  final BytesBuilder _recordedAudio = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  bool _recording = false;

  List<PhotoAttachment> get photoAttachments =>
      List.unmodifiable(_photoAttachments);
  bool get recording => _recording;

  void addPhotoAttachment(PhotoAttachment attachment) {
    _photoAttachments.add(attachment);
    notifyListeners();
  }

  void removePhotoAttachment(PhotoAttachment attachment) {
    _photoAttachments.remove(attachment);
    notifyListeners();
  }

  Future<void> startRecording() async {
    if (_recording) return;
    if (!await _audioRecorder.hasPermission()) {
      throw StateError('Microphone permission is required.');
    }

    _recordedAudio.clear();
    final stream = await _audioRecorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _audioSampleRate,
        numChannels: _audioChannels,
      ),
    );
    _audioStreamSubscription = stream.listen(_recordedAudio.add);
    _recording = true;
    notifyListeners();
  }

  Future<AudioAttachment?> stopRecording() async {
    if (!_recording) return null;

    _recording = false;
    notifyListeners();
    await _audioRecorder.stop().timeout(
      const Duration(seconds: 2),
      onTimeout: () => null,
    );
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;

    final pcmBytes = _recordedAudio.takeBytes();
    if (pcmBytes.isEmpty) return null;
    return AudioAttachment(
      name: 'voice.wav',
      bytes: _wavBytesFromPcm(pcmBytes),
    );
  }

  Future<void> cancelRecording() async {
    if (!_recording) return;

    _recording = false;
    notifyListeners();
    await _audioRecorder.stop().timeout(
      const Duration(seconds: 2),
      onTimeout: () => null,
    );
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    _recordedAudio.clear();
  }

  void clear() {
    if (_photoAttachments.isEmpty) return;
    _photoAttachments.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _audioStreamSubscription?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  Uint8List _wavBytesFromPcm(Uint8List pcmBytes) {
    final byteRate =
        _audioSampleRate * _audioChannels * _audioBitsPerSample ~/ 8;
    final blockAlign = _audioChannels * _audioBitsPerSample ~/ 8;
    final header = ByteData(44);

    _writeAscii(header, 0, 'RIFF');
    header.setUint32(4, 36 + pcmBytes.length, Endian.little);
    _writeAscii(header, 8, 'WAVE');
    _writeAscii(header, 12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, _audioChannels, Endian.little);
    header.setUint32(24, _audioSampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, _audioBitsPerSample, Endian.little);
    _writeAscii(header, 36, 'data');
    header.setUint32(40, pcmBytes.length, Endian.little);

    return Uint8List.fromList([...header.buffer.asUint8List(), ...pcmBytes]);
  }

  void _writeAscii(ByteData data, int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      data.setUint8(offset + index, value.codeUnitAt(index));
    }
  }
}
