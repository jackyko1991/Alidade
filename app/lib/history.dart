/// `HistoryEntry` (platform-independent) plus `HistoryStore`, which persists
/// entries differently depending on platform — see `history_store_io.dart`
/// (native) and `history_store_web.dart` (web) for why they can't share one
/// implementation: `path_provider`, which the native version depends on for
/// a documents directory, has no web platform backend at all.
library;

export 'history_entry.dart';
export 'history_store_io.dart' if (dart.library.js_interop) 'history_store_web.dart';
