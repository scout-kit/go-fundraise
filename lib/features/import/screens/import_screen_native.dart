import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Native implementation for CSV template download
Future<String?> downloadCsvTemplate(String csvContent) async {
  final directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/fundraiser_template.csv');
  await file.writeAsString(csvContent);
  return file.path;
}
