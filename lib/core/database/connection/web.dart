import 'package:drift/drift.dart';
import 'package:drift/web.dart';

/// Creates a database connection for web platform using sql.js with IndexedDB storage
QueryExecutor createDatabaseConnection() {
  return WebDatabase('fundraiser_db');
}
