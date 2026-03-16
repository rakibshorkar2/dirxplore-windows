import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// A custom HttpClientAdapter that redirects requests through the local Go gateway.
/// The Go gateway handles SOCKS5/HTTP protocols and upstream proxy routing.
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
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (uri) {
          final host = uri.host.toLowerCase();
          if (host == 'localhost' || 
              host == '127.0.0.1' || 
              host == '::1' || 
              host == '[::1]') {
            return 'DIRECT';
          }
          return 'PROXY 127.0.0.1:$localPort';
        };
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      },
    );
  }

  void clearProxy() {
    dio.httpClientAdapter = IOHttpClientAdapter();
  }
}
