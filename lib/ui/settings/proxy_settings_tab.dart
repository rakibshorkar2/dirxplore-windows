import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/proxy_provider.dart';
import '../../models/proxy_config.dart';
import '../../services/native_bridge.dart';

class ProxySettingsTab extends StatefulWidget {
  const ProxySettingsTab({super.key});

  @override
  State<ProxySettingsTab> createState() => _ProxySettingsTabState();
}

class _ProxySettingsTabState extends State<ProxySettingsTab> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  
  String _type = 'SOCKS5';
  String _testResult = '';
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AppProxyProvider>(context, listen: false);
      if (provider.currentProxy != null) {
        _populateFields(provider.currentProxy!);
      }
    });
  }

  void _populateFields(ProxyConfig proxy) {
    _hostController.text = proxy.host;
    _portController.text = proxy.port.toString();
    _usernameController.text = proxy.username ?? '';
    _passwordController.text = proxy.password ?? '';
    setState(() {
      if (['SOCKS5', 'SOCKS4', 'PROXY'].contains(proxy.type.toUpperCase())) {
        _type = proxy.type.toUpperCase();
      } else {
        _type = 'PROXY'; // Default fallback
      }
    });
  }

  Future<void> _testProxy() async {
    if (_hostController.text.isEmpty || _portController.text.isEmpty) {
      setState(() => _testResult = 'Please enter host and port');
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = 'Testing...';
    });

    try {
      final String protocol = _type.toLowerCase().startsWith('socks') ? 'socks5' : 'http';
      String? proxyUrl;
      if (_hostController.text.isNotEmpty && _portController.text.isNotEmpty) {
        if (_usernameController.text.isNotEmpty && _passwordController.text.isNotEmpty) {
          proxyUrl = "$protocol://${_usernameController.text}:${_passwordController.text}@${_hostController.text}:${_portController.text}";
        } else {
          proxyUrl = "$protocol://${_hostController.text}:${_portController.text}";
        }
      }

      final result = await NativeBridge().testProxy(
        'http://www.gstatic.com/generate_204',
        proxyUrl: proxyUrl,
      );
      
      if (result['success'] == true) {
        setState(() {
          _testResult = 'Success! Latency: ${result['latency']}ms';
        });
      } else {
        setState(() {
          _testResult = 'Failed: ${result['error'] ?? 'Unknown error'}';
        });
      }
    } catch (e) {
      setState(() {
        _testResult = 'Failed: $e';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProxyProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Proxy Configuration', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                icon: const Icon(Icons.file_upload),
                label: const Text('Import YAML'),
                onPressed: () async {
                  await provider.importFromYaml();
                  if (provider.importedProxies.isNotEmpty) {
                    _populateFields(provider.importedProxies.last);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (provider.currentProxy != null)
            SwitchListTile(
              title: const Text('Enable Global Proxy', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Routes Browser and Downloads via ${provider.currentProxy!.host}:${provider.currentProxy!.port}'),
              value: provider.isProxyEnabled,
              onChanged: (val) {
                provider.toggleProxy(val);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(val ? 'Proxy Enabled' : 'Proxy Disabled globally'),
                ));
              },
              contentPadding: EdgeInsets.zero,
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _hostController,
                  decoration: const InputDecoration(labelText: 'Host (e.g. 127.0.0.1)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _portController,
                  decoration: const InputDecoration(labelText: 'Port (e.g. 1080)', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 16),
              DropdownButton<String>(
                value: _type,
                items: ['SOCKS5', 'SOCKS4', 'PROXY'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _type = val);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: 'Username (Optional)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Password (Optional)', border: OutlineInputBorder()),
                  obscureText: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              ElevatedButton.icon(
                icon: _isTesting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.network_check),
                label: const Text('Test Proxy'),
                onPressed: _isTesting ? null : _testProxy,
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: () {
                  if (_hostController.text.isEmpty || _portController.text.isEmpty) return;
                  final config = ProxyConfig(
                    id: 'global_proxy',
                    host: _hostController.text,
                    port: int.parse(_portController.text),
                    type: _type,
                    username: _usernameController.text.isNotEmpty ? _usernameController.text : null,
                    password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
                  );
                  provider.setProxy(config);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Proxy applied globally')));
                },
                child: const Text('Save & Apply'),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: () {
                  provider.clearProxy();
                  _hostController.clear();
                  _portController.clear();
                  _usernameController.clear();
                  _passwordController.clear();
                  setState(() { _testResult = ''; });
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Proxy cleared')));
                },
                child: const Text('Clear Active Proxy'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_testResult.isNotEmpty)
            Text(_testResult, style: TextStyle(
              color: _testResult.startsWith('Success') ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            )),
          const SizedBox(height: 32),
          if (provider.importedProxies.isNotEmpty) ...[
            const Divider(),
            const SizedBox(height: 16),
            const Text('Imported Proxies', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: provider.importedProxies.length,
              itemBuilder: (context, index) {
                final proxy = provider.importedProxies[index];
                return ListTile(
                  leading: const Icon(Icons.rocket_launch),
                  title: Text(proxy.name.isNotEmpty ? proxy.name : '${proxy.host}:${proxy.port}'),
                  subtitle: Text('${proxy.type} - Auth: ${proxy.username != null ? 'Yes' : 'No'}'),
                  trailing: ElevatedButton(
                    onPressed: () => _populateFields(proxy),
                    child: const Text('Use'),
                  ),
                );
              },
            ),
          ]
        ],
      ),
    );
  }
}
