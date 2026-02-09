import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Web implementation for CSV template download
Future<String?> downloadCsvTemplate(String csvContent) async {
  final bytes = utf8.encode(csvContent);
  final jsArray = bytes.toJS;
  final blob = web.Blob(
    [jsArray].toJS,
    web.BlobPropertyBag(type: 'text/csv'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = 'fundraiser_template.csv';
  anchor.click();
  web.URL.revokeObjectURL(url);
  return null; // Web downloads don't have a file path
}
