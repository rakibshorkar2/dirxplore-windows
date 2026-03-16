import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yaml/yaml.dart';
import '../models/proxy_config.dart';
import '../core/network/dio_client.dart';
import '../core/network/app_http_overrides.dart';
import '../core/database/db_helper.dart';
import '../services/native_bridge.dart';

class AppProxyProvider with ChangeNotifier {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final DioClient dioClient = DioClient();

  List<ProxyConfig> _proxies = [];
  List<ProxyConfig> get proxies => _proxies;

  final Map<String, String> _testResults = {};
  Map<String, String?> get testResults => _testResults;

  final Map<String, bool> _testSuccess = {};
  Map<String, bool?> get testSuccess => _testSuccess;

  bool _isTestingAll = false;
  bool get isTestingAll => _isTestingAll;

  ProxyConfig? get activeProxy {
    try {
      return _proxies.firstWhere((p) => p.isActive);
    } catch (_) {
      return null;
    }
  }

  bool get isProxyEnabled => activeProxy != null;

  // -----------------------------------------------------------------------
  // Init
  // -----------------------------------------------------------------------
  Future<void> loadProxies() async {
    final db = await _dbHelper.database;
    final maps = await db.query('proxies');
    _proxies = maps.map((m) => ProxyConfig.fromMap(m)).toList();
    // Apply active proxy if present
    if (activeProxy != null) {
      await _applyProxy(activeProxy!);
    }
    notifyListeners();
  }

  // -----------------------------------------------------------------------
  // Add / Edit / Delete
  // -----------------------------------------------------------------------
  Future<void> addProxy(ProxyConfig proxy) async {
    final db = await _dbHelper.database;
    await db.insert('proxies', proxy.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    _proxies.add(proxy);
    notifyListeners();
  }

  Future<void> updateProxy(ProxyConfig proxy) async {
    final db = await _dbHelper.database;
    await db.update('proxies', proxy.toMap(), where: 'id = ?', whereArgs: [proxy.id]);
    final idx = _proxies.indexWhere((p) => p.id == proxy.id);
    if (idx != -1) _proxies[idx] = proxy;
    if (proxy.isActive) {
      await _applyProxy(proxy);
    }
    notifyListeners();
  }

  Future<void> deleteProxy(String id) async {
    final db = await _dbHelper.database;
    final proxy = _proxies.firstWhere((p) => p.id == id, orElse: () => ProxyConfig(id: id, host: '', port: 0, type: 'HTTP'));
    if (proxy.isActive) {
      await _clearActiveProxy();
    }
    await db.delete('proxies', where: 'id = ?', whereArgs: [id]);
    _proxies.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  // -----------------------------------------------------------------------
  // Toggle ON/OFF for a specific proxy
  // -----------------------------------------------------------------------
  Future<void> toggleProxy(String id, bool enable) async {
    final db = await _dbHelper.database;

    if (enable) {
      // Deactivate all others
      await db.update('proxies', {'isActive': 0});
      for (var i = 0; i < _proxies.length; i++) {
        _proxies[i] = ProxyConfig(
          id: _proxies[i].id,
          name: _proxies[i].name,
          host: _proxies[i].host,
          port: _proxies[i].port,
          type: _proxies[i].type,
          username: _proxies[i].username,
          password: _proxies[i].password,
          isActive: false,
        );
      }
      // Activate the chosen one
      final idx = _proxies.indexWhere((p) => p.id == id);
      if (idx != -1) {
        final activated = ProxyConfig(
          id: _proxies[idx].id,
          name: _proxies[idx].name,
          host: _proxies[idx].host,
          port: _proxies[idx].port,
          type: _proxies[idx].type,
          username: _proxies[idx].username,
          password: _proxies[idx].password,
          isActive: true,
        );
        _proxies[idx] = activated;
        await db.update('proxies', {'isActive': 1}, where: 'id = ?', whereArgs: [id]);
        await _applyProxy(activated);
      }
    } else {
      // Deactivate this proxy
      final idx = _proxies.indexWhere((p) => p.id == id);
      if (idx != -1 && _proxies[idx].isActive) {
        _proxies[idx] = ProxyConfig(
          id: _proxies[idx].id,
          name: _proxies[idx].name,
          host: _proxies[idx].host,
          port: _proxies[idx].port,
          type: _proxies[idx].type,
          username: _proxies[idx].username,
          password: _proxies[idx].password,
          isActive: false,
        );
        await db.update('proxies', {'isActive': 0}, where: 'id = ?', whereArgs: [id]);
        await _clearActiveProxy();
      }
    }
    notifyListeners();
  }

  // -----------------------------------------------------------------------
  // Internal: Apply / clear proxy (app-only via HttpOverrides + DioClient)
  // -----------------------------------------------------------------------
  Future<void> _applyProxy(ProxyConfig proxy) async {
    // 1. Start native engine with proxy env vars (for downloads)
    final env = _buildEnvVars(proxy);
    try {
      final port = await NativeBridge().init(environment: env);
      // 2. Route DioClient through the Go gateway
      dioClient.setProxy(port);
      // 3. Route all other HttpClient requests through the Go gateway
      HttpOverrides.global = AppHttpOverrides(localProxyPort: port);
    } catch (e) {
      debugPrint('Failed to apply proxy: $e');
    }
  }

  Future<void> _clearActiveProxy() async {
    dioClient.clearProxy();
    HttpOverrides.global = null;
    try {
      await NativeBridge().init(environment: {}); // clear proxy from engine
    } catch (e) {
      debugPrint('Failed to clear proxy from engine: $e');
    }
  }

  Map<String, String> _buildEnvVars(ProxyConfig proxy) {
    final protocol = proxy.type.toLowerCase().startsWith('socks') ? 'socks5' : 'http';
    final String proxyUrl;
    if ((proxy.username ?? '').isNotEmpty && (proxy.password ?? '').isNotEmpty) {
      proxyUrl = '$protocol://${proxy.username}:${proxy.password}@${proxy.host}:${proxy.port}';
    } else {
      proxyUrl = '$protocol://${proxy.host}:${proxy.port}';
    }
    return {
      'HTTP_PROXY': proxyUrl,
      'HTTPS_PROXY': proxyUrl,
      'ALL_PROXY': proxyUrl,
      'NO_PROXY': 'localhost,127.0.0.1',
    };
  }

  // -----------------------------------------------------------------------
  // Test proxy connectivity (via native engine)
  // -----------------------------------------------------------------------
  Future<Map<String, dynamic>> testProxy(ProxyConfig proxy) async {
    final protocol = proxy.type.toLowerCase().startsWith('socks') ? 'socks5' : 'http';
    final String proxyUrl;
    if ((proxy.username ?? '').isNotEmpty && (proxy.password ?? '').isNotEmpty) {
      proxyUrl = '$protocol://${proxy.username}:${proxy.password}@${proxy.host}:${proxy.port}';
    } else {
      proxyUrl = '$protocol://${proxy.host}:${proxy.port}';
    }
    final res = await NativeBridge().testProxy(
      'http://www.gstatic.com/generate_204',
      proxyUrl: proxyUrl,
    );

    if (res['success'] == true) {
      _testResults[proxy.id] = '${res['latency']} ms';
      _testSuccess[proxy.id] = true;
    } else {
      _testResults[proxy.id] = res['error'] ?? 'Failed';
      _testSuccess[proxy.id] = false;
    }
    notifyListeners();
    return res;
  }

  // -----------------------------------------------------------------------
  // URI Parser: socks5://user:pass@host:port
  // -----------------------------------------------------------------------
  // -----------------------------------------------------------------------
  // Batch Operations: YAML Import & Test All
  // -----------------------------------------------------------------------
  Future<void> importProxiesFromYaml(String yamlContent) async {
    try {
      final doc = loadYaml(yamlContent);
      if (doc is! YamlMap || !doc.containsKey('proxies')) return;
      
      final YamlList proxyList = doc['proxies'];
      final db = await _dbHelper.database;
      
      for (final item in proxyList) {
        if (item is! YamlMap) continue;
        
        final name = item['name']?.toString() ?? '';
        final type = (item['type']?.toString().toUpperCase()) ?? 'SOCKS5';
        final server = item['server']?.toString() ?? '';
        final port = int.tryParse(item['port']?.toString() ?? '0') ?? 0;
        final user = item['username']?.toString();
        final pass = item['password']?.toString();
        
        if (server.isEmpty || port == 0) continue;
        
        final proxy = ProxyConfig(
          id: DateTime.now().millisecondsSinceEpoch.toString() + server + port.toString(),
          name: name,
          host: server,
          port: port,
          type: type,
          username: (user ?? '').isEmpty ? null : user,
          password: (pass ?? '').isEmpty ? null : pass,
        );
        
        await db.insert('proxies', proxy.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await loadProxies();
    } catch (e) {
      debugPrint('YAML Import Error: $e');
    }
  }

  Future<void> testAllProxies() async {
    if (_isTestingAll) return;
    _isTestingAll = true;
    _testResults.clear();
    _testSuccess.clear();
    notifyListeners();

    // Test in chunks of 5 to avoid overloading the bridge
    const chunkSize = 5;
    for (var i = 0; i < _proxies.length; i += chunkSize) {
      final chunk = _proxies.skip(i).take(chunkSize);
      await Future.wait(chunk.map((p) => testProxy(p)));
    }

    _isTestingAll = false;
    notifyListeners();
  }

  static ProxyConfig? parseProxyUri(String uri) {
    try {
      final parsed = Uri.parse(uri.trim());
      final scheme = parsed.scheme.toUpperCase();
      final typeMap = {
        'SOCKS5': 'SOCKS5',
        'SOCKS4': 'SOCKS4',
        'HTTP': 'HTTP',
        'HTTPS': 'HTTPS',
      };
      final type = typeMap[scheme] ?? 'HTTP';
      final host = parsed.host;
      final port = parsed.port;
      final username = parsed.userInfo.isNotEmpty ? parsed.userInfo.split(':').first : null;
      final password = parsed.userInfo.contains(':') ? parsed.userInfo.split(':').skip(1).join(':') : null;

      if (host.isEmpty || port == 0) return null;

      return ProxyConfig(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: '$type $host:$port',
        host: host,
        port: port,
        type: type,
        username: (username ?? '').isEmpty ? null : username,
        password: (password ?? '').isEmpty ? null : password,
      );
    } catch (_) {
      return null;
    }
  }
}
