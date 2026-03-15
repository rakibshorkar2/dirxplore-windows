import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeBridge {
  static final NativeBridge _instance = NativeBridge._internal();
  factory NativeBridge() => _instance;
  NativeBridge._internal();

  Process? _engineProcess;
  final _updateController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get updates => _updateController.stream;

  final Map<String, Completer<Map<String, dynamic>>> _testCompleters = {};

  int? _localProxyPort;
  int? get localProxyPort => _localProxyPort;

  final Completer<int> _portCompleter = Completer<int>();
  Future<int> get portFuture => _portCompleter.future;

  static const MethodChannel _taskbarChannel = MethodChannel('com.dirxplore/taskbar');

  Future<void> init({Map<String, String>? environment}) async {
    if (_engineProcess != null) {
      stop();
    }

    try {
      final exePath = Platform.isWindows 
          ? 'native_engine/dirxplore_engine.exe' 
          : './dirxplore_engine';

      _engineProcess = await Process.start(
        exePath, 
        [], 
        environment: environment,
      );

      _engineProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.startsWith('LOCAL_PROXY_PORT:')) {
          _localProxyPort = int.tryParse(line.split(':')[1]);
          if (_localProxyPort != null && !_portCompleter.isCompleted) {
            _portCompleter.complete(_localProxyPort);
          }
          return;
        }

        try {
          final data = json.decode(line);

          if (data['type'] == 'TEST_RESULT') {
            final id = data['id'];
            if (_testCompleters.containsKey(id)) {
              _testCompleters[id]!.complete(data);
              _testCompleters.remove(id);
            }
            return;
          }

          _updateController.add(data);
          
          if (data['progress'] != null) {
             _updateTaskbar(data['progress']);
          }
        } catch (e) {
          debugPrint('Native Engine Output error: $e line: $line');
        }
      });

      _engineProcess!.stderr
          .transform(utf8.decoder)
          .listen((data) => debugPrint('Native Engine Error: $data'));

      _engineProcess!.exitCode.then((code) {
        debugPrint('Native Engine exited with code $code');
        _engineProcess = null;
        _localProxyPort = null;
      });
    } catch (e) {
      debugPrint('Failed to start Native Engine: $e');
    }
  }

  void startDownload(String id, String url, String savePath) {
    _sendCommand('START', id: id, url: url, savePath: savePath);
  }

  void pauseDownload(String id) {
    _sendCommand('PAUSE', id: id);
  }

  void resumeDownload(String id) {
    _sendCommand('RESUME', id: id);
  }

  void cancelDownload(String id) {
    _sendCommand('CANCEL', id: id);
  }

  Future<Map<String, dynamic>> testProxy(String url, {String? proxyUrl}) {
    final id = 'test_${DateTime.now().millisecondsSinceEpoch}';
    final completer = Completer<Map<String, dynamic>>();
    _testCompleters[id] = completer;

    _sendCommand('TEST', id: id, url: url, proxyUrl: proxyUrl);
    return completer.future.timeout(const Duration(seconds: 20), onTimeout: () {
      _testCompleters.remove(id);
      return {'success': false, 'error': 'Timeout'};
    });
  }

  void _sendCommand(String type, {required String id, String? url, String? savePath, String? proxyUrl}) {
    if (_engineProcess == null) {
      init().then((_) => _doSendCommand(type, id, url, savePath, proxyUrl));
    } else {
      _doSendCommand(type, id, url, savePath, proxyUrl);
    }
  }

  void _doSendCommand(String type, String id, String? url, String? savePath, String? proxyUrl) {
    final Map<String, dynamic> data = {
      'type': type,
      'id': id,
    };
    if (url != null) data['url'] = url;
    if (savePath != null) data['savePath'] = savePath;
    if (proxyUrl != null) data['proxyUrl'] = proxyUrl;
    
    final cmd = json.encode(data);
    _engineProcess?.stdin.writeln(cmd);
  }

  Future<void> _updateTaskbar(double progress) async {
    try {
      await _taskbarChannel.invokeMethod('setProgress', {'progress': progress});
    } on PlatformException catch (e) {
      debugPrint('Failed to update taskbar: ${e.message}');
    }
  }

  void stop() {
    _engineProcess?.kill();
    _engineProcess = null;
    _localProxyPort = null;
  }
}
