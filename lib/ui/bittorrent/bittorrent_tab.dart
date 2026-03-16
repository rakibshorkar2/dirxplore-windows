import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/torrent_search_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/app_settings_provider.dart';
import '../../models/torrent_result.dart';

class BittorrentTab extends StatefulWidget {
  const BittorrentTab({super.key});

  @override
  State<BittorrentTab> createState() => _BittorrentTabState();
}

class _BittorrentTabState extends State<BittorrentTab> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchProvider = context.watch<TorrentSearchProvider>();
    final theme = Theme.of(context);

    return Column(
      children: [
        // Search Header
        Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BitTorrent Search',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search for torrents...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searchProvider.isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: () =>
                                searchProvider.search(_searchCtrl.text),
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 15),
                  ),
                  onSubmitted: (val) => searchProvider.search(val),
                ),
              ),
              const SizedBox(height: 16),
              // Category Filters
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    'All',
                    'Movies',
                    'TV',
                    'Games',
                    'Music',
                    'Apps',
                    'Other'
                  ].map((cat) {
                    final isSelected = searchProvider.currentCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(cat),
                        selected: isSelected,
                        onSelected: (_) => searchProvider.setCategory(cat),
                        selectedColor: theme.primaryColor.withValues(alpha: 0.2),
                        checkmarkColor: theme.primaryColor,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        // Results
        Expanded(
          child: _buildResultsList(searchProvider),
        ),
      ],
    );
  }

  Widget _buildResultsList(TorrentSearchProvider provider) {
    if (provider.isLoading && provider.results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(provider.error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => provider.search(_searchCtrl.text),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final filteredResults = provider.currentCategory == 'All'
        ? provider.results
        : provider.results
            .where((r) => r.category.contains(provider.currentCategory))
            .toList();

    if (filteredResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text('No torrents found.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: filteredResults.length,
      itemBuilder: (ctx, i) {
        final result = filteredResults[i];
        return _TorrentResultTile(result: result);
      },
    );
  }
}

class _TorrentResultTile extends StatelessWidget {
  final TorrentResult result;
  const _TorrentResultTile({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloadProvider = context.read<DownloadProvider>();
    final settingsProvider = context.read<AppSettingsProvider>();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(result.title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Row(
          children: [
            Text(result.size, style: TextStyle(fontSize: 12, color: theme.hintColor)),
            const SizedBox(width: 12),
            Icon(Icons.arrow_upward, size: 12, color: Colors.green),
            Text('${result.seeds}',
                style: const TextStyle(fontSize: 12, color: Colors.green)),
            const SizedBox(width: 8),
            Icon(Icons.arrow_downward, size: 12, color: Colors.red),
            Text('${result.leeches}',
                style: const TextStyle(fontSize: 12, color: Colors.red)),
            const Spacer(),
            Text(result.provider,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor.withValues(alpha: 0.7))),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    // Copy magnet
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy Magnet'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () async {
                    String magnet = result.magnet;
                    if (result.provider == '1337x' && magnet.startsWith('http')) {
                      // Fetch real magnet
                      final provider = context.read<TorrentSearchProvider>();
                      final realMagnet = await provider.getMagnetFor1337x(magnet);
                      if (realMagnet != null) {
                        magnet = realMagnet;
                      } else {
                        // Show error
                        return;
                      }
                    }
                    
                    final savePath = settingsProvider.getSortedSavePath(result.title);
                    await settingsProvider.ensureFolderExists(savePath);
                    downloadProvider.addDownload(magnet, savePath, result.title);
                    
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Added to downloads.'))
                      );
                    }
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
