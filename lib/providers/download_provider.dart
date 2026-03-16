import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/download_task.dart';
import '../core/database/db_helper.dart';
import '../services/native_bridge.dart';

class DownloadProvider with ChangeNotifier {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  
  DownloadProvider() {
    _initNativeListener();
  }

  void _initNativeListener() {
    NativeBridge().updates.listen((data) {
      final id = data['id'];
      final taskIndex = _tasks.indexWhere((t) => t.id == id);
      if (taskIndex != -1) {
        final task = _tasks[taskIndex];
        task.status = data['status'] ?? task.status;
        task.downloadedBytes = data['downloaded'] ?? task.downloadedBytes;
        
        // Preserve total size if it's already set and new total is 0 or null
        if (data['total'] != null && data['total'] > 0) {
          task.totalBytes = data['total'];
        }
        
        task.progress = data['progress'] ?? task.progress;
        task.speed = data['speed'] ?? task.speed;
        
        if (task.status == 'completed') {
           _currentActiveDownloads--;
           task.speed = 0;
           _processQueue();
        } else if (task.status == 'error') {
           _currentActiveDownloads--;
           task.speed = 0;
           _processQueue();
        } else if (task.status == 'paused') {
           // Paused count is handled in pauseDownload
           task.speed = 0;
        }
        
        notifyListeners();
        _updateTaskInDb(task);
      }
    });
  }


  
  List<DownloadTask> _tasks = [];
  List<DownloadTask> get tasks => _tasks;

  Set<String> _selectedIds = {};
  Set<String> get selectedIds => _selectedIds;

  bool get isSelectionMode => _selectedIds.isNotEmpty;

  void toggleSelection(String id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    notifyListeners();
  }

  void selectAll() {
    _selectedIds = _tasks.map((t) => t.id).toSet();
    notifyListeners();
  }

  int maxConcurrentDownloads = 3;
  int _currentActiveDownloads = 0;



  Future<void> loadTasks() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('downloads');
    _tasks = List.generate(maps.length, (i) {
      return DownloadTask.fromMap(maps[i]);
    });
    notifyListeners();
  }

  Future<void> addDownload(String url, String savePath, String fileName) async {
    int existingSize = 0;
    try {
      final file = File(savePath);
      if (await file.exists()) {
        existingSize = await file.length();
      }
    } catch (e) {
      debugPrint('Error checking existing file: $e');
    }

    final task = DownloadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: url,
      savePath: savePath,
      fileName: fileName,
      downloadedBytes: existingSize,
      progress: 0.0, // Will be updated on first progress from bridge
    );
    _tasks.add(task);
    final db = await _dbHelper.database;
    await db.insert('downloads', task.toMap());
    notifyListeners();
    _processQueue();
  }

  void _processQueue() {
    if (_currentActiveDownloads >= maxConcurrentDownloads) return;

    final pendingTasks = _tasks.where((t) => t.status == 'pending').toList();
    for (var task in pendingTasks) {
      if (_currentActiveDownloads >= maxConcurrentDownloads) break;
      _startDownload(task);
    }
  }

  Future<void> _startDownload(DownloadTask task) async {
    // Refresh existing size before starting
    try {
      final file = File(task.savePath);
      if (await file.exists()) {
        task.downloadedBytes = await file.length();
      }
    } catch (_) {}

    task.status = 'downloading';
    _currentActiveDownloads++;
    notifyListeners();
    
    _updateTaskInDb(task);

    // Offload to Native Go Engine
    NativeBridge().startDownload(task.id, task.url, task.savePath);
  }

  Future<void> pauseDownload(String id) async {
    final task = _tasks.firstWhere((t) => t.id == id);
    if (task.status == 'downloading' || task.status == 'pending') {
      task.status = 'paused';
      task.speed = 0;
      NativeBridge().pauseDownload(id);
      await _updateTaskInDb(task);
      notifyListeners();
    }
  }

  Future<void> resumeDownload(String id) async {
    final task = _tasks.firstWhere((t) => t.id == id);
    if (task.status == 'paused' || task.status == 'error') {
      task.status = 'pending';
      NativeBridge().resumeDownload(id);
      await _updateTaskInDb(task);
      notifyListeners();
      _processQueue();
    }
  }

  Future<void> pauseAll() async {
    for (var task in _tasks) {
      if (task.status == 'downloading' || task.status == 'pending') {
        task.status = 'paused';
        task.speed = 0;
        await _updateTaskInDb(task);
      }
    }
    notifyListeners();
  }

  Future<void> resumeAll() async {
    for (var task in _tasks) {
      if (task.status == 'paused' || task.status == 'error') {
        task.status = 'pending';
        await _updateTaskInDb(task);
      }
    }
    notifyListeners();
    _processQueue();
  }

  Future<void> deleteTask(String id, {bool deleteFile = false}) async {
    final taskIndex = _tasks.indexWhere((t) => t.id == id);
    if (taskIndex != -1) {
      final task = _tasks[taskIndex];

      // Delete file if requested
      if (deleteFile) {
        try {
          final file = File(task.savePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          debugPrint('Error deleting file: $e');
        }
      }

      // Stop native download
      NativeBridge().cancelDownload(id);

      // Remove from DB
      final db = await _dbHelper.database;
      await db.delete('downloads', where: 'id = ?', whereArgs: [id]);

      // Remove from list
      _tasks.removeAt(taskIndex);
      _selectedIds.remove(id);
      notifyListeners();
    }
  }

  Future<void> deleteSelected({bool deleteFiles = false}) async {
    final idsToDelete = _selectedIds.toList();
    for (var id in idsToDelete) {
      await deleteTask(id, deleteFile: deleteFiles);
    }
    _selectedIds.clear();
    notifyListeners();
  }

  Future<void> deleteAll({bool deleteFiles = false}) async {
    final idsToDelete = _tasks.map((t) => t.id).toList();
    for (var id in idsToDelete) {
      await deleteTask(id, deleteFile: deleteFiles);
    }
    notifyListeners();
  }

  Future<void> _updateTaskInDb(DownloadTask task) async {
    final db = await _dbHelper.database;
    await db.update(
      'downloads',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }
}
