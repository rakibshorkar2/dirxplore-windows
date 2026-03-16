import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../providers/proxy_provider.dart';
import '../../models/proxy_config.dart';

class ProxySettingsTab extends StatefulWidget {
  const ProxySettingsTab({super.key});

  @override
  State<ProxySettingsTab> createState() => _ProxySettingsTabState();
}

class _ProxySettingsTabState extends State<ProxySettingsTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProxyProvider>();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.security, color: theme.primaryColor, size: 28),
                  const SizedBox(width: 12),
                  Text('Proxy Manager',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (provider.activeProxy != null)
                    Chip(
                      avatar: const Icon(Icons.check_circle,
                          size: 16, color: Colors.greenAccent),
                      label: Text(
                          'Active: ${provider.activeProxy!.host}:${provider.activeProxy!.port}',
                          style: const TextStyle(fontSize: 12)),
                      backgroundColor: Colors.green.withValues(alpha: 0.15),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Proxies apply only to this app\'s network requests. Not a device-wide VPN.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
        ),
        // Tab bar
        TabBar(
          controller: _tabController,
          isScrollable: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          tabs: const [
            Tab(icon: Icon(Icons.list), text: 'Proxy List'),
            Tab(icon: Icon(Icons.add_circle_outline), text: 'Add Proxy'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _ProxyListView(provider: provider),
              _AddProxyView(
                provider: provider,
                onAdded: () => _tabController.animateTo(0),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Proxy List
// ---------------------------------------------------------------------------
class _ProxyListView extends StatelessWidget {
  final AppProxyProvider provider;
  const _ProxyListView({required this.provider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (provider.proxies.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No proxies configured.',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
            SizedBox(height: 8),
            Text('Go to "Add Proxy" to add your first proxy.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Spacer(),
              FilledButton.icon(
                onPressed: provider.isTestingAll ? null : () => provider.testAllProxies(),
                icon: provider.isTestingAll 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.speed, size: 18),
                label: Text(provider.isTestingAll ? 'Testing All...' : 'Test All'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primaryColor.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: provider.proxies.length,
            itemBuilder: (ctx, i) {
              final proxy = provider.proxies[i];
              return _ProxyListItem(proxy: proxy, provider: provider);
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Proxy List Item
// ---------------------------------------------------------------------------
class _ProxyListItem extends StatefulWidget {
  final ProxyConfig proxy;
  final AppProxyProvider provider;
  const _ProxyListItem({required this.proxy, required this.provider});

  @override
  State<_ProxyListItem> createState() => _ProxyListItemState();
}

class _ProxyListItemState extends State<_ProxyListItem> {
  bool _testing = false;

  Future<void> _runTest() async {
    setState(() => _testing = true);
    await widget.provider.testProxy(widget.proxy);
    if (mounted) setState(() => _testing = false);
  }

  void _showEditDialog() {
    showDialog(
      context: context,
      builder: (_) => _EditProxyDialog(
        proxy: widget.proxy,
        provider: widget.provider,
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Proxy'),
        content: Text(
            'Remove "${widget.proxy.name.isNotEmpty ? widget.proxy.name : '${widget.proxy.host}:${widget.proxy.port}'}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              widget.provider.deleteProxy(widget.proxy.id);
              Navigator.pop(ctx);
            },
            child:
                const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final proxy = widget.proxy;
    final label =
        proxy.name.isNotEmpty ? proxy.name : '${proxy.host}:${proxy.port}';
    final hasAuth = (proxy.username ?? '').isNotEmpty;
    
    // Get test result from provider for unified batch testing
    final testResult = widget.provider.testResults[proxy.id];
    final testSuccess = widget.provider.testSuccess[proxy.id];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: proxy.isActive
            ? BorderSide(color: theme.primaryColor, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Protocol badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(proxy.type,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: theme.primaryColor)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                ),
                // Toggle
                Switch(
                  value: proxy.isActive,
                  onChanged: (val) =>
                      widget.provider.toggleProxy(proxy.id, val),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${proxy.host}:${proxy.port}  •  Auth: ${hasAuth ? 'Yes' : 'No'}',
              style:
                  TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                // Test button
                OutlinedButton.icon(
                  onPressed: _testing ? null : _runTest,
                  icon: _testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check, size: 16),
                  label: const Text('Test', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                // Test result badge
                if (testResult != null)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (testSuccess == true ? Colors.green : Colors.red)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          testSuccess == true
                              ? Icons.check_circle
                              : Icons.cancel,
                          size: 14,
                          color:
                              testSuccess == true ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(testResult,
                            style: TextStyle(
                                fontSize: 12,
                                color: testSuccess == true
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                const Spacer(),
                // Edit
                IconButton(
                  tooltip: 'Edit',
                  onPressed: _showEditDialog,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 4),
                // Delete
                IconButton(
                  tooltip: 'Delete',
                  onPressed: _confirmDelete,
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.redAccent),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add Proxy View — three forms: Manual, URI, YAML
// ---------------------------------------------------------------------------
class _AddProxyView extends StatefulWidget {
  final AppProxyProvider provider;
  final VoidCallback onAdded;
  const _AddProxyView({required this.provider, required this.onAdded});

  @override
  State<_AddProxyView> createState() => _AddProxyViewState();
}

class _AddProxyViewState extends State<_AddProxyView> {
  // Form A — Manual
  final _manualFormKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String _protocol = 'SOCKS5';
  bool _obscurePass = true;

  // Form B — URI
  final _uriFormKey = GlobalKey<FormState>();
  final _uriCtrl = TextEditingController();
  String? _uriParseError;
  ProxyConfig? _parsedPreview;

  // Form C — YAML paste
  final _yamlPasteCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _uriCtrl.dispose();
    _yamlPasteCtrl.dispose();
    super.dispose();
  }

  void _saveManual() {
    if (!_manualFormKey.currentState!.validate()) return;
    final proxy = ProxyConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text.trim().isNotEmpty
          ? _nameCtrl.text.trim()
          : '$_protocol ${_hostCtrl.text}:${_portCtrl.text}',
      host: _hostCtrl.text.trim(),
      port: int.parse(_portCtrl.text.trim()),
      type: _protocol,
      username: _userCtrl.text.trim().isNotEmpty ? _userCtrl.text.trim() : null,
      password: _passCtrl.text.isNotEmpty ? _passCtrl.text : null,
    );
    widget.provider.addProxy(proxy);
    _manualFormKey.currentState!.reset();
    _nameCtrl.clear();
    _hostCtrl.clear();
    _portCtrl.clear();
    _userCtrl.clear();
    _passCtrl.clear();
    setState(() => _protocol = 'SOCKS5');
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Proxy added.')));
    widget.onAdded();
  }

  void _parseUri() {
    final parsed = AppProxyProvider.parseProxyUri(_uriCtrl.text);
    setState(() {
      _parsedPreview = parsed;
      _uriParseError = parsed == null ? 'Invalid proxy URI. Example: socks5://user:pass@host:1080' : null;
    });
  }

  void _saveFromUri() {
    if (_parsedPreview == null) return;
    widget.provider.addProxy(_parsedPreview!);
    _uriCtrl.clear();
    setState(() {
      _parsedPreview = null;
      _uriParseError = null;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Proxy added.')));
    widget.onAdded();
  }

  Future<void> _importYaml() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['yaml', 'yml'],
      );
      
      if (result != null && result.files.single.path != null) {
        final content = await File(result.files.single.path!).readAsString();
        await widget.provider.importProxiesFromYaml(content);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Proxies imported from file.'))
          );
          widget.onAdded();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'))
        );
      }
    }
  }

  Future<void> _importYamlFromText() async {
    final text = _yamlPasteCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      await widget.provider.importProxiesFromYaml(text);
      if (mounted) {
        _yamlPasteCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Proxies imported from pasted YAML.'))
        );
        widget.onAdded();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _importBundledYaml() async {
    try {
      // Look for bypassempire.yaml in the same directory as the executable
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      var yamlFile = File('$exeDir/bypassempire.yaml');
      if (!await yamlFile.exists()) {
        // Fall back to working directory
        yamlFile = File('bypassempire.yaml');
      }
      if (!await yamlFile.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('bypassempire.yaml not found next to the executable.'))
          );
        }
        return;
      }
      final content = await yamlFile.readAsString();
      await widget.provider.importProxiesFromYaml(content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Imported proxies from bypassempire.yaml.'))
        );
        widget.onAdded();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Form A: Manual ----
          Text('Manual Entry',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Form(
            key: _manualFormKey,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Name (optional)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.label_outline)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _protocol,
                      decoration: const InputDecoration(
                          labelText: 'Protocol',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14)),
                      items: ['SOCKS5', 'SOCKS4', 'HTTP', 'HTTPS']
                          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _protocol = v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _hostCtrl,
                        decoration: const InputDecoration(
                            labelText: 'IP / Hostname',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.dns_outlined)),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _portCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Port',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.numbers)),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          final p = int.tryParse(v);
                          if (p == null || p <= 0 || p > 65535) return 'Invalid';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _userCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Username (optional)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person_outline)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _passCtrl,
                        obscureText: _obscurePass,
                        decoration: InputDecoration(
                          labelText: 'Password (optional)',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePass
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () =>
                                setState(() => _obscurePass = !_obscurePass),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _saveManual,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Proxy'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          // ---- Form B: URI ----
          Text('From URI / Link',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Paste a proxy string: socks5://user:pass@host:1080',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 12),
          Form(
            key: _uriFormKey,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _uriCtrl,
                    decoration: InputDecoration(
                      labelText: 'Proxy URI',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.link),
                      errorText: _uriParseError,
                    ),
                    onChanged: (_) {
                      if (_parsedPreview != null || _uriParseError != null) {
                        setState(() {
                          _parsedPreview = null;
                          _uriParseError = null;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _parseUri,
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 18)),
                  child: const Text('Parse'),
                ),
              ],
            ),
          ),
          if (_parsedPreview != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Parsed Successfully ✓',
                      style: TextStyle(
                          color: Colors.green, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                      'Protocol: ${_parsedPreview!.type}  •  Host: ${_parsedPreview!.host}  •  Port: ${_parsedPreview!.port}  •  Auth: ${(_parsedPreview!.username ?? '').isNotEmpty ? 'Yes' : 'No'}',
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _saveFromUri,
                    icon: const Icon(Icons.add),
                    label: const Text('Add This Proxy'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          // ---- Form C: YAML Import ----
          Text('Import from YAML',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Import proxies from a Clash/BypassEmpire compatible YAML file.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 16),

          // Option 1: File picker
          OutlinedButton.icon(
            onPressed: _importYaml,
            icon: const Icon(Icons.upload_file),
            label: const Text('Select YAML File'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          const SizedBox(height: 8),
          // Option 2: Import bundled bypassempire.yaml
          FilledButton.icon(
            onPressed: _importBundledYaml,
            icon: const Icon(Icons.shield_outlined),
            label: const Text('Import Bundled bypassempire.yaml'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          const SizedBox(height: 24),

          // Option 3: Paste YAML inline
          Text('— or paste YAML content directly —',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          const SizedBox(height: 12),
          TextField(
            controller: _yamlPasteCtrl,
            maxLines: 8,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              labelText: 'Paste YAML here',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
              hintText: 'proxies:\n  - name: "My Proxy"\n    type: socks5\n    server: 1.2.3.4\n    port: 1080\n    username: user\n    password: pass',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _importYamlFromText,
            icon: const Icon(Icons.check),
            label: const Text('Import Pasted YAML'),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit Proxy Dialog
// ---------------------------------------------------------------------------
class _EditProxyDialog extends StatefulWidget {
  final ProxyConfig proxy;
  final AppProxyProvider provider;
  const _EditProxyDialog({required this.proxy, required this.provider});

  @override
  State<_EditProxyDialog> createState() => _EditProxyDialogState();
}

class _EditProxyDialogState extends State<_EditProxyDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late String _protocol;
  bool _obscurePass = true;

  @override
  void initState() {
    super.initState();
    final p = widget.proxy;
    _nameCtrl = TextEditingController(text: p.name);
    _hostCtrl = TextEditingController(text: p.host);
    _portCtrl = TextEditingController(text: p.port.toString());
    _userCtrl = TextEditingController(text: p.username ?? '');
    _passCtrl = TextEditingController(text: p.password ?? '');
    _protocol = p.type;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final updated = ProxyConfig(
      id: widget.proxy.id,
      name: _nameCtrl.text.trim().isNotEmpty
          ? _nameCtrl.text.trim()
          : '$_protocol ${_hostCtrl.text}:${_portCtrl.text}',
      host: _hostCtrl.text.trim(),
      port: int.parse(_portCtrl.text.trim()),
      type: _protocol,
      username:
          _userCtrl.text.trim().isNotEmpty ? _userCtrl.text.trim() : null,
      password: _passCtrl.text.isNotEmpty ? _passCtrl.text : null,
      isActive: widget.proxy.isActive,
    );
    widget.provider.updateProxy(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Proxy'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Name', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButtonFormField<String>(
                  initialValue: _protocol,
                  decoration: const InputDecoration(
                      labelText: 'Protocol',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                  items: ['SOCKS5', 'SOCKS4', 'HTTP', 'HTTPS']
                      .map((p) =>
                          DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _protocol = v);
                  },
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _hostCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Host', border: OutlineInputBorder()),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _portCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Port', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      final p = int.tryParse(v);
                      if (p == null || p <= 0 || p > 65535) return 'Invalid';
                      return null;
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Username (optional)',
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscurePass,
                    decoration: InputDecoration(
                      labelText: 'Password (optional)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePass
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _obscurePass = !_obscurePass),
                      ),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
