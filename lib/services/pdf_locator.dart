import 'dart:io';
import 'package:path_provider/path_provider.dart';

class PdfLocator {
  static Future<File?> findPdf(String screeningId) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/$screeningId.pdf");

    if (await file.exists()) {
      return file;
    }
    return null;
  }
}
