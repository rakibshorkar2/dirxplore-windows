import 'package:html/parser.dart' as parser;
import '../core/network/dio_client.dart';
import '../models/dir_item.dart';

class DirectoryParser {
  final DioClient _dioClient;
  
  DirectoryParser(this._dioClient);

  Future<List<DirItem>> parseUrl(String url) async {
    try {
      final response = await _dioClient.dio.get(url);
      final htmlStr = response.data.toString();
      final document = parser.parse(htmlStr);
      
      final links = document.querySelectorAll('a');
      final List<DirItem> items = [];

      for (var link in links) {
        final href = link.attributes['href'];
        var text = link.text.trim();
        
        if (href == null || href.isEmpty || href.startsWith('?') || href.startsWith('#')) {
          continue;
        }

        // Parent directory
        if (text == '../' || href == '../' || text == 'Parent Directory') {
          items.add(DirItem(
            name: '..',
            url: _resolveUrl(url, href),
            isDirectory: true,
          ));
          continue;
        }
        
        // Skip obvious non-files like some server specific sorts
        if (text.toLowerCase() == 'name' || text.toLowerCase() == 'last modified' || text.toLowerCase() == 'size' || text.toLowerCase() == 'description') {
          continue;
        }

        bool isDir = href.endsWith('/');
        String itemUrl = _resolveUrl(url, href);
        
        items.add(DirItem(
          name: text.isNotEmpty ? text : href,
          url: itemUrl,
          isDirectory: isDir,
        ));
      }
      
      // Basic sorting: directories first
      items.sort((a, b) {
        if (a.name == '..') return -1;
        if (b.name == '..') return 1;
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      
      return items;
    } catch (e) {
      throw Exception("Failed to load directory: $e");
    }
  }

  String _resolveUrl(String base, String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    
    final baseUri = Uri.parse(base);
    
    if (path.startsWith('/')) {
      // Root relative
      return baseUri.replace(path: path).toString();
    }
    
    // Relative to current directory
    String normalizedBase = base;
    if (!normalizedBase.endsWith('/')) {
      normalizedBase = normalizedBase.substring(0, normalizedBase.lastIndexOf('/') + 1);
    }
    
    return normalizedBase + path;
  }
}
