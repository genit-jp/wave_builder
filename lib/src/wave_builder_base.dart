import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:wave_builder/src/lib/byte_utils.dart';

/// This flag is used when appending silence.
/// Determines whether or not to start the silence timer at the beginning or end of the
/// last sample appended to this file.
enum WaveBuilderSilenceType { BeginningOfLastSample, EndOfLastSample }

/// Build a wave file.
class WaveBuilder {
  static const int RIFF_CHUNK_SIZE_INDEX = 4;
  static const int SUB_CHUNK_SIZE = 16;
  static const int AUDIO_FORMAT = 1;
  static const int BYTE_SIZE = 8;

  //int _lastSampleSize = 0;

  /// Finalizes the header sizes and returns bytes
  List<int> get fileBytes {
    _finalize();
    return _outputBytes;
  }

  List<int> _outputBytes = <int>[];
  final Utf8Encoder _utf8encoder = Utf8Encoder();

  int _dataChunkSizeIndex = 0;

  int _bitRate = 16;
  int _frequency = 44100;
  int _numChannels = 2;
  Int16List _dataChunk = Int16List(0);
  int get bitRate {
    return _bitRate;
  }

  int get frequency {
    return _frequency;
  }

  int get numChannels {
    return _numChannels;
  }

  Int16List get data {
    return _dataChunk;
  }

  set data(Int16List newData) {
    _dataChunk = newData;
  }

  int get sampleLength {
    return _dataChunk.length ~/ _numChannels;
  }

  WaveBuilder({
    int bitRate = 16,
    int frequency = 44100,
    int numChannels = 2,
    ByteBuffer? fileBuffer,
    int sampleLength = 0,
  }) {
    if (fileBuffer != null) {
      List<int> fileContents =
          fileBuffer.asUint8List(0, fileBuffer.lengthInBytes);
      _numChannels = ByteUtils.byteListAsNumber(fileContents.sublist(22, 24));
      _bitRate = ByteUtils.byteListAsNumber(fileContents.sublist(34, 36));
      _frequency = ByteUtils.byteListAsNumber(fileContents.sublist(24, 28));
      _dataChunk = _getDataChunk(fileContents);
    } else {
      _outputBytes = <int>[];
      _bitRate = bitRate;
      _frequency = frequency;
      _numChannels = numChannels;
      _dataChunk = Int16List(sampleLength * numChannels);
    }
  }

  void _finalize() {
    _outputBytes = [];
    _outputBytes.addAll(_utf8encoder.convert('RIFF'));
    _outputBytes.addAll(ByteUtils.numberAsByteList(0, 4, bigEndian: false));
    _outputBytes.addAll(_utf8encoder.convert('WAVE'));

    _createFormatChunk();
    _writeDataChunkHeader();
    ByteBuffer byteBuffer = _dataChunk.buffer;
    _outputBytes.addAll(byteBuffer.asUint8List());
    _updateRiffChunkSize();
    _updateDataChunkSize();
  }

  void _createFormatChunk() {
    var byteRate = _frequency * _numChannels * _bitRate ~/ BYTE_SIZE,
        blockAlign = _numChannels * _bitRate ~/ 8,
        bitsPerSample = _bitRate;
    _outputBytes.addAll(_utf8encoder.convert('fmt '));
    _outputBytes.addAll(
        ByteUtils.numberAsByteList(SUB_CHUNK_SIZE, 4, bigEndian: false));
    _outputBytes
        .addAll(ByteUtils.numberAsByteList(AUDIO_FORMAT, 2, bigEndian: false));
    _outputBytes
        .addAll(ByteUtils.numberAsByteList(_numChannels, 2, bigEndian: false));
    _outputBytes
        .addAll(ByteUtils.numberAsByteList(_frequency, 4, bigEndian: false));
    _outputBytes
        .addAll(ByteUtils.numberAsByteList(byteRate, 4, bigEndian: false));
    _outputBytes
        .addAll(ByteUtils.numberAsByteList(blockAlign, 2, bigEndian: false));
    _outputBytes
        .addAll(ByteUtils.numberAsByteList(bitsPerSample, 2, bigEndian: false));
  }

  void _writeDataChunkHeader() {
    _outputBytes.addAll(_utf8encoder.convert('data'));
    _dataChunkSizeIndex = _outputBytes.length;
    _outputBytes.addAll(ByteUtils.numberAsByteList(0, 4, bigEndian: false));
  }

  /// Find data chunk content after <data|size> in [fileContents]
  Int16List _getDataChunk(List<int> fileContents) {
    final dataIdSequence = _utf8encoder.convert('data');
    final dataIdIndex =
        ByteUtils.findByteSequenceInList(dataIdSequence, fileContents);
    var dataStartIndex = 0;

    if (dataIdIndex != -1) {
      // Add 4 for data size
      dataStartIndex = dataIdIndex + dataIdSequence.length + 4;
    }
    Uint8List bytes = Uint8List.fromList(fileContents.sublist(dataStartIndex));
    ByteBuffer byteBuffer = bytes.buffer;
    return byteBuffer.asInt16List();
  }

  void _updateRiffChunkSize() {
    _outputBytes.replaceRange(
        RIFF_CHUNK_SIZE_INDEX,
        RIFF_CHUNK_SIZE_INDEX + 4,
        ByteUtils.numberAsByteList(
            _outputBytes.length - (RIFF_CHUNK_SIZE_INDEX + 4), 4,
            bigEndian: false));
  }

  void _updateDataChunkSize() {
    _outputBytes.replaceRange(
        _dataChunkSizeIndex,
        _dataChunkSizeIndex + 4,
        ByteUtils.numberAsByteList(
            _outputBytes.length - (_dataChunkSizeIndex + 4), 4,
            bigEndian: false));
  }

  int _roundInt16(int value) {
    if (value > 32767) {
      return 32767;
    } else if (value < -32768) {
      return -32768;
    }
    return value;
  }

  void mergeOtherWaveBuilder(
      {required WaveBuilder waveBuilder,
      int offsetSample = 0,
      double volume = 1.0}) {
    var currentBuffer = data;
    for (var i = 0; i < min(waveBuilder.data.length, this.data.length); i++) {
      if (i + offsetSample >= 0) {
        if (waveBuilder._numChannels == 2) {
          var value = currentBuffer[i + offsetSample] +
              (waveBuilder.data[i] * volume).toInt();
          currentBuffer[i + offsetSample] = _roundInt16(value);
        } else if (this.numChannels == 2 && waveBuilder._numChannels == 1) {
          var evenValue = currentBuffer[2 * (i + offsetSample)] +
              (waveBuilder.data[i] * volume).toInt();
          var oddValue = currentBuffer[2 * (i + offsetSample) + 1] +
              (waveBuilder.data[i] * volume).toInt();
          currentBuffer[2 * (i + offsetSample)] = _roundInt16(evenValue);
          currentBuffer[2 * (i + offsetSample) + 1] = _roundInt16(oddValue);
        } else if (this.numChannels == 1 && waveBuilder._numChannels == 2) {
          var value = currentBuffer[i + offsetSample] +
              (waveBuilder.data[2 * i] + waveBuilder.data[2 * i + 1]) *
                  volume ~/
                  2;
          currentBuffer[i + offsetSample] = _roundInt16(value);
        }
      }
    }
  }
}
