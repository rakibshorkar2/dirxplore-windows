import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class AppSettingsProvider with ChangeNotifier {
  String _downloadPath = '';
  String get downloadPath => _downloadPath;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  AppSettingsProvider() {
    _init();
  }

  Future<void> _init() async {
    try {
      Directory? downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) {
        _downloadPath = p.join(downloadsDir.path, 'DirXplore');
      } else {
        // Fallback for Windows if getDownloadsDirectory fails (unlikely)
        _downloadPath = p.join(Platform.environment['USERPROFILE'] ?? 'C:', 'Downloads', 'DirXplore');
      }
      
      // Ensure the directory exists
      final dir = Directory(_downloadPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (e) {
      debugPrint('Error initializing download path: $e');
      _downloadPath = 'C:\\DirXplore'; // Extreme fallback
    }
    
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setDownloadPath(String newPath) async {
    _downloadPath = newPath;
    final dir = Directory(_downloadPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    notifyListeners();
  }

  String getSortedSavePath(String fileName) {
    if (!_isInitialized) return p.join(_downloadPath, fileName);

    final ext = p.extension(fileName).toLowerCase();
    String subFolder = 'Others';

    if (['.mp4', '.mkv', '.avi', '.mov', '.flv', '.wmv'].contains(ext)) {
      subFolder = 'Videos';
    } else if (['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.svg'].contains(ext)) {
      subFolder = 'Images';
    } else if (['.pdf', '.doc', '.docx', '.txt', '.rtf', '.odt', '.xls', '.xlsx', '.ppt', '.pptx'].contains(ext)) {
      subFolder = 'Documents';
    } else if (['.mp3', '.wav', '.aac', '.flac', '.ogg', '.m4a'].contains(ext)) {
      subFolder = 'Music';
    } else if (['.zip', '.rar', '.7z', '.tar', '.gz'].contains(ext)) {
      subFolder = 'Archives';
    }

    final fullDir = p.join(_downloadPath, subFolder);
    
    // We don't create it here as it might be synchronous and blocking UI
    // The DownloadProvider or addDownload logic should ensure it exists or we handle it inside setDownloadPath
    // Actually, it's better to ensure it exists before starting the task.
    
    return p.join(fullDir, fileName);
  }

  Future<void> ensureFolderExists(String filePath) async {
    final folder = p.dirname(filePath);
    final dir = Directory(folder);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }
}
