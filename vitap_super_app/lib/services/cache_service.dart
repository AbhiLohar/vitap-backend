class CacheService {
  static final Map<String, _CacheEntry> _cache = {};
  static const Duration defaultTtl = Duration(minutes: 10);

  static T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiry)) {
      _cache.remove(key);
      return null;
    }
    return entry.value as T;
  }

  static void set(String key, dynamic value, {Duration? ttl}) {
    _cache[key] = _CacheEntry(
      value: value,
      expiry: DateTime.now().add(ttl ?? defaultTtl),
    );
  }

  static void remove(String key) {
    _cache.remove(key);
  }

  static void clear() {
    _cache.clear();
  }
}

class _CacheEntry {
  final dynamic value;
  final DateTime expiry;

  _CacheEntry({required this.value, required this.expiry});
}
