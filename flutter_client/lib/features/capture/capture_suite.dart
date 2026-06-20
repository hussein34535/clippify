import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_theme.dart';

// ────────────────────────────────────────────────────────────
//  Riverpod Providers
// ────────────────────────────────────────────────────────────

final screenRecorderProvider = Provider<ScreenRecorder>((ref) => ScreenRecorder());
final webcamCaptureProvider = Provider<WebcamCapture>((ref) => WebcamCapture());
final audioRecorderProvider = Provider<AudioRecorder>((ref) => AudioRecorder());

final isScreenRecordingProvider = StateProvider<bool>((ref) => false);
final isWebcamActiveProvider = StateProvider<bool>((ref) => false);
final isAudioRecordingProvider = StateProvider<bool>((ref) => false);
final webcamDeviceProvider = StateProvider<String>((ref) => '');

final webcamFrameProvider = StreamProvider<Uint8List?>((ref) {
  final wc = ref.watch(webcamCaptureProvider);
  return wc.frameStream;
});

// ────────────────────────────────────────────────────────────
//  ScreenRecorder
// ────────────────────────────────────────────────────────────

class ScreenRecorder {
  Process? _process;
  DateTime? _startTime;
  Timer? _timer;
  bool _isRecording = false;
  double _duration = 0.0;
  String? _outputPath;

  bool get isRecording => _isRecording;
  double get recordingDuration => _duration;

  VoidCallback? onStart;
  VoidCallback? onStop;
  void Function(String)? onError;

  Future<bool> startRecording(String outputPath, {Rect? region, bool includeAudio = true}) async {
    if (_isRecording) return false;

    final args = <String>['-y', '-f', 'gdigrab'];

    if (region != null) {
      args.addAll(['-offset_x', '${region.left.toInt()}', '-offset_y', '${region.top.toInt()}']);
      args.addAll(['-video_size', '${region.width.toInt()}x${region.height.toInt()}']);
    }

    if (!includeAudio) {
      args.add('-an');
    }

    args.addAll(['-i', 'desktop', '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '23', outputPath]);

    try {
      _process = await Process.start('ffmpeg', args);
      _isRecording = true;
      _outputPath = outputPath;
      _startTime = DateTime.now();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _duration = DateTime.now().difference(_startTime!).inMilliseconds / 1000.0;
      });
      onStart?.call();
      return true;
    } catch (e) {
      onError?.call(e.toString());
      return false;
    }
  }

  Future<String?> stopRecording() async {
    if (!_isRecording || _process == null) return null;

    _timer?.cancel();
    try {
      _process?.stdin.write('q');
    } catch (_) {}
    _process?.kill();
    await _process?.exitCode;
    _isRecording = false;
    _duration = 0.0;
    final path = _outputPath;
    _outputPath = null;
    onStop?.call();
    return path;
  }

  void dispose() {
    _timer?.cancel();
    _process?.kill();
  }
}

// ────────────────────────────────────────────────────────────
//  WebcamCapture
// ────────────────────────────────────────────────────────────

class WebcamCapture {
  Process? _captureProcess;
  Process? _previewProcess;
  StreamSubscription<List<int>>? _previewSub;
  bool _isRecording = false;
  String? _currentOutputPath;
  String _currentDevice = '';
  bool _pipEnabled = false;
  int _pipX = 0, _pipY = 0, _pipW = 240, _pipH = 180;

  final _frameController = StreamController<Uint8List?>.broadcast();
  Stream<Uint8List?> get frameStream => _frameController.stream;

  bool get isRecording => _isRecording;
  bool get pipEnabled => _pipEnabled;
  int get pipX => _pipX;
  int get pipY => _pipY;
  int get pipW => _pipW;
  int get pipH => _pipH;

  VoidCallback? onStart;
  VoidCallback? onStop;
  void Function(String)? onError;

  static Future<List<String>> listCameras() async {
    try {
      final result = await Process.run('ffmpeg', [
        '-list_devices', 'true', '-f', 'dshow', '-i', 'dummy',
      ], runInShell: true);
      final stderr = result.stderr.toString();
      final cameras = <String>[];
      final lines = stderr.split('\n');
      bool inVideo = false;
      for (final line in lines) {
        if (line.contains('DirectShow video devices')) {
          inVideo = true;
          continue;
        }
        if (line.contains('DirectShow audio devices')) {
          inVideo = false;
          continue;
        }
        if (inVideo) {
          final match = RegExp(r'"(.+?)"').firstMatch(line);
          if (match != null) {
            cameras.add(match.group(1)!);
          }
        }
      }
      return cameras;
    } catch (e) {
      debugPrint('[WebcamCapture] listCameras error: $e');
      return [];
    }
  }

  Future<bool> startCapture(String outputPath, {String? deviceName}) async {
    if (_isRecording) return false;

    final device = deviceName ?? _currentDevice;
    if (device.isEmpty) return false;

    final args = <String>['-y', '-f', 'dshow', '-i', 'video=$device', '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '23', outputPath];

    try {
      _captureProcess = await Process.start('ffmpeg', args);
      _isRecording = true;
      _currentOutputPath = outputPath;
      _currentDevice = device;
      _startPreview(device);
      onStart?.call();
      return true;
    } catch (e) {
      onError?.call(e.toString());
      return false;
    }
  }

  void _startPreview(String device) {
    _previewProcess?.kill();
    _previewSub?.cancel();

    try {
      Process.start('ffmpeg', [
        '-f', 'dshow', '-i', 'video=$device',
        '-vf', 'scale=${_pipW}:${_pipH}',
        '-f', 'image2pipe', '-vcodec', 'mjpeg', '-q:v', '2', '-',
      ]).then((proc) {
        _previewProcess = proc;
        final completer = Completer<void>();
        final buffer = <int>[];
        proc.stdout.listen((data) {
          buffer.addAll(data);
          while (true) {
            final startIdx = _findMarker(buffer, [0xFF, 0xD8]);
            if (startIdx == -1) break;
            final endIdx = _findMarker(buffer, [0xFF, 0xD9], startIdx + 2);
            if (endIdx == -1) break;
            final frame = buffer.sublist(startIdx, endIdx + 2);
            buffer.removeRange(0, endIdx + 2);
            _frameController.add(Uint8List.fromList(frame));
          }
        }, onDone: () {
          if (!completer.isCompleted) completer.complete();
        });
        proc.stderr.listen((_) {});
      }).catchError((e) {
        debugPrint('[WebcamCapture] Preview error: $e');
      });
    } catch (e) {
      debugPrint('[WebcamCapture] Preview start error: $e');
    }
  }

  int _findMarker(List<int> data, List<int> marker, [int start = 0]) {
    for (int i = start; i < data.length - marker.length + 1; i++) {
      bool match = true;
      for (int j = 0; j < marker.length; j++) {
        if (data[i + j] != marker[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  Future<String?> stopCapture() async {
    if (!_isRecording) return null;

    _previewSub?.cancel();
    _previewProcess?.kill();
    _previewProcess = null;
    _captureProcess?.kill();
    await _captureProcess?.exitCode;
    _captureProcess = null;
    _isRecording = false;
    final path = _currentOutputPath;
    _currentOutputPath = null;
    _frameController.add(null);
    onStop?.call();
    return path;
  }

  void setPiP(bool enabled, {int x = 0, int y = 0, int width = 240, int height = 180}) {
    _pipEnabled = enabled;
    _pipX = x;
    _pipY = y;
    _pipW = width;
    _pipH = height;
  }

  void dispose() {
    _previewSub?.cancel();
    _previewProcess?.kill();
    _captureProcess?.kill();
    _frameController.close();
  }
}

// ────────────────────────────────────────────────────────────
//  AudioRecorder
// ────────────────────────────────────────────────────────────

class AudioRecorder {
  Process? _process;
  bool _isRecording = false;
  String? _outputPath;

  bool get isRecording => _isRecording;

  VoidCallback? onStart;
  VoidCallback? onStop;
  void Function(String)? onError;

  static Future<List<String>> listAudioDevices() async {
    try {
      final result = await Process.run('ffmpeg', [
        '-list_devices', 'true', '-f', 'dshow', '-i', 'dummy',
      ], runInShell: true);
      final stderr = result.stderr.toString();
      final devices = <String>[];
      final lines = stderr.split('\n');
      bool inAudio = false;
      for (final line in lines) {
        if (line.contains('DirectShow audio devices')) {
          inAudio = true;
          continue;
        }
        if (inAudio) {
          final trimmed = line.trim();
          if (trimmed.startsWith('"')) {
            final match = RegExp(r'"(.+?)"').firstMatch(line);
            if (match != null) {
              devices.add(match.group(1)!);
            }
          }
        }
        if (inAudio && line.trim().isEmpty) break;
      }
      return devices;
    } catch (e) {
      debugPrint('[AudioRecorder] listAudioDevices error: $e');
      return [];
    }
  }

  Future<bool> startRecording(String outputPath, {String? deviceName}) async {
    if (_isRecording) return false;

    final device = deviceName ?? 'Microphone';
    final args = <String>['-y', '-f', 'dshow', '-i', 'audio=$device', '-c:a', 'pcm_s16le', outputPath];

    try {
      _process = await Process.start('ffmpeg', args);
      _isRecording = true;
      _outputPath = outputPath;
      onStart?.call();
      return true;
    } catch (e) {
      onError?.call(e.toString());
      return false;
    }
  }

  Future<String?> stopRecording() async {
    if (!_isRecording || _process == null) return null;

    try {
      _process?.stdin.write('q');
    } catch (_) {}
    _process?.kill();
    await _process?.exitCode;
    _process = null;
    _isRecording = false;
    final path = _outputPath;
    _outputPath = null;
    onStop?.call();
    return path;
  }

  void dispose() {
    _process?.kill();
  }
}

// ────────────────────────────────────────────────────────────
//  CapturePanel Widget
// ────────────────────────────────────────────────────────────

class CapturePanel extends ConsumerStatefulWidget {
  final void Function(String filePath)? onCaptureComplete;

  const CapturePanel({super.key, this.onCaptureComplete});

  @override
  ConsumerState<CapturePanel> createState() => _CapturePanelState();
}

class _CapturePanelState extends ConsumerState<CapturePanel> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Screen recorder state
  bool _screenIncludeAudio = true;
  bool _screenFullscreen = true;

  // Webcam state
  List<String> _cameraList = [];
  String _selectedCamera = '';
  bool _webcamPip = false;
  double _pipX = 0, _pipY = 0, _pipW = 240, _pipH = 180;

  // Audio state
  List<String> _audioDeviceList = [];
  String _selectedAudioDevice = '';
  double _audioLevel = 0.0;
  Timer? _audioLevelTimer;

  // Shared
  String _defaultDir = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initDefaultDir();
    _listCameras();
    _listAudioDevices();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _audioLevelTimer?.cancel();
    super.dispose();
  }

  Future<void> _initDefaultDir() async {
    final dir = await getTemporaryDirectory();
    _defaultDir = dir.path;
  }

  Future<void> _listCameras() async {
    final cameras = await WebcamCapture.listCameras();
    if (mounted) {
      setState(() {
        _cameraList = cameras;
        if (_selectedCamera.isEmpty && cameras.isNotEmpty) {
          _selectedCamera = cameras.first;
        }
      });
    }
  }

  Future<void> _listAudioDevices() async {
    final devices = await AudioRecorder.listAudioDevices();
    if (mounted) {
      setState(() {
        _audioDeviceList = devices;
        if (_selectedAudioDevice.isEmpty && devices.isNotEmpty) {
          _selectedAudioDevice = devices.first;
        }
      });
    }
  }

  String _defaultPath(String name, String ext) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final dir = _defaultDir.isEmpty ? 'C:\\temp' : _defaultDir;
    return '$dir\\${name}_$ts.$ext';
  }

  // ── Screen Tab ───────────────────────────────────────────

  Widget _buildScreenTab() {
    final isRecording = ref.watch(isScreenRecordingProvider);
    final sr = ref.read(screenRecorderProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Region selector
          Row(
            children: [
              const Text('المنطقة:', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('شاشة كاملة', style: TextStyle(fontSize: 11)),
                selected: _screenFullscreen,
                onSelected: (v) => setState(() => _screenFullscreen = v),
                selectedColor: AppColors.primary.withValues(alpha: 0.3),
                backgroundColor: AppColors.surfaceVariant,
                labelStyle: TextStyle(color: _screenFullscreen ? Colors.white : AppColors.textSecondary),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('منطقة مخصصة', style: TextStyle(fontSize: 11)),
                selected: !_screenFullscreen,
                onSelected: (v) => setState(() => _screenFullscreen = !v),
                selectedColor: AppColors.primary.withValues(alpha: 0.3),
                backgroundColor: AppColors.surfaceVariant,
                labelStyle: TextStyle(color: !_screenFullscreen ? Colors.white : AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Audio toggle
          Row(
            children: [
              const Text('الصوت:', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(width: 8),
              Switch(
                value: _screenIncludeAudio,
                onChanged: (v) => setState(() => _screenIncludeAudio = v),
                activeColor: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(_screenIncludeAudio ? 'مضمن' : 'بدون صوت', style: TextStyle(fontSize: 11, color: _screenIncludeAudio ? AppColors.textPrimary : AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 12),

          // Timer display
          if (isRecording)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDuration(sr.recordingDuration),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),

          const Spacer(),

          // Start/Stop button
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () => _toggleScreenRecording(sr, isRecording),
              style: ElevatedButton.styleFrom(
                backgroundColor: isRecording ? AppColors.destructive : AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(isRecording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded, size: 18),
              label: Text(isRecording ? 'إيقاف التسجيل' : 'بدء تسجيل الشاشة', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleScreenRecording(ScreenRecorder sr, bool isRecording) async {
    if (isRecording) {
      final path = await sr.stopRecording();
      ref.read(isScreenRecordingProvider.notifier).state = false;
      if (path != null) widget.onCaptureComplete?.call(path);
    } else {
      final path = _defaultPath('screen_recording', 'mp4');
      final success = await sr.startRecording(path,
        includeAudio: _screenIncludeAudio,
        region: _screenFullscreen ? null : const Rect.fromLTWH(0, 0, 1920, 1080),
      );
      if (success) {
        ref.read(isScreenRecordingProvider.notifier).state = true;
      }
    }
  }

  // ── Webcam Tab ───────────────────────────────────────────

  Widget _buildWebcamTab() {
    final isActive = ref.watch(isWebcamActiveProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Camera dropdown
          const Text('الكاميرا:', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _selectedCamera.isEmpty ? null : _selectedCamera,
            dropdownColor: AppColors.surfaceVariant,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            hint: const Text('اختر كاميرا', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            items: _cameraList.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) {
              if (v != null) setState(() => _selectedCamera = v);
            },
          ),
          const SizedBox(height: 12),

          // Preview area
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: isActive
                ? _buildWebcamPreview()
                : const Center(child: Text('معاينة الكاميرا', style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
          ),
          const SizedBox(height: 12),

          // PiP toggle
          Row(
            children: [
              const Text('PiP:', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(width: 8),
              Switch(
                value: _webcamPip,
                onChanged: (v) => setState(() => _webcamPip = v),
                activeColor: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(_webcamPip ? 'مفعل' : 'غير مفعل', style: TextStyle(fontSize: 11, color: _webcamPip ? AppColors.textPrimary : AppColors.textMuted)),
            ],
          ),
          if (_webcamPip) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildNumberField('X', _pipX, (v) => _pipX = v)),
                const SizedBox(width: 8),
                Expanded(child: _buildNumberField('Y', _pipY, (v) => _pipY = v)),
                const SizedBox(width: 8),
                Expanded(child: _buildNumberField('العرض', _pipW, (v) => _pipW = v)),
                const SizedBox(width: 8),
                Expanded(child: _buildNumberField('الارتفاع', _pipH, (v) => _pipH = v)),
              ],
            ),
          ],

          const Spacer(),

          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () => _toggleWebcamCapture(isActive),
              style: ElevatedButton.styleFrom(
                backgroundColor: isActive ? AppColors.destructive : AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(isActive ? Icons.stop_rounded : Icons.fiber_manual_record_rounded, size: 18),
              label: Text(isActive ? 'إيقاف الكاميرا' : 'بدء تسجيل الكاميرا', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebcamPreview() {
    return ref.watch(webcamFrameProvider).when(
      data: (frame) {
        if (frame == null) return const Center(child: Text('بانتظار الكاميرا...', style: TextStyle(color: AppColors.textMuted, fontSize: 12)));
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(frame, fit: BoxFit.contain),
        );
      },
      error: (e, _) => Center(child: Text('خطأ: $e', style: const TextStyle(color: Colors.redAccent, fontSize: 11))),
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _buildNumberField(String label, double value, void Function(double) onChanged) {
    return SizedBox(
      width: 80,
      child: TextField(
        style: const TextStyle(fontSize: 11, color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          filled: true,
          fillColor: AppColors.surfaceVariant,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
        keyboardType: TextInputType.number,
        controller: TextEditingController(text: value.toInt().toString()),
        onChanged: (v) {
          final parsed = double.tryParse(v);
          if (parsed != null) onChanged(parsed);
        },
      ),
    );
  }

  Future<void> _toggleWebcamCapture(bool isActive) async {
    final wc = ref.read(webcamCaptureProvider);
    if (isActive) {
      final path = await wc.stopCapture();
      ref.read(isWebcamActiveProvider.notifier).state = false;
      if (path != null) widget.onCaptureComplete?.call(path);
    } else {
      if (_selectedCamera.isEmpty) return;
      final path = _defaultPath('webcam_recording', 'mp4');
      final success = await wc.startCapture(path, deviceName: _selectedCamera);
      if (success) {
        wc.setPiP(_webcamPip, x: _pipX.toInt(), y: _pipY.toInt(), width: _pipW.toInt(), height: _pipH.toInt());
        ref.read(isWebcamActiveProvider.notifier).state = true;
        ref.read(webcamDeviceProvider.notifier).state = _selectedCamera;
      }
    }
  }

  // ── Audio Tab ────────────────────────────────────────────

  Widget _buildAudioTab() {
    final isRecording = ref.watch(isAudioRecordingProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('الميكروفون:', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _selectedAudioDevice.isEmpty ? null : _selectedAudioDevice,
            dropdownColor: AppColors.surfaceVariant,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            hint: const Text('اختر ميكروفون', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            items: _audioDeviceList.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) {
              if (v != null) setState(() => _selectedAudioDevice = v);
            },
          ),
          const SizedBox(height: 16),

          // Levels meter
          const Text('مستوى الصوت:', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Container(
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 200 * _audioLevel,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary,
                        _audioLevel > 0.7 ? AppColors.destructive : AppColors.secondary,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (isRecording)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent)),
                  const SizedBox(width: 6),
                  const Text('جاري التسجيل...', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                ],
              ),
            ),

          const Spacer(),

          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () => _toggleAudioRecording(isRecording),
              style: ElevatedButton.styleFrom(
                backgroundColor: isRecording ? AppColors.destructive : AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(isRecording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded, size: 18),
              label: Text(isRecording ? 'إيقاف التسجيل' : 'بدء تسجيل الصوت', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleAudioRecording(bool isRecording) async {
    final ar = ref.read(audioRecorderProvider);
    if (isRecording) {
      _audioLevelTimer?.cancel();
      final path = await ar.stopRecording();
      ref.read(isAudioRecordingProvider.notifier).state = false;
      if (path != null) widget.onCaptureComplete?.call(path);
    } else {
      if (_selectedAudioDevice.isEmpty) return;
      final path = _defaultPath('audio_recording', 'wav');
      final success = await ar.startRecording(path, deviceName: _selectedAudioDevice);
      if (success) {
        ref.read(isAudioRecordingProvider.notifier).state = true;
        _audioLevelTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
          setState(() => _audioLevel = 0.2 + 0.8 * (DateTime.now().millisecond % 100) / 100.0);
        });
      }
    }
  }

  // ── Shared ───────────────────────────────────────────────

  String _formatDuration(double sec) {
    final m = (sec / 60).floor().toString().padLeft(2, '0');
    final s = (sec % 60).floor().toString().padLeft(2, '0');
    final ms = ((sec * 100) % 100).floor().toString().padLeft(2, '0');
    return '$m:$s.$ms';
  }

  @override
  Widget build(BuildContext context) {
    final screenRecording = ref.watch(isScreenRecordingProvider);
    final webcamActive = ref.watch(isWebcamActiveProvider);
    final audioRecording = ref.watch(isAudioRecordingProvider);

    return Container(
      width: 440,
      height: 520,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Title bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.fiber_manual_record_rounded, size: 14, color: Colors.redAccent),
                const SizedBox(width: 8),
                const Text('التسجيل الاحترافي', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Outfit')),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          // Tabs
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (screenRecording) Container(width: 6, height: 6, margin: const EdgeInsets.only(left: 4), decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent)),
                    const SizedBox(width: 4),
                    const Text('تسجيل الشاشة'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (webcamActive) Container(width: 6, height: 6, margin: const EdgeInsets.only(left: 4), decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent)),
                    const SizedBox(width: 4),
                    const Text('كاميرا ويب'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (audioRecording) Container(width: 6, height: 6, margin: const EdgeInsets.only(left: 4), decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent)),
                    const SizedBox(width: 4),
                    const Text('تسجيل صوت'),
                  ],
                ),
              ),
            ],
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildScreenTab(),
                _buildWebcamTab(),
                _buildAudioTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
