// Implémentation web de core/download.dart : crée un Blob et déclenche son
// téléchargement via une ancre temporaire (Task 12).
import 'dart:js_interop';

import 'package:web/web.dart' as web;

void downloadTextFile(String filename, String content) {
  final blob = web.Blob(
    <JSAny>[content.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
