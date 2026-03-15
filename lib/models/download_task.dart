class DownloadTask {
  final String id;
  final String url;
  final String savePath;
  final String fileName;
  String status; // 'pending', 'downloading', 'paused', 'completed', 'error'
  double progress;
  int speed; // bytes per second
  int totalBytes;
  int downloadedBytes;

  DownloadTask({
    required this.id,
    required this.url,
    required this.savePath,
    required this.fileName,
    this.status = 'pending',
    this.progress = 0.0,
    this.speed = 0,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'url': url,
      'savePath': savePath,
      'fileName': fileName,
      'status': status,
      'progress': progress,
      'speed': speed,
      'totalBytes': totalBytes,
      'downloadedBytes': downloadedBytes,
    };
  }

  factory DownloadTask.fromMap(Map<String, dynamic> map) {
    return DownloadTask(
      id: map['id'],
      url: map['url'],
      savePath: map['savePath'],
      fileName: map['fileName'],
      status: map['status'],
      progress: map['progress'],
      speed: map['speed'],
      totalBytes: map['totalBytes'],
      downloadedBytes: map['downloadedBytes'],
    );
  }
}
