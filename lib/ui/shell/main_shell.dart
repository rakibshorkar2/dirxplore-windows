import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';

import '../browser/browser_tab.dart';
import '../downloads/downloads_tab.dart';
import '../bittorrent/bittorrent_tab.dart';
import '../settings/proxy_settings_tab.dart';
import '../settings/app_settings_tab.dart';
import '../../providers/theme_provider.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WindowListener {
  int _selectedIndex = 0;
  
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  final List<Widget> _pages = [
    const BrowserTab(),
    const DownloadsTab(),
    const BittorrentTab(),
    const ProxySettingsTab(),
    const AppSettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    // Evaluate if transparent or fully opaque
    Color scaffoldColor = themeProvider.isGlassyUi ? Colors.transparent : Theme.of(context).scaffoldBackgroundColor;
    Color sidebarColor = themeProvider.isGlassyUi 
      ? Theme.of(context).cardColor.withValues(alpha: 0.85) 
      : Theme.of(context).cardColor;

    return Scaffold(
      backgroundColor: scaffoldColor, 
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(40),
        child: WindowCaption(
          brightness: Theme.of(context).brightness,
          title: const Text('DirXplore', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
      body: Row(
        children: [
          // Sidebar Navbar
          Container(
            width: 200,
            decoration: BoxDecoration(
              color: sidebarColor,
              border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
            ),
            child: ListView(
              children: [
                _buildNavItem(Icons.explore, 'Browser', 0),
                _buildNavItem(Icons.download, 'Downloads', 1),
                _buildNavItem(Icons.cloud_download, 'BitTorrent', 2),
                _buildNavItem(Icons.security, 'Proxy', 3), 
                _buildNavItem(Icons.settings, 'Settings', 4),
              ],
            ),
          ),
          // Main Content with state preservation
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _pages,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String title, int index) {
    final isSelected = _selectedIndex == index;
    return ListTile(
      leading: Icon(icon, color: isSelected ? Theme.of(context).primaryColor : Colors.grey),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
    );
  }
}
