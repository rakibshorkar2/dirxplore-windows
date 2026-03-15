import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../providers/theme_provider.dart';
import '../../providers/app_settings_provider.dart';

class AppSettingsTab extends StatelessWidget {
  const AppSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final settingsProvider = Provider.of<AppSettingsProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('App Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          
          _buildSectionHeader('Appearance'),
          SwitchListTile(
            title: const Text('Dark Mode'),
            subtitle: const Text('Toggle between light and dark themes.'),
            value: themeProvider.isDarkMode,
            onChanged: (val) {
              themeProvider.toggleTheme();
            },
            secondary: Icon(themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Glassy UI'),
            subtitle: const Text('Toggle translucent backgrounds for elements (Glassmorphism).'),
            value: themeProvider.isGlassyUi,
            onChanged: (val) {
              themeProvider.toggleGlassyUi();
            },
            secondary: Icon(themeProvider.isGlassyUi ? Icons.blur_on : Icons.blur_off),
          ),
          
          const SizedBox(height: 32),
          _buildSectionHeader('Downloads'),
          ListTile(
            title: const Text('Download Location'),
            subtitle: Text(settingsProvider.downloadPath.isEmpty ? 'Loading...' : settingsProvider.downloadPath),
            leading: const Icon(Icons.folder_open),
            trailing: ElevatedButton(
              onPressed: () async {
                String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
                if (selectedDirectory != null) {
                  settingsProvider.setDownloadPath(selectedDirectory);
                }
              },
              child: const Text('Change'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Files will be automatically sorted into Videos, Images, etc. folders within this directory.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.blueAccent,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
