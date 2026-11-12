import 'dart:async';

/// Runs [fn] for every item with at most [limit] running at once.
/// Stops starting new items when [cancelled] returns true.
Future<void> forEachLimited<T>(
  Iterable<T> items,
  int limit,
  Future<void> Function(T item) fn, {
  bool Function()? cancelled,
}) async {
  final it = items.iterator;
  Future<void> worker() async {
    while (cancelled?.call() != true && it.moveNext()) {
      await fn(it.current);
    }
  }

  await Future.wait([for (var i = 0; i < limit; i++) worker()]);
}
