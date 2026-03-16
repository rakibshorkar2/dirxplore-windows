import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as hp;
import '../models/torrent_result.dart';
import '../core/network/dio_client.dart';

class TorrentSearchProvider with ChangeNotifier {
  final DioClient _dioClient = DioClient();
  
  List<TorrentResult> _results = [];
  List<TorrentResult> get results => _results;
  
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  String? _error;
  String? get error => _error;

  String _currentCategory = 'All';
  String get currentCategory => _currentCategory;

  void setCategory(String category) {
    _currentCategory = category;
    notifyListeners();
  }

  Future<void> search(String query) async {
    if (query.isEmpty) return;
    
    _isLoading = true;
    _error = null;
    _results = [];
    notifyListeners();

    try {
      // Run searches in parallel
      final searches = await Future.wait([
        _searchYTS(query),
        _search1337x(query),
        // Add more providers here
      ]);

      for (var list in searches) {
        _results.addAll(list);
      }

      // Sort by seeds by default
      _results.sort((a, b) => b.seeds.compareTo(a.seeds));
      
    } catch (e) {
      _error = 'Failed to fetch results: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<TorrentResult>> _searchYTS(String query) async {
    try {
      final response = await _dioClient.dio.get(
        'https://yts.mx/api/v2/list_movies.json',
        queryParameters: {'query_term': query, 'limit': 20},
      );
      
      if (response.data['status'] == 'ok' && response.data['data']['movies'] != null) {
        final List movies = response.data['data']['movies'];
        return movies.expand((movie) {
          final List torrents = movie['torrents'] ?? [];
          return torrents.map((t) {
            return TorrentResult(
              title: '${movie['title']} (${movie['year']}) [${t['quality']}] [${t['type']}]',
              size: t['size'] ?? '',
              seeds: t['seeds'] ?? 0,
              leeches: t['peers'] ?? 0,
              category: 'Movies',
              magnet: _buildMagnet(t['hash'], movie['title']),
              infoHash: t['hash'],
              provider: 'YTS',
              date: t['date_uploaded'],
            );
          });
        }).toList();
      }
    } catch (e) {
      debugPrint('YTS Search Error: $e');
    }
    return [];
  }

  String _buildMagnet(String hash, String title) {
    return 'magnet:?xt=urn:btih:$hash&dn=${Uri.encodeComponent(title)}&tr=udp://open.demonii.com:1337/announce&tr=udp://tracker.openbittorrent.com:80&tr=udp://tracker.coppersurfer.tk:6969&tr=udp://glotorrents.pw:6969/announce&tr=udp://tracker.opentrackr.org:1337/announce&tr=udp://torrent.gresille.org:80/announce&tr=udp://p4p.arenabg.com:1337&tr=udp://tracker.leechers-paradise.org:6969';
  }

  Future<List<TorrentResult>> _search1337x(String query) async {
    try {
      final searchUrl = 'https://1337x.to/search/${Uri.encodeComponent(query)}/1/';
      final response = await _dioClient.dio.get(searchUrl);
      final document = hp.parse(response.data);
      final rows = document.querySelectorAll('table.table-list tbody tr');
      
      List<TorrentResult> results = [];
      for (var row in rows) {
        final cols = row.querySelectorAll('td');
        if (cols.length < 6) continue;
        
        final nameAnchor = cols[0].querySelectorAll('a').last;
        final title = nameAnchor.text;
        final detailPath = nameAnchor.attributes['href'];
        
        final seeds = int.tryParse(cols[1].text) ?? 0;
        final leeches = int.tryParse(cols[2].text) ?? 0;
        final date = cols[3].text;
        final size = '${cols[4].text.split('B')[0]}B'; // Normalize size
        
        // Category is often in the first column icon or a class
        final category = cols[0].querySelector('i')?.attributes['class']?.split('-').last ?? 'Other';

        // 1337x requires a second jump for magnet or parsing the detail page
        // For efficiency, we'll try to get it from the detail page if user clicks, 
        // but for initial search we might just store the detail URL as "magnet placeholder"
        // and fetch it on demand. 
        // OR we can fetch it now in parallel. Let's do a quick fetch for top 5.
        
        results.add(TorrentResult(
          title: title,
          size: size,
          seeds: seeds,
          leeches: leeches,
          category: category,
          magnet: 'https://1337x.to$detailPath', // Temporary store detail URL
          provider: '1337x',
          date: date,
        ));
      }
      return results;
    } catch (e) {
      debugPrint('1337x Search Error: $e');
    }
    return [];
  }

  Future<String?> getMagnetFor1337x(String detailUrl) async {
    try {
      final response = await _dioClient.dio.get(detailUrl);
      final document = hp.parse(response.data);
      final magnetLink = document.querySelector('ul.dropdown-menu li a[href^="magnet"]')?.attributes['href'] 
          ?? document.querySelector('a[href^="magnet"]')?.attributes['href'];
      return magnetLink;
    } catch (e) {
      debugPrint('1337x Magnet Error: $e');
    }
    return null;
  }
}
