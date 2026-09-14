// One-off: builds placeholder PDFs in assets/documents/ (replace with full PIS on server).
import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<void> main() async {
  final dir = Directory('assets/documents');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  for (final lang in ['English', 'Hindi']) {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.all(48),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'PORTAL Trial — PIS / ICF ($lang)',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                'Deploy the full participant information sheet PDF as '
                'PIS_ICF_$lang.pdf on the web app (public/documents/) '
                'and in assets/documents/ for offline use.',
                style: const pw.TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
    final path = 'assets/documents/PIS_ICF_$lang.pdf';
    await File(path).writeAsBytes(await doc.save());
    // ignore: avoid_print
    print('Wrote $path');
  }
}
