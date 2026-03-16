import 'dart:io';

class AppHttpOverrides extends HttpOverrides {
  final int localProxyPort;

  AppHttpOverrides({required this.localProxyPort});

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..findProxy = (uri) {
        // Send all traffic through the Go gateway except localhost
        final host = uri.host.toLowerCase();
        if (host == 'localhost' || 
            host == '127.0.0.1' || 
            host == '::1' || 
            host == '[::1]') {
          return "DIRECT";
        }
        return "PROXY 127.0.0.1:$localProxyPort";
      }
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}
