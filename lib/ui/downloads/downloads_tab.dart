import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/download_provider.dart';

class DownloadsTab extends StatelessWidget {
  const DownloadsTab({super.key});

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    double b = bytes.toDouble();
    while (b > 1024 && i < suffixes.length - 1) {
      b /= 1024;
      i++;
    }
    return '${b.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<void> _showDeleteConfirmation(BuildContext context, DownloadProvider provider, {String? taskId, bool isBulk = false}) async {
    bool deleteFiles = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isBulk ? 'Delete All Downloads' : (taskId != null ? 'Delete Download' : 'Delete Selected')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isBulk 
                ? 'Are you sure you want to remove all download tasks?' 
                : 'Are you sure you want to remove these download tasks?'),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('Also delete downloaded files from storage'),
                value: deleteFiles,
                onChanged: (val) => setState(() => deleteFiles = val ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
            TextButton(
              onPressed: () => Navigator.pop(context, true), 
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('DELETE'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      if (isBulk) {
        await provider.deleteAll(deleteFiles: deleteFiles);
      } else if (taskId != null) {
        await provider.deleteTask(taskId, deleteFile: deleteFiles);
      } else {
        await provider.deleteSelected(deleteFiles: deleteFiles);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadProvider>(
      builder: (context, provider, child) {
        final tasks = provider.tasks.reversed.toList();
        final isSelectionMode = provider.isSelectionMode;

        return Column(
          children: [
            // Top Toolbar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              ),
              child: Row(
                children: [
                  if (isSelectionMode) ...[
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => provider.clearSelection(),
                      tooltip: 'Clear Selection',
                    ),
                    Text('${provider.selectedIds.length} Selected', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => _showDeleteConfirmation(context, provider),
                      tooltip: 'Delete Selected',
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.select_all),
                      onPressed: () => provider.selectAll(),
                      tooltip: 'Select All',
                    ),
                  ] else ...[
                    const Text('Downloads', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (tasks.isNotEmpty) ...[
                      TextButton.icon(
                        icon: const Icon(Icons.pause_circle_outline, size: 20),
                        label: const Text('Pause All'),
                        onPressed: () => provider.pauseAll(),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.play_circle_outline, size: 20),
                        label: const Text('Resume All'),
                        onPressed: () => provider.resumeAll(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                        onPressed: () => _showDeleteConfirmation(context, provider, isBulk: true),
                        tooltip: 'Delete All',
                      ),
                    ]
                  ],
                ],
              ),
            ),
            
            // Task List
            Expanded(
              child: tasks.isEmpty
                ? const Center(child: Text('No active downloads'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      final isSelected = provider.selectedIds.contains(task.id);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12.0),
                        color: isSelected 
                            ? Theme.of(context).primaryColor.withValues(alpha: 0.2)
                            : Theme.of(context).cardColor.withValues(alpha: 0.6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                            color: isSelected 
                                ? Theme.of(context).primaryColor 
                                : Colors.white.withValues(alpha: 0.1), 
                            width: 1
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: InkWell(
                          onLongPress: () => provider.toggleSelection(task.id),
                          onTap: isSelectionMode ? () => provider.toggleSelection(task.id) : null,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (isSelectionMode)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 12),
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: Checkbox(
                                            value: isSelected,
                                            onChanged: (_) => provider.toggleSelection(task.id),
                                          ),
                                        ),
                                      ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            task.fileName, 
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(task.status.toUpperCase(), style: TextStyle(
                                            fontSize: 12,
                                            color: task.status == 'completed' ? Colors.green : (task.status == 'error' ? Colors.red : Colors.grey)
                                          )),
                                        ],
                                      ),
                                    ),
                                    if (!isSelectionMode)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                                        onPressed: () => _showDeleteConfirmation(context, provider, taskId: task.id),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: task.totalBytes > 0 ? (task.downloadedBytes / task.totalBytes).clamp(0.0, 1.0) : 0,
                                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('${_formatBytes(task.downloadedBytes)} / ${_formatBytes(task.totalBytes)}', 
                                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    if (task.status == 'downloading')
                                      Text('${_formatBytes(task.speed)}/s', style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                                if (!isSelectionMode) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (task.status == 'downloading' || task.status == 'pending')
                                        IconButton(
                                          icon: const Icon(Icons.pause),
                                          onPressed: () => provider.pauseDownload(task.id),
                                        ),
                                      if (task.status == 'paused' || task.status == 'error')
                                        IconButton(
                                          icon: const Icon(Icons.play_arrow),
                                          onPressed: () => provider.resumeDownload(task.id),
                                        ),
                                    ],
                                  )
                                ]
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ],
        );
      },
    );
  }
}
