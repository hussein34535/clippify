import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/native/rust_engine.dart';
import 'short_provider_settings.dart';

/// Owns a private Windows engine process for Short Auto.
class ShortSidecar {
  _ShortSidecarRun? _run;

  Future<String> start() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('The Short sidecar requires Windows.');
    }
    final current = _run;
    if (current != null) {
      if (current.stopping) {
        throw StateError('The Short sidecar is stopping.');
      }
      return current.ready.future;
    }

    final run = _ShortSidecarRun();
    _run = run;
    run.done = run.launch().whenComplete(() => _run = null);
    run.done.ignore();
    return run.ready.future;
  }

  Future<void> stop() async {
    final run = _run;
    if (run == null) return;
    run.requestStop(StateError('The Short sidecar was stopped.'));
    await run.done;
  }
}

class _ShortSidecarRun {
  static const _startupTimeout = Duration(seconds: 15);
  static const _maxStartupLineBytes = 8192;
  static final _loopbackAddress = RegExp(
    r'^(?:http://)?127\.0\.0\.1:([0-9]{1,5})/?$',
  );

  final ready = Completer<String>();
  final _stopRequested = Completer<void>();
  final _startupLine = <int>[];
  late final Future<void> done;
  Process? _process;

  bool get stopping => _stopRequested.isCompleted;

  Future<void> launch() async {
    final timer = Timer(_startupTimeout, () {
      if (!ready.isCompleted) {
        requestStop(
          TimeoutException('The Short sidecar did not start in time.'),
        );
      }
    });
    Directory? workingDir;
    StreamSubscription<List<int>>? stdout;
    StreamSubscription<List<int>>? stderr;
    try {
      final launch = await Future.any([
        _launchConfig(),
        _stopRequested.future.then((_) => null),
      ]);
      if (launch == null || stopping) return;
      final (executable, environment) = launch;
      final temp = Directory(await Directory.systemTemp.resolveSymbolicLinks());
      if (stopping) return;
      workingDir = await temp.createTemp('clippify-short-');
      if (stopping) return;

      final process = await Process.start(
        executable,
        ['serve', '--port', '0', '--local-short'],
        workingDirectory: workingDir.path,
        environment: environment,
        includeParentEnvironment: false,
      );
      _process = process;
      stdout = process.stdout.listen(
        _readStdout,
        onError: (Object _) => _stdoutClosed(),
        onDone: _stdoutClosed,
      );
      stderr = process.stderr.listen(null, onError: (Object _) {});
      process.stdin.close().ignore();
      if (stopping) process.kill(ProcessSignal.sigkill);

      await process.exitCode;
      _process = null;
      requestStop(StateError('The Short sidecar exited before it was ready.'));
    } catch (_) {
      requestStop(StateError('Could not launch the Short sidecar.'));
    } finally {
      timer.cancel();
      try {
        final process = _process;
        if (process != null) {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
        }
        await Future.wait([
          if (stdout != null) stdout.cancel(),
          if (stderr != null) stderr.cancel(),
        ]);
        if (workingDir != null) await _deleteWorkingDir(workingDir);
      } catch (_) {
        throw StateError('Could not clean up the Short sidecar.');
      }
    }
  }

  void requestStop(Object error) {
    if (!stopping) _stopRequested.complete();
    _process?.kill(ProcessSignal.sigkill);
    if (!ready.isCompleted) {
      _startupLine.clear();
      ready.completeError(error);
    }
  }

  static Future<(String, Map<String, String>)> _launchConfig() async {
    final path = await RustEngine.resolveEngine();
    if (path == null) throw StateError('Could not find the Rust engine.');
    final executable = File(path).absolute.path;
    final asrDirectory = p.join(p.dirname(executable), 'short-asr');
    final bundledWhisper = File(p.join(asrDirectory, 'whisper-cli.exe'));
    final bundledModel = File(p.join(asrDirectory, 'ggml-small-q5_1.bin'));
    final overrides = await ShortProviderSettings.loadLaunchEnvironment();
    final inherited = Platform.environment;
    const allowed = {
      'SYSTEMROOT',
      'WINDIR',
      'PATH',
      'PATHEXT',
      'TEMP',
      'TMP',
      'USERPROFILE',
      'LOCALAPPDATA',
      'APPDATA',
      'CLIPPIFY_FFMPEG',
      'CLIPPIFY_WHISPER_EXE',
      'WHISPER_MODEL_PATH',
    };
    final environment = {
      if (await bundledWhisper.exists() && await bundledModel.exists()) ...{
        'CLIPPIFY_WHISPER_EXE': bundledWhisper.path,
        'WHISPER_MODEL_PATH': bundledModel.path,
      },
      for (final entry in inherited.entries)
        if (allowed.contains(entry.key.toUpperCase()))
          entry.key.toUpperCase(): entry.value,
      'CLIPPIFY_SHORT_TEAMSOCLO_KEY': '',
      'CLIPPIFY_SHORT_TEAMSOCLO_MODEL': '',
      'CLIPPIFY_SHORT_AI_BASE_URL': '',
      'CLIPPIFY_SHORT_AI_VISION': '',
      for (final entry in overrides.entries)
        entry.key.toUpperCase(): entry.value,
    };
    return (executable, environment);
  }

  void _stdoutClosed() {
    if (!ready.isCompleted) {
      requestStop(StateError('The Short sidecar closed its startup output.'));
    }
  }

  void _readStdout(List<int> bytes) {
    if (ready.isCompleted) return;
    for (final byte in bytes) {
      if (byte == 10) {
        final url = _listeningUrl(_startupLine);
        _startupLine.clear();
        if (url != null) {
          ready.complete(url);
          return;
        }
      } else if (_startupLine.length == _maxStartupLineBytes) {
        requestStop(
          StateError('The Short sidecar sent oversized startup output.'),
        );
        return;
      } else {
        _startupLine.add(byte);
      }
    }
  }

  static String? _listeningUrl(List<int> line) {
    try {
      final message = jsonDecode(utf8.decode(line));
      if (message case {'listening': final String address}) {
        final match = _loopbackAddress.firstMatch(address);
        if (match == null || match.end != address.length) return null;
        final port = int.parse(match[1]!);
        if (port > 0 && port <= 65535) return 'http://127.0.0.1:$port';
      }
    } on FormatException {
      // The engine may emit other stdout lines before the listening message.
    }
    return null;
  }

  static Future<void> _deleteWorkingDir(Directory directory) async {
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.directory ||
        await directory.resolveSymbolicLinks() != directory.path) {
      throw StateError('The Short sidecar working directory changed.');
    }
    await directory.delete(recursive: true);
  }
}
