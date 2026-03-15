import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:file_picker/file_picker.dart';
import 'package:yaml/yaml.dart';
import 'dart:io';
import '../models/proxy_config.dart';
import '../core/network/dio_client.dart';
import '../core/database/db_helper.dart';
import '../services/native_bridge.dart';

class AppProxyProvider with ChangeNotifier {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final DioClient dioClient = DioClient();
  
  ProxyConfig? _currentProxy;
  ProxyConfig? get currentProxy => _currentProxy;

  bool _isProxyEnabled = false;
  bool get isProxyEnabled => _isProxyEnabled;

  List<ProxyConfig> _importedProxies = [];
  List<ProxyConfig> get importedProxies => _importedProxies;

  Future<void> loadProxy() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('proxies', where: 'isActive = ?', whereArgs: [1]);
    if (maps.isNotEmpty) {
      _currentProxy = ProxyConfig.fromMap(maps.first);
      _isProxyEnabled = true;
      _applyProxyToDio(_currentProxy!);
      _updateNativeEngineProxy();
    }
    
    final List<Map<String, dynamic>> allMaps = await db.query('proxies', where: 'isActive = ?', whereArgs: [0]);
    _importedProxies = allMaps.map((m) => ProxyConfig.fromMap(m)).toList();
    
    notifyListeners();
  }

  void _applyProxyToDio(ProxyConfig proxy) {
    dioClient.setProxy(
      proxy.host, 
      proxy.port, 
      proxy.type,
      username: proxy.username,
      password: proxy.password,
    );
  }

  Future<void> setProxy(ProxyConfig proxy) async {
    final activeProxy = ProxyConfig(
      id: proxy.id.isEmpty ? 'global_proxy' : proxy.id,
      name: proxy.name,
      host: proxy.host,
      port: proxy.port,
      type: proxy.type,
      username: proxy.username,
      password: proxy.password,
      isActive: true,
    );

    _currentProxy = activeProxy;
    _isProxyEnabled = true;
    _applyProxyToDio(activeProxy);
    _updateNativeEngineProxy();

    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.update('proxies', {'isActive': 0});
      await txn.insert(
        'proxies', 
        activeProxy.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    notifyListeners();
  }

  Future<void> clearProxy() async {
    _currentProxy = null;
    _isProxyEnabled = false;
    dioClient.clearProxy();
    _updateNativeEngineProxy();
    final db = await _dbHelper.database;
    await db.update('proxies', {'isActive': 0});
    notifyListeners();
  }
  
  void toggleProxy(bool enable) {
    if (_currentProxy == null) return;
    
    _isProxyEnabled = enable;
    if (enable) {
      _applyProxyToDio(_currentProxy!);
    } else {
      dioClient.clearProxy();
    }
    _updateNativeEngineProxy();
    notifyListeners();
  }
  
  // importFromYaml remains the same ...

  Future<void> importFromYaml() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['yaml', 'yml'],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String yamlString = await file.readAsString();
        final yamlMap = loadYaml(yamlString);

        if (yamlMap['proxies'] != null) {
          final db = await _dbHelper.database;
          final proxiesList = yamlMap['proxies'] as YamlList;
          
          await db.transaction((txn) async {
            for (var item in proxiesList) {
              if (item is YamlMap) {
                final Map<String, dynamic> proxyMap = {
                  'id': item['name']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
                  'name': item['name']?.toString() ?? 'Imported Proxy',
                  'host': item['server']?.toString() ?? '',
                  'port': item['port'] is int ? item['port'] : int.tryParse(item['port']?.toString() ?? '0') ?? 0,
                  'type': item['type']?.toString().toUpperCase() ?? 'HTTP',
                  'username': item['username']?.toString(),
                  'password': item['password']?.toString(),
                  'isActive': 0,
                };
                
                final newProxy = ProxyConfig.fromMap(proxyMap);
                _importedProxies.add(newProxy);
                
                await txn.insert(
                  'proxies', 
                  newProxy.toMap(),
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
              }
            }
          });
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error importing YAML: $e');
    }
  }

  void _updateNativeEngineProxy() {
    if (!_isProxyEnabled || _currentProxy == null) {
      NativeBridge().init(environment: {}); // Clear proxy env
      return;
    }

    final proxy = _currentProxy!;
    final String protocol = proxy.type.toLowerCase().startsWith('socks') ? 'socks5' : 'http';
    String proxyUrl = "";
    if (proxy.username != null && proxy.username!.isNotEmpty && 
        proxy.password != null && proxy.password!.isNotEmpty) {
        proxyUrl = "$protocol://${proxy.username}:${proxy.password}@${proxy.host}:${proxy.port}";
    } else {
        proxyUrl = "$protocol://${proxy.host}:${proxy.port}";
    }

    final env = {
      'HTTP_PROXY': proxyUrl,
      'HTTPS_PROXY': proxyUrl,
      'ALL_PROXY': proxyUrl,
      'NO_PROXY': 'localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16',
    };
    NativeBridge().init(environment: env);
  }
}
