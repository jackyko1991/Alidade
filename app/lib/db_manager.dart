/// Downloads, caches, and cleans up per-lens solver databases. Exactly one
/// of the two platform implementations is used depending on platform — see
/// `db_manager_io.dart` (native) and `db_manager_web.dart` (web) for why
/// they can't share one implementation: `path_provider`, which the native
/// version depends on for a cache directory, has no web platform backend
/// at all.
library;

export 'db_manager_io.dart' if (dart.library.js_interop) 'db_manager_web.dart';
