import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/directory_parser.dart';
import '../../models/dir_item.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/proxy_provider.dart';
import '../media/media_player_screen.dart';

class BrowserTab extends StatefulWidget {
  const BrowserTab({super.key});

  @override
  State<BrowserTab> createState() => _BrowserTabState();
}

class _BrowserTabState extends State<BrowserTab> {
  final TextEditingController _urlController = TextEditingController(text: 'http://172.16.50.4/');
  late DirectoryParser _parser;
  
  List<DirItem> _items = [];
  bool _isLoading = false;
  String? _error;
  String _currentUrl = 'http://172.16.50.4/';
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    final proxyProvider = Provider.of<AppProxyProvider>(context, listen: false);
    _parser = DirectoryParser(proxyProvider.dioClient);
    _loadDirectory(_currentUrl, addToHistory: false);
  }

  Future<void> _loadDirectory(String url, {bool addToHistory = true}) async {
    // Ensure trailing slash for directory browsing
    if (!url.endsWith('/') && !url.split('/').last.contains('.')) {
      url += '/';
    }
    
    if (url == _currentUrl && _items.isNotEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await _parser.parseUrl(url);
      if (addToHistory && _currentUrl.isNotEmpty) {
        _history.add(_currentUrl);
      }
      
      setState(() {
        _items = items;
        _currentUrl = url;
        _urlController.text = url;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _goBack() {
    if (_history.isNotEmpty) {
      final prevUrl = _history.removeLast();
      _loadDirectory(prevUrl, addToHistory: false);
    }
  }

  void _goHome() {
    _loadDirectory('http://172.16.50.4/');
  }

  void _goUp() {
    if (_currentUrl.isEmpty) return;
    
    final uri = Uri.parse(_currentUrl);
    if (uri.pathSegments.isEmpty || (uri.pathSegments.length == 1 && uri.pathSegments.first.isEmpty)) return;

    List<String> segments = List.from(uri.pathSegments);
    if (segments.last.isEmpty) segments.removeLast(); // Remove trailing slash segment
    if (segments.isNotEmpty) segments.removeLast();
    
    final newPath = segments.isEmpty ? '/' : '/${segments.join('/')}/';
    final newUrl = uri.replace(path: newPath).toString();
    _loadDirectory(newUrl);
  }

  Widget _buildBreadcrumbs() {
    final uri = Uri.parse(_currentUrl);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    
    List<Widget> crumbs = [];
    
    // Origin
    crumbs.add(
      InkWell(
        onTap: () => _loadDirectory(uri.replace(path: '/').toString()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
          child: Text(uri.host, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
        ),
      ),
    );

    String currentPath = '/';
    for (int i = 0; i < segments.length; i++) {
      crumbs.add(const Icon(Icons.chevron_right, size: 16, color: Colors.grey));
      currentPath += '${segments[i]}/';
      final targetUrl = uri.replace(path: currentPath).toString();
      
      crumbs.add(
        InkWell(
          onTap: () => _loadDirectory(targetUrl),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
            child: Text(Uri.decodeComponent(segments[i]), style: const TextStyle(color: Colors.blue)),
          ),
        ),
      );
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: crumbs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Navigation Toolbar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: _history.isNotEmpty ? _goBack : null,
              ),
              IconButton(
                icon: const Icon(Icons.home),
                tooltip: 'Home',
                onPressed: _goHome,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_upward),
                tooltip: 'Up',
                onPressed: _goUp,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: () => _loadDirectory(_currentUrl, addToHistory: false),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    hintText: 'Enter directory URL',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onSubmitted: _loadDirectory,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _loadDirectory(_urlController.text),
                child: const Text('Go'),
              ),
            ],
          ),
        ),
        
        _buildBreadcrumbs(),
        const Divider(height: 1),
        
        // Content Area
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red, fontSize: 16),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () => _loadDirectory(_currentUrl, addToHistory: false),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _items.isEmpty
                ? const Center(child: Text('Directory is empty'))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      // Skip parent directory if we already have breadcrumbs and Up button
                      if (item.name == '..') return const SizedBox.shrink();

                      return ListTile(
                        leading: Icon(
                          item.isDirectory ? Icons.folder : Icons.insert_drive_file,
                          color: item.isDirectory ? Colors.amber : Colors.blueGrey,
                        ),
                        title: Text(item.name),
                        onTap: () {
                          if (item.isDirectory) {
                            _loadDirectory(item.url);
                          } else {
                            final isMedia = item.name.toLowerCase().endsWith('.mp4') || 
                                            item.name.toLowerCase().endsWith('.mkv') || 
                                            item.name.toLowerCase().endsWith('.avi');
                            
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Select Action'),
                                content: Text('What would you like to do with ${item.name}?'),
                                actions: [
                                  if (isMedia)
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => MediaPlayerScreen(url: item.url),
                                          ),
                                        );
                                      },
                                      child: const Text('Play Stream'),
                                    ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Downloading ${item.name}...'))
                                      );
                                      final dlProvider = Provider.of<DownloadProvider>(context, listen: false);
                                      final settings = Provider.of<AppSettingsProvider>(context, listen: false);
                                      final savePath = settings.getSortedSavePath(item.name);
                                      
                                      settings.ensureFolderExists(savePath).then((_) {
                                        dlProvider.addDownload(item.url, savePath, item.name);
                                      });
                                    },
                                    child: const Text('Download'),
                                  )
                                ],
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
        ),
      ],
    );
  }
}
