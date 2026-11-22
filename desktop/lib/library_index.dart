import 'package:nami_hub/catalog.dart';

/// The catalog publishes a new resource map after a successful scan.
class LibraryIndex {
  LibraryIndex(Iterable<Resource> resources) {
    final entries = <({Resource file, String name})>[];
    final names = <String>{};
    var bytes = 0;
    for (final file in resources) {
      final name = file.name.toLowerCase();
      entries.add((file: file, name: name));
      if (!names.add(name)) _duplicates.add(name);
      final type = file.format.$1;
      _counts[type] = (_counts[type] ?? 0) + 1;
      bytes += file.size;
    }
    entries.sort((a, b) {
      final byName = a.name.compareTo(b.name);
      return byName == 0 ? a.file.relative.compareTo(b.file.relative) : byName;
    });
    totalBytes = bytes;
    files = List.unmodifiable(entries.map((e) => e.file));
    _names = [for (final entry in entries) entry.name];
  }

  late final List<Resource> files;
  late final List<String> _names;
  final _counts = <String, int>{};
  final _duplicates = <String>{};
  late final int totalBytes;
  int count(String kind) => _counts[kind] ?? 0;
  bool ambiguousName(Resource file) =>
      _duplicates.contains(file.name.toLowerCase());

  (String, String)? _lastFilter;
  List<Resource> _matches = const [];
  List<Resource> filter(String kind, String search) {
    final query = search.trim().toLowerCase();
    if (kind == 'all' && query.isEmpty) return files;
    final filter = (kind, query);
    if (filter != _lastFilter) {
      _matches = List.unmodifiable([
        for (var i = 0; i < files.length; i++)
          if ((kind == 'all' || files[i].format.$1 == kind) &&
              _names[i].contains(query))
            files[i],
      ]);
      _lastFilter = filter;
    }
    return _matches;
  }
}
