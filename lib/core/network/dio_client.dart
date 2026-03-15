import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// A custom HttpClientAdapter that redirects requests through the local Go gateway.
/// The Go gateway handles SOCKS5/HTTP protocols and upstream proxy routing.
class GoProxyAdapter implements HttpClientAdapter {
  final int localProxyPort;
  late final IOHttpClientAdapter _adapter;

  GoProxyAdapter({required this.localProxyPort}) {
    _adapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 45); // Increased for stability
        client.findProxy = (uri) {
          // Send all traffic through the Go gateway except localhost
          if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
            return "DIRECT";
          }
          return "PROXY 127.0.0.1:$localProxyPort";
        };
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
    return _adapter.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {
    _adapter.close(force: force);
  }
}

class DioClient {
  late Dio dio;

  DioClient() {
    dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 45),
      ),
    );
  }

  void setProxy(int localPort) {
    dio.httpClientAdapter = GoProxyAdapter(localProxyPort: localPort);
  }

  void clearProxy() {
    dio.httpClientAdapter = IOHttpClientAdapter();
  }
}
