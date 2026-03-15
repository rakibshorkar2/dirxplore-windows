class ProxyConfig {
  final String id;
  final String name; // Name mapped from YAML 'name'
  final String host; // Mapped from YAML 'server'
  final int port;
  final String type;
  final String? username;
  final String? password;
  final bool isActive;

  ProxyConfig({
    required this.id,
    this.name = '',
    required this.host,
    required this.port,
    required this.type,
    this.username,
    this.password,
    this.isActive = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'type': type,
      'username': username,
      'password': password,
      'isActive': isActive ? 1 : 0,
    };
  }

  factory ProxyConfig.fromMap(Map<String, dynamic> map) {
    return ProxyConfig(
      id: map['id'],
      name: map['name'] ?? '',
      host: map['host'],
      port: map['port'],
      type: map['type'],
      username: map['username'],
      password: map['password'],
      isActive: map['isActive'] == 1,
    );
  }
}
