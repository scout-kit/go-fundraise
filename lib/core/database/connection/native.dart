import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Creates a database connection for native platforms (iOS, Android, macOS, etc.)
QueryExecutor createDatabaseConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'fundraiser.db'));
    return NativeDatabase.createInBackground(file);
  });
}
