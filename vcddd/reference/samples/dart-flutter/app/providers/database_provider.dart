import 'package:flutter_riverpod/flutter_riverpod.dart';

// TODO: Replace with actual AppDatabase import once infrastructure layer is ready
// import 'package:{project_name}/infrastructure/database/app_database.dart';

/// Provides the singleton [AppDatabase] instance.
///
/// Database is a singleton — use [Provider], not [StateProvider].
/// The connection is closed when the provider is disposed.
// final databaseProvider = Provider<AppDatabase>((ref) {
//   final database = AppDatabase();
//   ref.onDispose(() => database.close());
//   return database;
// });

/// Placeholder until AppDatabase is implemented in infrastructure/.
/// Remove this and uncomment the above once ready.
final databaseProvider = Provider<Object>((ref) {
  // TODO: Replace with AppDatabase()
  ref.onDispose(() {
    // TODO: Call database.close()
  });
  return Object();
});
