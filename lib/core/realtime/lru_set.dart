import 'dart:collection';

/// Simple LRU set for idempotency checks
class LruSet<T> {
  final int capacity;
  final _map = LinkedHashMap<T, Object>();

  LruSet({this.capacity = 500});

  /// Returns true if added (new), false if already present
  bool addIfNew(T key) {
    if (_map.containsKey(key)) {
      final val = _map.remove(key);
      _map[key] = val as Object; // refresh position
      return false;
    }
    _map[key] = Object();
    if (_map.length > capacity) {
      _map.remove(_map.keys.first); // evict oldest
    }
    return true;
  }

  bool contains(T key) => _map.containsKey(key);
  void clear() => _map.clear();
}
