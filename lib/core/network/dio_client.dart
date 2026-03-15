import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:socks5_proxy/socks.dart';

/// A custom HttpClientAdapter that redirects requests based on the host.
/// It bypasses the proxy for local network addresses.
class ProxyBypassAdapter implements HttpClientAdapter {
  final String host;
  final int port;
  final String type;
  final String? username;
  final String? password;
  final bool Function(String host) isLocalAddress;

  late final IOHttpClientAdapter _directAdapter;
  late final IOHttpClientAdapter _proxyAdapter;

  ProxyBypassAdapter({
    required this.host,
    required this.port,
    required this.type,
    this.username,
    this.password,
    required this.isLocalAddress,
  }) {
    _directAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 30);
        client.findProxy = (uri) => "DIRECT"; // Force direct connection
        return client;
      },
    );
    _proxyAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 30);
        
        if (type.toUpperCase().startsWith('SOCKS')) {
          SocksTCPClient.assignToHttpClient(client, [
            ProxySettings(InternetAddress(host), port, username: username, password: password),
          ]);
        } else {
          client.findProxy = (uri) => "PROXY $host:$port";
          final user = username;
          final pass = password;
          if (user != null && pass != null && user.isNotEmpty) {
            client.authenticateProxy = (h, p, s, r) async {
              client.addProxyCredentials(h, p, '', HttpClientBasicCredentials(user, pass));
              return true;
            };
          }
        }
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      },
    );
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (isLocalAddress(options.uri.host)) {
      return _directAdapter.fetch(options, requestStream, cancelFuture);
    }
    return _proxyAdapter.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {
    _directAdapter.close(force: force);
    _proxyAdapter.close(force: force);
  }
}

class DioClient {
  late Dio dio;

  DioClient() {
    dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
  }

  bool _isLocalAddress(String host) {
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') return true;
    
    // Check for private IP ranges
    if (host.startsWith('10.')) return true;
    if (host.startsWith('192.168.')) return true;
    if (host.startsWith('172.')) {
      final parts = host.split('.');
      if (parts.length >= 2) {
        final secondPart = int.tryParse(parts[1]);
        if (secondPart != null && secondPart >= 16 && secondPart <= 31) {
          return true;
        }
      }
    }
    return false;
  }

  void setProxy(String host, int port, String type, {String? username, String? password}) {
    dio.httpClientAdapter = ProxyBypassAdapter(
      host: host,
      port: port,
      type: type,
      username: username,
      password: password,
      isLocalAddress: _isLocalAddress,
    );
  }

  void clearProxy() {
    dio.httpClientAdapter = IOHttpClientAdapter();
  }
}
