import 'dart:typed_data';

/// A simple in-memory page allocator that manages fixed-size byte pages.
///
/// Useful for scenarios where:
///   - You need to allocate many fixed-size byte buffers
///   - You want to keep track of all allocated pages
///   - You need to clear everything at once (e.g. when closing a session)
///
/// Each page is exactly [pageSize] bytes (default: 16 KiB).
///
/// **Not thread-safe** — should be used from a single isolate only.
///
/// Example usage:
/// ```dart
/// final manager = MemoryPageManager();
/// final page1 = manager.allocatePage();
/// final page2 = manager.allocatePage();
/// // ... write data into page1, page2 ...
/// manager.clear();
/// ```
class MemoryPageManager {
  static const int pageSize = 16 * 1024;

  final List<Uint8List> _pages = [];

  /// Allocates and returns a new page of exactly [pageSize] bytes.
  ///
  /// The returned [Uint8List] is zero-initialized.
  /// The page is automatically tracked and will be cleared when [clear()] is called.
  Uint8List allocatePage() {
    final page = Uint8List(pageSize);
    _pages.add(page);
    return page;
  }

  /// Retrieves a previously allocated page by its index (0-based).
  ///
  /// Throws [RangeError] if the index is negative or beyond the current number
  /// of allocated pages.
  Uint8List getPage(int index) {
    if (index < 0 || index >= _pages.length) {
      throw RangeError('Page index out of range');
    }
    return _pages[index];
  }

  int get totalPages => _pages.length;

  /// Removes all allocated pages and clears internal storage.
  ///
  /// After calling this method, [totalPages] will be 0 and all previously
  /// returned page references remain valid but should no longer be used
  /// (their memory is no longer managed by this instance).
  ///
  /// This is typically called when:
  ///   - The session/context is destroyed
  ///   - You're done processing a large file/stream
  ///   - You want to free memory explicitly
  void clear() {
    _pages.clear();
  }
}
