import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/form_b.dart';
import '../models/form_c.dart';
import '../models/crf.dart';

class PdfService {

  static Future<File> generateFullTrialPdf({
    required CRF crf,
    FormB? formB,
    FormC? formC,
  }) async {

    final pdf = pw.Document();
    final formattedNow =
        DateFormat("dd/MM/yyyy  HH:mm").format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),

        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            "Page ${context.pageNumber} of ${context.pagesCount}",
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),

        build: (context) => [

          // ================= HEADER =================
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [

              pw.Text(
                "PORTAL TRIAL",
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 6),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    "Site: ${crf.site}",
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                  pw.Text(
                    "Generated: $formattedNow",
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ],
              ),

              pw.SizedBox(height: 10),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 10),
            ],
          ),

          // ================= FORM A =================
          _section("FORM A – SCREENING", [

            _row("Screening ID", crf.screeningId),
            _row("Site", crf.site),
            _row("Site ID", crf.siteId),
            _row("Screening Date & Time", crf.screeningDateTime),
            _row("Screened By", crf.screenedBy),

            _divider(),

            _row("Mother Name",
                "${crf.motherFirstName ?? ""} ${crf.motherSurname ?? ""}"),
            _row("Husband Name",
                "${crf.husbandFirstName ?? ""} ${crf.husbandSurname ?? ""}"),
            _row("Mother Phone", crf.motherPhone),
            _row("Husband Phone", crf.husbandPhone),
            _row("Maternal UID", crf.maternalUid),
            _row("Hospital Admission No", crf.hospitalNo),

            _divider(),

            _row("Gestation",
                "${crf.gestationWeeks ?? 0} + ${crf.gestationDays ?? 0} days"),
            _row("GA Method", crf.gestationMethod),
            _row("Expected Delivery Date", crf.expectedDeliveryDate),
            _row("GA Known in Weeks",
                crf.gestationKnownInWeeks == true ? "Yes" : "No"),
            _row("EDD Known",
                crf.eddKnown == true ? "Yes" : "No"),

            _divider(),

            _row("Exclusion Present",
                crf.exclusion == true ? "Yes" : "No"),
            _row("Exclusion Reason(s)", crf.exclusionReason),
            _row("Anomaly Details", crf.anomalyDetails),
            _row("Final Eligibility", crf.eligibilityStatus),

            _divider(),

            _row("Consent Status", crf.consentStatus),
            _row("Consent Refusal Reason", crf.consentRefusalReason),
            _row("Relationship to Participant",
                crf.relationshipToParticipant),
            _row("Relationship (Other)", crf.relationshipOther),
            _row("Consent Taken By", crf.consentTakenBy),
          ]),

          // ================= FORM B =================
          if (formB != null)
            _section("FORM B – BIRTH DETAILS", [

              _row("Baby UID", formB.babyUid),
              _row("Birth Weight", formB.birthWeight),
              _row("Date of Birth", formB.dateOfBirth),
              _row("Time of Birth", formB.timeOfBirth),

              _divider(),

              _row("Indication", formB.indication),
              _row("Delivery Mode", formB.delivery),
              _row("Labor Type", formB.labor),
              _row("Gender", formB.gender),

              _divider(),

              _row("Required Resuscitation",
                  formB.requiredResuscitation ? "Yes" : "No"),
              _row("Randomized",
                  formB.randomized ? "Yes" : "No"),
              _row("Enrollment ID", formB.enrollmentId),
            ]),

          // ================= FORM C =================
          if (formC != null)
            _section("FORM C – RESUSCITATION DETAILS", [

              _row("Ventilation",
                  formC.ventilation ? "Yes" : "No"),
              _row("Device", formC.device),
              _row("SIB PEEP",
                  formC.sibPeep ? "Yes" : "No"),
              _row("Interface", formC.interface),
              _row("Ventilation Duration",
                  formC.ventilationDuration),

              _divider(),

              _row("Intubation",
                  formC.intubation ? "Yes" : "No"),
              _row("Chest Compression",
                  formC.chestCompression ? "Yes" : "No"),
              _row("Chest Compression Duration",
                  formC.chestCompressionDuration),

              _divider(),

              _row("Epinephrine",
                  formC.epinephrine ? "Yes" : "No"),
              _row("Epinephrine Doses",
                  formC.epinephrineDoses),
              _row("Fluid Bolus",
                  formC.fluidBolus ? "Yes" : "No"),

              _divider(),

              _row("Placental Transfusion",
                  formC.placentalTransfusion ? "Yes" : "No"),
              _row("Placental Method",
                  formC.placentalMethod),

              _divider(),

              _row("Cord Clamp Time", formC.cordClampTime),
              _row("Time to Respiration",
                  formC.timeToRespiration),
              _row("SpO2 at 5 min",
                  formC.spo2At5Min),
              _row("FiO2 at Exit",
                  formC.fio2Exit),
              _row("SpO2 at Exit",
                  formC.spo2Exit),

              _divider(),

              _row("pH", formC.ph),
              _row("Base Excess", formC.be),
              _row("pCO2", formC.pco2),

              _divider(),

              _row("Cord Blood Done",
                  formC.cordBloodDone ? "Yes" : "No"),
              _row("Resuscitation Failure",
                  formC.resusFailure ? "Yes" : "No"),
              _row("Exit Reason",
                  formC.exitReason),

              _divider(),

              pw.SizedBox(height: 10),
              pw.Text(
                "INTERVENTION TIMELINE (1–20 min)",
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),

              _buildTimelineTable(formC),
            ]),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file =
        File("${dir.path}/${crf.screeningId}_FULL.pdf");

    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static Future<File> generateCrfPdf(CRF crf) async {
    return await generateFullTrialPdf(crf: crf);
  }

  // ================= TIMELINE TABLE =================
  static pw.Widget _buildTimelineTable(FormC formC) {
    final minutes = [1, 5, 10, 15, 20];

    final headers = [
      "Intervention",
      ...minutes.map((m) => "$m min"),
    ];

    final rows = <List<String>>[];

    formC.timelineChecks.forEach((intervention, minuteMap) {
      final row = <String>[intervention];

      for (final m in minutes) {
        row.add((minuteMap[m] ?? false) ? "✔" : "-");
      }

      rows.add(row);
    });

    final apgarRow = <String>["Apgar"];
    for (final m in minutes) {
      apgarRow.add(formC.apgarScores[m] ?? "-");
    }
    rows.add(apgarRow);

    return pw.Table.fromTextArray(
      headers: headers,
      data: rows,
      border: pw.TableBorder.all(width: 0.5),
      headerStyle:
          pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration:
          const pw.BoxDecoration(color: PdfColors.grey300),
      cellAlignment: pw.Alignment.center,
      cellPadding: const pw.EdgeInsets.all(4),
    );
  }

  // ================= UI HELPERS =================

  static pw.Widget _section(
      String title, List<pw.Widget> children) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Column(
        crossAxisAlignment:
            pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  static pw.Widget _divider() {
    return pw.Padding(
      padding:
          const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Divider(),
    );
  }

  static pw.Widget _row(
      String label, String? value) {
    return pw.Padding(
      padding:
          const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment:
            pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 190,
            child: pw.Text(
              "$label:",
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              (value == null ||
                      value.trim().isEmpty)
                  ? "-"
                  : value,
            ),
          ),
        ],
      ),
    );
  }
}
