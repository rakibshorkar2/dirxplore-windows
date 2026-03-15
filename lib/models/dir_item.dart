class DirItem {
  final String name;
  final String url;
  final bool isDirectory;
  final String size;
  final String date;

  DirItem({
    required this.name,
    required this.url,
    this.isDirectory = false,
    this.size = '',
    this.date = '',
  });
}
