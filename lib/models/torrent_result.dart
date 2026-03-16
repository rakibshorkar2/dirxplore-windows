class TorrentResult {
  final String title;
  final String size;
  final int seeds;
  final int leeches;
  final String category;
  final String magnet;
  final String? infoHash;
  final String provider;
  final String? date;

  TorrentResult({
    required this.title,
    required this.size,
    required this.seeds,
    required this.leeches,
    required this.category,
    required this.magnet,
    this.infoHash,
    required this.provider,
    this.date,
  });

  factory TorrentResult.fromJson(Map<String, dynamic> json) {
    return TorrentResult(
      title: json['title'] ?? '',
      size: json['size'] ?? '',
      seeds: json['seeds'] ?? 0,
      leeches: json['leeches'] ?? 0,
      category: json['category'] ?? '',
      magnet: json['magnet'] ?? '',
      infoHash: json['infoHash'],
      provider: json['provider'] ?? '',
      date: json['date'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'size': size,
      'seeds': seeds,
      'leeches': leeches,
      'category': category,
      'magnet': magnet,
      'infoHash': infoHash,
      'provider': provider,
      'date': date,
    };
  }
}
