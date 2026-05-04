import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:{project_name}/app/ledger_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _initLogging();
  runApp(const ProviderScope(child: AppRoot()));
}

void _initLogging() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    debugPrint(
      '${record.time.toIso8601String()} '
      '[${record.level.name}] '
      '${record.loggerName}: ${record.message}',
    );
  });
}
