import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/birth_resuscitation.dart';
import '../models/crf.dart';
import '../models/form_b.dart';
import '../models/form_c.dart';

/// Patient PDF export aligned with web PrintSummary / PrintSummaryB.
/// Includes only forms that have been filled:
///   Form A only → Form A
///   Form A + B → Form A + Form B1
///   Form A + B + C → all three
class PdfService {
  static Future<File> generateFullTrialPdf({
    required CRF crf,
    FormB? formB,
    FormC? formC,
    BirthResuscitationData? birth,
    bool includeFormA = true,
  }) async {
    final hasB = formB != null || _birthHasIdentification(birth);
    final hasC = formC != null || _birthHasResuscitation(birth);

    final pdf = pw.Document();
    final todayLong = DateFormat('dd MMMM yyyy').format(DateTime.now());
    final todayShort = DateFormat('dd MMM yyyy').format(DateTime.now());

    final pages = <pw.Widget>[];

    if (includeFormA) {
      pages.addAll(_buildFormA(crf, todayLong, todayShort));
    }
    if (hasB) {
      if (pages.isNotEmpty) pages.add(pw.NewPage());
      pages.addAll(_buildFormB(
        crf: crf,
        formB: formB,
        birth: birth,
        todayLong: todayLong,
        todayShort: todayShort,
      ));
    }
    if (hasC) {
      if (pages.isNotEmpty) pages.add(pw.NewPage());
      pages.addAll(_buildFormC(
        crf: crf,
        formB: formB,
        formC: formC,
        birth: birth,
        todayLong: todayLong,
        todayShort: todayShort,
      ));
    }

    if (pages.isEmpty) {
      pages.add(pw.Center(
        child: pw.Text('No form data available to export.',
            style: const pw.TextStyle(fontSize: 12)),
      ));
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 28),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (_) => pages,
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final suffix = [
      if (includeFormA) 'A',
      if (hasB) 'B1',
      if (hasC) 'B2',
    ].join('');
    final file = File(
        '${dir.path}/${crf.screeningId}_Form$suffix.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Form A only (e.g. immediately after screening save).
  static Future<File> generateCrfPdf(CRF crf) async {
    return generateFullTrialPdf(crf: crf, includeFormA: true);
  }

  // ── Presence helpers ──────────────────────────────────────────────────────

  static bool _birthHasIdentification(BirthResuscitationData? d) {
    if (d == null) return false;
    return (d.babyUid ?? '').trim().isNotEmpty ||
        d.dateOfBirth != null ||
        d.birthWeight != null ||
        (d.enrollmentId ?? '').trim().isNotEmpty;
  }

  static bool _birthHasResuscitation(BirthResuscitationData? d) {
    if (d == null) return false;
    return (d.devicePpv ?? '').trim().isNotEmpty ||
        d.intubation != null ||
        d.chestCompression != null ||
        d.adrenaline != null ||
        d.cordBloodDone != null ||
        d.resusFailure != null ||
        (d.interfaceUsed ?? '').trim().isNotEmpty;
  }

  // ── FORM A (PrintSummary.jsx) ─────────────────────────────────────────────

  static List<pw.Widget> _buildFormA(
      CRF crf, String todayLong, String todayShort) {
    final outcome = _formAOutcome(crf);
    final gaStr =
        '${crf.gestationWeeks} weeks ${crf.gestationDays} days';
    final gaDays = crf.gestationWeeks * 7 + crf.gestationDays;
    final gaElig = (crf.gestationWeeks <= 0 && crf.gestationDays <= 0)
        ? 'Not calculated'
        : (gaDays >= 25 * 7 && gaDays <= 31 * 7 + 6
            ? 'Within range (25w 0d – 31w 6d)'
            : 'Outside range (25w 0d – 31w 6d)');

    final methodLabels = {
      'LMP': 'LMP (Last Menstrual Period)',
      'Early USG': 'Early USG (<24w)',
      'Fundal Height': 'Fundal height',
      'Unknown': 'Method not known',
    };

    final yesKeys = crf.exclusionReason
        .split(RegExp(r'[;,]'))
        .map((e) => e.trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toSet();

    String excYn(String key) {
      if (yesKeys.contains(key)) return 'Yes';
      if (crf.exclusionReason.trim().isEmpty && !crf.exclusion) return 'No';
      if (crf.exclusion && yesKeys.isEmpty) return '—';
      return yesKeys.isEmpty ? 'No' : (yesKeys.contains(key) ? 'Yes' : 'No');
    }

    return [
      _studyHeader(
        docLabel: 'Screening Summary — Form A',
        meta: [
          ['Screening ID',
            crf.screeningId.isEmpty ? 'Not assigned' : crf.screeningId],
          ['Site', crf.site],
          ['Print Date', todayLong],
        ],
      ),
      _rule(),
      _outcomeBanner('Screening Outcome', outcome),
      pw.SizedBox(height: 10),

      _sectionHd('Maternal Information'),
      _kvTable([
        ['Mother\'s Name',
          '${crf.motherFirstName} ${crf.motherSurname}'.trim()],
        ['Husband\'s Name',
          '${crf.husbandFirstName} ${crf.husbandSurname}'.trim()],
        ['Maternal UID (CR No.)', crf.maternalUid],
        ['Hospital Admission No.', crf.hospitalNo],
        ['Mother Contact', crf.motherPhone],
        ['Husband Contact', crf.husbandPhone],
      ]),

      _sectionHd('Screening Information'),
      _kvTable([
        ['Site', crf.site],
        ['Site ID', crf.siteId],
        ['Screened By', crf.screenedBy],
        ['Screening Date & Time', crf.screeningDateTime],
      ]),

      _sectionHd('Consent Information'),
      _kvTable([
        ['Consent Status', crf.consentStatus],
        ['Consent Taken By', crf.consentTakenBy],
        ['Relationship', crf.relationshipToParticipant == 'Other'
            ? 'Other — ${crf.relationshipOther}'
            : crf.relationshipToParticipant],
        if (crf.consentStatus == 'No')
          ['Refusal Reason', crf.consentRefusalReason],
        if (crf.consentStatus == 'Not approached')
          ['Not Approached Reason', crf.consentRefusalReason],
      ]),

      _sectionHd('Gestation Assessment'),
      _kvTable([
        ['Gestation Known', crf.gestationKnownInWeeks ? 'Yes' : 'No'],
        ['Best Estimate GA', gaStr],
        ['EDD', crf.expectedDeliveryDate],
        if (crf.gestationKnownInWeeks)
          ['Assessment Method',
            methodLabels[crf.gestationMethod] ?? crf.gestationMethod],
        ['GA Eligibility', gaElig],
        ['Final Eligibility', crf.eligibilityStatus],
      ]),

      _sectionHd('Exclusion Criteria'),
      _ynTable([
        ['Major Structural Anomaly / Genetic', excYn('ANOMALY')],
        if (excYn('ANOMALY') == 'Yes' && crf.anomalyDetails.trim().isNotEmpty)
          ['↳ Anomaly details', crf.anomalyDetails],
        ['Fetal Hydrops', excYn('HYDROPS')],
        ['Decision to Forego Resuscitation', excYn('RESUSCITATION')],
        ['Insufficient Time for Consent', excYn('INSUFFICIENT')],
        ['Intrauterine Fetal Death (IUFD)', excYn('IUFD')],
      ]),

      _signatureArea(),
      _formFooter(
        'PORTAL Trial · Form A · Version 1.0',
        'ID: ${crf.screeningId.isEmpty ? "—" : crf.screeningId} · Printed: $todayShort',
      ),
    ];
  }

  static String _formAOutcome(CRF crf) {
    final gaDays = crf.gestationWeeks * 7 + crf.gestationDays;
    if (!crf.gestationKnownInWeeks && !crf.eddKnown) {
      return 'SCREEN FAILURE';
    }
    if (crf.gestationWeeks <= 0 && crf.gestationDays <= 0) return 'PENDING';
    if (gaDays < 25 * 7 || gaDays > 31 * 7 + 6) return 'NOT ELIGIBLE';
    if (crf.exclusion) return 'SCREEN FAILURE';
    final consent = crf.consentStatus.trim();
    if (consent == 'No' || consent == 'Not approached') {
      return 'CONSENT REFUSED';
    }
    if (consent == 'Yes') return 'ELIGIBLE';
    if (crf.eligibilityStatus.toLowerCase().contains('eligible') &&
        !crf.eligibilityStatus.toLowerCase().contains('not')) {
      return 'ELIGIBLE';
    }
    if (crf.eligibilityStatus.toLowerCase().contains('not')) {
      return 'NOT ELIGIBLE';
    }
    return 'PENDING';
  }

  // ── Form B1 (PrintSummaryB B1–B3 + Randomisation) ──────────────────────────

  static List<pw.Widget> _buildFormB({
    required CRF crf,
    FormB? formB,
    BirthResuscitationData? birth,
    required String todayLong,
    required String todayShort,
  }) {
    final eid = _firstNonEmpty([
      formB?.enrollmentId,
      birth?.enrollmentId,
      crf.enrollmentId,
    ]);
    final babyUid = _firstNonEmpty([formB?.babyUid, birth?.babyUid]);
    final admission =
        _firstNonEmpty([formB?.babyAdmissionNo, birth?.babyAdmissionNo]);
    final annual =
        _firstNonEmpty([formB?.babyAnnualNo, birth?.babyAnnualNo]);
    final dob = _firstNonEmpty([
      formB?.dateOfBirth,
      birth?.dateOfBirth != null
          ? DateFormat('dd MMM yyyy').format(birth!.dateOfBirth!)
          : null,
    ]);
    final tob = _firstNonEmpty([formB?.timeOfBirth, birth?.timeOfBirth]);
    final bw = _firstNonEmpty([
      formB?.birthWeight,
      birth?.birthWeight?.toString(),
    ]);
    final centile = _firstNonEmpty([
      formB?.intrauterineCentile,
      birth?.intrauterineCentile,
    ]);
    final gender = _firstNonEmpty([formB?.gender, birth?.gender]);

    String? deliveryDetail;
    if (birth?.deliveryMode != null && birth!.deliveryMode!.isNotEmpty) {
      if (birth.deliveryMode == 'Vaginal') {
        deliveryDetail = birth.vaginalDeliveryType != null &&
                birth.vaginalDeliveryType!.isNotEmpty
            ? 'Vaginal — ${birth.vaginalDeliveryType}'
            : 'Vaginal';
      } else if (birth.deliveryMode == 'LSCS') {
        deliveryDetail =
            birth.lscsType != null && birth.lscsType!.isNotEmpty
                ? 'LSCS — ${birth.lscsType}'
                : 'LSCS';
      } else {
        deliveryDetail = birth.deliveryMode;
      }
    } else if (formB != null && formB.delivery.isNotEmpty) {
      deliveryDetail = formB.labor.isNotEmpty
          ? '${formB.delivery} — ${formB.labor}'
          : formB.delivery;
    }

    final indications = _firstNonEmpty([
      formB?.indication,
      birth != null && birth.indicationForDelivery.isNotEmpty
          ? birth.indicationForDelivery.join(', ')
          : null,
    ]);
    final indicationOther = _firstNonEmpty([
      formB?.indicationOther,
      birth?.indicationForDeliveryOther,
    ]);

    final poorResp = _ynBool(
        formB?.poorRespiratoryEffort ?? birth?.poorRespEfforts);
    final poorTone =
        _ynBool(formB?.poorMuscleTone ?? birth?.poorMuscleTone);
    final hr = _ynBool(formB?.hrAbove100 ?? birth?.hrAbove100);
    // Web label is "HR < 100"; mobile stores hrAbove100 (true = HR ≥ 100).
    // PrintSummaryB uses hr_below_100 — invert when we only have hrAbove100.
    final hrBelow = () {
      final v = formB?.hrAbove100 ?? birth?.hrAbove100;
      if (v == null) return '—';
      return v ? 'No' : 'Yes'; // above 100 → not below 100
    }();
    final initial =
        _ynBool(formB?.initialStepsRequired ?? birth?.initialSteps);
    final reqResus = _ynBool(
        formB?.requiredResuscitation ?? birth?.requiredResuscitation);
    final randomised =
        _ynBool(formB?.randomized ?? birth?.randomised);

    final randDate = _firstNonEmpty([
      formB?.randomizationDate,
      birth?.randomisationDate != null
          ? _fmtIsoDate(birth!.randomisationDate!)
          : null,
    ]);
    final strata = birth?.strata ?? '';
    final notRandReason = _firstNonEmpty([
      formB?.notRandomizedReason,
      birth?.enrollmentReasonNotRandomized,
    ]);
    final notRandOther = _firstNonEmpty([
      formB?.notRandomizedOther,
      birth?.enrollmentReasonNotRandomizedOther,
    ]);

    final gaScreen =
        '${crf.gestationWeeks}w ${crf.gestationDays}d';
    final gaRand = birth?.gestationRandWeeks != null
        ? '${birth!.gestationRandWeeks}w ${birth.gestationRandDays ?? 0}d'
        : gaScreen;

    final outcome = () {
      if (reqResus == 'No') return 'NO PPV — FORMS A–B2 ONLY';
      if (randomised == 'Yes') return 'RANDOMISED';
      if (randomised == 'No') return 'NOT RANDOMISED';
      if (reqResus == 'Yes') return 'PPV REQUIRED';
      return 'IN PROGRESS';
    }();

    return [
      _studyHeader(
        docLabel: 'Birth & Resuscitation — Form B1',
        meta: [
          ['Enrollment ID', eid.isEmpty ? 'Not assigned' : eid],
          ['Screening ID', crf.screeningId],
          ['Print Date', todayLong],
        ],
      ),
      _rule(),
      _outcomeBanner('Form B1 Status', outcome),
      pw.SizedBox(height: 10),

      _sectionHd('B1 · Identification'),
      _kvTable([
        ['Screening ID', crf.screeningId],
        ['Enrollment ID', eid],
        ['Mother\'s Name',
          '${crf.motherFirstName} ${crf.motherSurname}'.trim()],
        ['Maternal UID', crf.maternalUid],
        ['Baby UID', babyUid],
        ['Baby Admission No.', admission],
        ['Baby Annual No.', annual],
      ]),

      _sectionHd('B2 · Birth Details'),
      _kvTable([
        ['Date of Birth', dob],
        ['Time of Birth', tob],
        ['GA at Screening', gaScreen],
        ['GA at Randomisation', gaRand],
        ['Birth Weight (g)', bw],
        ['Intrauterine Centile', centile],
        ['Gender', gender],
        ['Delivery Mode', deliveryDetail ?? ''],
        ['Indication for Delivery', indications],
        if (indicationOther.isNotEmpty)
          ['Indication — Other', indicationOther],
      ]),

      _sectionHd('B3 · Initial Assessment'),
      _ynTable([
        ['Poor Respiratory Effort', poorResp],
        ['Poor Muscle Tone', poorTone],
        ['HR < 100', hrBelow == '—' ? hr : hrBelow],
        ['Initial Steps Done', initial],
        ['Requires Ventilation (PPV)', reqResus],
      ]),

      _sectionHd('Randomisation'),
      _kvTable([
        ['Randomised', randomised],
        ['Randomisation Date', randDate],
        ['Strata', strata],
        if (randomised == 'No')
          ['Reason Not Randomised', notRandReason],
        if (notRandOther.isNotEmpty) ['Reason — Other', notRandOther],
      ]),

      _signatureArea(),
      _formFooter(
        'PORTAL Trial · Form B1 · CRF v1.25',
        'ID: ${eid.isEmpty ? crf.screeningId : eid} · Printed: $todayShort',
      ),
    ];
  }

  // ── Form B2 (PrintSummaryB B4 + B6; mobile Form B2) ─────────────────────────

  static List<pw.Widget> _buildFormC({
    required CRF crf,
    FormB? formB,
    FormC? formC,
    BirthResuscitationData? birth,
    required String todayLong,
    required String todayShort,
  }) {
    final eid = _firstNonEmpty([
      formB?.enrollmentId,
      birth?.enrollmentId,
      crf.enrollmentId,
    ]);

    final device = _firstNonEmpty([formC?.device, birth?.devicePpv]);
    final interface =
        _firstNonEmpty([formC?.interface, birth?.interfaceUsed]);
    final ppvDur = _firstNonEmpty([
      formC?.ventilationDuration,
      birth?.ppvDuration?.toString(),
    ]);
    final sibPeepWith = _firstNonEmpty([
      formC?.sibPeepWith,
      birth?.sibPeepWith,
      formC?.sibPeep == true
          ? 'Yes'
          : (formC?.sibPeep == false ? 'No' : null),
    ]);
    final sibVal = _firstNonEmpty([
      formC?.sibPeepCmh2o,
      birth?.sibPeepCmh2o?.toString(),
    ]);
    final tPip = _firstNonEmpty(
        [formC?.tpiecePip, birth?.tpiecePip?.toString()]);
    final tPeep = _firstNonEmpty(
        [formC?.tpiecePeep, birth?.tpiecePeep?.toString()]);
    final tFlow = _firstNonEmpty(
        [formC?.tpieceFlow, birth?.tpieceFlow?.toString()]);
    final intubation =
        _ynBool(formC?.intubation ?? birth?.intubation);
    final cc = _ynBool(formC?.chestCompression ?? birth?.chestCompression);
    final ccDur = _firstNonEmpty([
      formC?.chestCompressionDuration,
      birth?.ccDuration?.toString(),
    ]);
    final epi = _ynBool(formC?.epinephrine ?? birth?.adrenaline);
    final epiDil = _firstNonEmpty(
        [formC?.adrenalineDilution, birth?.adrenalineDilution]);
    final epiRoute =
        _firstNonEmpty([formC?.adrenalineRoute, birth?.adrenalineRoute]);
    final fluid = _ynBool(formC?.fluidBolus ?? birth?.fluidBolus);
    final fluidDoses = _firstNonEmpty([
      formC?.fluidBolusDoses,
      birth?.fluidBolusDoses?.toString(),
    ]);
    final fluidCum = _firstNonEmpty([
      formC?.fluidBolusCumulative,
      birth?.fluidBolusCumulative?.toString(),
    ]);
    final placental = _ynBool(
        formC?.placentalTransfusion ?? birth?.placentalTransfusion);
    final placentalMethod = _firstNonEmpty(
        [formC?.placentalMethod, birth?.transfusionMethod]);
    final cordClamp = _firstNonEmpty([
      formC?.cordClampedAt,
      birth?.cordClampTimestamp,
      formC?.cordClampTime,
      birth?.cordClampTime?.toString(),
    ]);
    final timeResp = _firstNonEmpty([
      formC?.timeToRespiration,
      birth?.timeToRespiration != null
          ? _secsToHms(birth!.timeToRespiration!)
          : null,
    ]);
    final spo25 = _firstNonEmpty([
      formC?.spo2At5Min,
      birth?.spo25min?.toString(),
    ]);
    final timeSpo2 = _firstNonEmpty([
      formC?.timeToSpo2Above80,
      birth?.timeToSpo280 != null
          ? _secsToHms(birth!.timeToSpo280!)
          : null,
    ]);

    final cordDone =
        _ynBool(formC?.cordBloodDone ?? birth?.cordBloodDone);
    final cord1hr =
        _ynBool(formC?.cordBloodWithin1hr ?? birth?.cordBloodWithin1hr);
    final cordSrc =
        _firstNonEmpty([formC?.cordBloodSource, birth?.cordBloodSource]);
    final ph = _firstNonEmpty([formC?.ph, birth?.cordPh?.toString()]);
    final sbe = _firstNonEmpty([formC?.be, birth?.cordSbe?.toString()]);
    final pco2 =
        _firstNonEmpty([formC?.pco2, birth?.cordPco2?.toString()]);
    final resusFail =
        _ynBool(formC?.resusFailure ?? birth?.resusFailure);
    final spo2Exit = _firstNonEmpty([
      formC?.spo2Exit,
      birth?.spo2ExitTrialGas?.toString(),
    ]);
    final totalTime = _firstNonEmpty([
      formC?.totalTime,
      birth?.totalResusTime?.toString(),
    ]);
    final exitReason = _firstNonEmpty([
      formC?.exitReason,
      birth?.reasonExitTrialGas,
    ]);
    final exitOther = birth?.reasonExitTrialGasOther ?? '';
    final blender =
        _ynBool(formC?.blenderStopped ?? birth?.blenderStopped);
    final blenderReasons = _firstNonEmpty([
      (formC?.blenderInterruptReasons ?? const []).join(', '),
      (birth?.blenderInterruptReasons ?? const []).join(', '),
    ]);
    final blenderDesc = _firstNonEmpty([
      formC?.blenderStoppedDescription,
      birth?.blenderStoppedDescription,
    ]);
    final blenderUnit = _firstNonEmpty([
      formC?.blenderLetter,
      birth?.blenderLetter,
    ]);

    return [
      _studyHeader(
        docLabel: 'Resuscitation Details — Form B2',
        meta: [
          ['Enrollment ID', eid.isEmpty ? 'Not assigned' : eid],
          ['Screening ID', crf.screeningId],
          ['Print Date', todayLong],
        ],
      ),
      _rule(),
      pw.SizedBox(height: 8),

      _sectionHd('B4 · Resuscitation'),
      _kvTable([
        ['PPV Device', device],
        ['Interface Used', interface],
        ['PPV Duration', ppvDur],
        ['SIB with PEEP', sibPeepWith],
        if (sibPeepWith == 'Yes') ['SIB PEEP (cmH₂O)', sibVal],
        ['T-piece PIP', tPip],
        ['T-piece PEEP', tPeep],
        ['T-piece Flow', tFlow],
        ['Endotracheal Intubation', intubation],
        ['Chest Compressions', cc],
        if (cc == 'Yes') ['CC Duration', ccDur],
        ['Epinephrine', epi],
        if (epi == 'Yes') ...[
          ['Epinephrine Dilution', epiDil],
          ['Epinephrine Route', epiRoute],
        ],
        ['Fluid Bolus', fluid],
        if (fluid == 'Yes') ...[
          ['Fluid Bolus Doses', fluidDoses],
          ['Cumulative Fluid Bolus', fluidCum],
        ],
        ['Placental Transfusion', placental],
        ['Transfusion Method', placentalMethod],
        ['Cord Clamp Time', cordClamp],
        ['Time to Respiration', timeResp],
        ['SpO₂ at 5 min', spo25],
        ['Time to SpO₂ 80%', timeSpo2],
      ]),

      if (formC != null &&
          (formC.timelineChecks.isNotEmpty ||
              formC.apgarScores.values.any((v) => v.trim().isNotEmpty))) ...[
        _sectionHd('B5 · Minute-wise Intervention Summary'),
        pw.SizedBox(height: 4),
        _buildTimelineTable(formC),
        pw.SizedBox(height: 8),
      ],

      _sectionHd('B6 · Cord Blood & Exit'),
      _kvTable([
        ['Cord Blood Done', cordDone],
        ['Within 1 Hour', cord1hr],
        ['Cord Blood Source', cordSrc],
        ['Cord pH', ph],
        ['Cord SBE', sbe],
        ['Cord PCO₂', pco2],
        ['Resuscitation Failure', resusFail],
        ['SpO₂ Exit Trial Gas', spo2Exit],
        ['Total Resus Time', totalTime],
        ['Reason Exit Trial Gas', exitReason],
        if (exitOther.trim().isNotEmpty)
          ['Exit Reason — Other', exitOther],
        ['Blender interrupted before 30 min', blender],
        if (blenderReasons.isNotEmpty)
          ['Interrupt reason', blenderReasons],
        if (blenderDesc.isNotEmpty)
          ['Blender stopped abruptly — Detail', blenderDesc],
        ['Blender Unit ID', blenderUnit],
      ]),

      _signatureArea(),
      _formFooter(
        'PORTAL Trial · Form B2 · CRF v1.25',
        'ID: ${eid.isEmpty ? crf.screeningId : eid} · Printed: $todayShort',
      ),
    ];
  }

  // ── Shared layout widgets (PrintSummary.css parity) ───────────────────────

  static pw.Widget _studyHeader({
    required String docLabel,
    required List<List<String>> meta,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 3,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('PORTAL Trial',
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Text(
                'Providing initial Oxygen for delivery Room resuscitATion of\n'
                'preteRm infants using targeted Low oxygen versus air',
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey700, lineSpacing: 1.2),
              ),
              pw.SizedBox(height: 3),
              pw.Text('ICMR Funded · Multi-site RCT · PGIMER Chandigarh',
                  style: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey600)),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(docLabel,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Table(
                columnWidths: {
                  0: const pw.IntrinsicColumnWidth(),
                  1: const pw.FlexColumnWidth(),
                },
                children: meta
                    .map((r) => pw.TableRow(children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(
                                right: 8, bottom: 2),
                            child: pw.Text(r[0],
                                style: const pw.TextStyle(
                                    fontSize: 8,
                                    color: PdfColors.grey600)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 2),
                            child: pw.Text(r[1].isEmpty ? '—' : r[1],
                                textAlign: pw.TextAlign.right,
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold)),
                          ),
                        ]))
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _rule() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 8),
        child: pw.Container(height: 1.2, color: PdfColors.grey800),
      );

  static pw.Widget _outcomeBanner(String label, String value) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        border: pw.Border.all(color: PdfColors.grey700, width: 0.8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey700)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _sectionHd(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
      child: pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        color: PdfColors.grey300,
        child: pw.Text(title,
            style: pw.TextStyle(
                fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ),
    );
  }

  static pw.Widget _kvTable(List<List<String>> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.35),
        1: pw.FlexColumnWidth(2),
      },
      children: rows.map((r) {
        final val = r.length > 1 ? r[1].trim() : '';
        return pw.TableRow(children: [
          pw.Container(
            color: PdfColors.grey100,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: pw.Text(r[0],
                style: const pw.TextStyle(fontSize: 8.5)),
          ),
          pw.Padding(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: pw.Text(val.isEmpty ? '—' : val,
                style: const pw.TextStyle(fontSize: 8.5)),
          ),
        ]);
      }).toList(),
    );
  }

  static pw.Widget _ynTable(List<List<String>> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('Criterion / Finding',
                  style: pw.TextStyle(
                      fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('Yes / No',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
        ...rows.map((r) {
          final yn = r.length > 1 ? r[1] : '—';
          final display = yn == 'Yes'
              ? 'YES'
              : yn == 'No'
                  ? 'NO'
                  : (yn.startsWith('↳') ? yn : (yn.isEmpty ? '—' : yn));
          return pw.TableRow(children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6, vertical: 3),
              child: pw.Text(r[0],
                  style: const pw.TextStyle(fontSize: 8.5)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 4, vertical: 3),
              child: pw.Text(display,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: yn == 'Yes' || yn == 'No'
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                  )),
            ),
          ]);
        }),
      ],
    );
  }

  static pw.Widget _signatureArea() {
    pw.Widget block(String cap) => pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 22),
              pw.Container(height: 0.8, color: PdfColors.grey800),
              pw.SizedBox(height: 3),
              pw.Text(cap,
                  style: const pw.TextStyle(
                      fontSize: 7.5, color: PdfColors.grey700)),
            ],
          ),
        );
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 18),
      child: pw.Row(children: [
        block('Prepared By — Name & Signature'),
        pw.SizedBox(width: 16),
        block('Date'),
        pw.SizedBox(width: 16),
        block('Investigator / Delegate — Signature'),
      ]),
    );
  }

  static pw.Widget _formFooter(String left, String right) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14),
      child: pw.Column(children: [
        pw.Container(height: 0.6, color: PdfColors.grey500),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(left,
                style: const pw.TextStyle(
                    fontSize: 7, color: PdfColors.grey700)),
            pw.Text('CONFIDENTIAL — Authorised study personnel only',
                style: const pw.TextStyle(
                    fontSize: 7, color: PdfColors.grey700)),
            pw.Text(right,
                style: const pw.TextStyle(
                    fontSize: 7, color: PdfColors.grey700)),
          ],
        ),
      ]),
    );
  }

  static pw.Widget _buildTimelineTable(FormC formC) {
    final minutes = [1, 5, 10, 15, 20];
    final headers = ['Intervention', ...minutes.map((m) => '$m min')];
    final rows = <List<String>>[];

    formC.timelineChecks.forEach((intervention, minuteMap) {
      final row = <String>[intervention];
      for (final m in minutes) {
        final v = (minuteMap[m] ?? '').trim();
        if (v == 'Y' || v == 'Yes' || v == 'true') {
          row.add('Y');
        } else if (v == 'NR') {
          row.add('NR');
        } else if (v == 'N' || v == 'No' || v == 'false') {
          row.add('N');
        } else {
          row.add(v.isEmpty ? '—' : v);
        }
      }
      rows.add(row);
    });

    final apgarRow = <String>['Apgar'];
    for (final m in minutes) {
      final a = formC.apgarScores[m]?.trim() ?? '';
      apgarRow.add(a.isEmpty ? '—' : a);
    }
    rows.add(apgarRow);

    return pw.Table.fromTextArray(
      headers: headers,
      data: rows,
      border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey500),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignment: pw.Alignment.center,
      cellPadding: const pw.EdgeInsets.all(3),
    );
  }

  // ── Value helpers ─────────────────────────────────────────────────────────

  static String _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  static String _ynBool(bool? v) {
    if (v == true) return 'Yes';
    if (v == false) return 'No';
    return '—';
  }

  static String _fmtIsoDate(String iso) {
    try {
      final d = DateTime.parse(iso.split('T').first);
      return DateFormat('dd MMM yyyy').format(d);
    } catch (_) {
      return iso;
    }
  }

  static String _secsToHms(int total) {
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
}
