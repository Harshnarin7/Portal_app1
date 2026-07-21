// lib/models/crf.dart
import 'dart:convert';

class CRF {
  // ===============================
  // IDENTIFICATION
  // ===============================
  final String screeningId;
  final String site;
  final String siteId;
  final String screeningDateTime;
  final String screenedBy;

  // ===============================
  // MATERNAL IDENTIFICATION
  // ===============================
  final String motherFirstName;
  final String motherSurname;
  final String husbandFirstName;
  final String husbandSurname;
  final String motherPhone;
  final String husbandPhone;
  final String maternalUid;
  final String hospitalNo;

  // ===============================
  // GESTATION & DELIVERY
  // ===============================
  final int gestationWeeks;
  final int gestationDays;
  final String gestationMethod;
  final String expectedDeliveryDate;

  // ✅ NEW — GESTATION FLAGS (YES / NO)
  final bool gestationKnownInWeeks; // "Yes" | "No"
  final bool eddKnown;              // "Yes" | "No"

  // ===============================
  // EXCLUSION
  // ===============================
  final bool exclusion;
  final String exclusionReason;
  final String anomalyDetails;

  // ===============================
  // FINAL DECISION & CONSENT
  // ===============================
  final String eligibilityStatus;
  final String consentStatus;
  final String consentRefusalReason;

  final String relationshipToParticipant;
  final String relationshipOther;
  final String consentTakenBy;

  // Present only after randomization (Form B). Used to gate access to
  // enrollment-scoped forms (Helper Forms 2-4, FiO2 AUC) — empty string
  // means "not yet randomized, those forms aren't applicable yet".
  final String enrollmentId;

  CRF({
    required this.screeningId,
    required this.site,
    required this.siteId,
    required this.screeningDateTime,
    required this.screenedBy,

    required this.motherFirstName,
    required this.motherSurname,
    required this.husbandFirstName,
    required this.husbandSurname,
    required this.motherPhone,
    required this.husbandPhone,
    required this.maternalUid,
    required this.hospitalNo,

    required this.gestationWeeks,
    required this.gestationDays,
    required this.gestationMethod,
    required this.expectedDeliveryDate,

    // ✅ NEW
    required this.gestationKnownInWeeks,
    required this.eddKnown,

    required this.exclusion,
    required this.exclusionReason,
    required this.anomalyDetails,

    required this.eligibilityStatus,
    required this.consentStatus,
    required this.consentRefusalReason,

    required this.relationshipToParticipant,
    required this.relationshipOther,
    required this.consentTakenBy,

    this.enrollmentId = "",
  });

  // ===============================
  // JSON SERIALIZATION
  // ===============================
  Map<String, dynamic> toJson() {
    return {
      "identification": {
        "screeningId": screeningId,
        "site": site,
        "siteId": siteId,
        "screeningDateTime": screeningDateTime,
        "screenedBy": screenedBy,
      },

      "maternal": {
        "motherFirstName": motherFirstName,
        "motherSurname": motherSurname,
        "husbandFirstName": husbandFirstName,
        "husbandSurname": husbandSurname,
        "motherPhone": motherPhone,
        "husbandPhone": husbandPhone,
        "maternalUid": maternalUid,
        "hospitalNo": hospitalNo,
      },

      "gestation": {
        "weeks": gestationWeeks,
        "days": gestationDays,
        "method": gestationMethod,
        "expectedDeliveryDate": expectedDeliveryDate,

        // ✅ NEW FLAGS
        "gestationKnownInWeeks": gestationKnownInWeeks,
        "eddKnown": eddKnown,
      },

      "exclusion": {
        "present": exclusion,
        "reason": exclusionReason,
        "anomalyDetails": anomalyDetails,
      },

      "finalDecision": {
        "eligibilityStatus": eligibilityStatus,
        "consentStatus": consentStatus,
        "consentRefusalReason": consentRefusalReason,
        "relationshipToParticipant": relationshipToParticipant,
        "relationshipOther": relationshipOther,
        "consentTakenBy": consentTakenBy,
      },

      "enrollmentId": enrollmentId,
    };
  }

  factory CRF.fromJson(Map<String, dynamic> json) {
    final id = json["identification"] ?? {};
    final mat = json["maternal"] ?? {};
    final gest = json["gestation"] ?? {};
    final exc = json["exclusion"] ?? {};
    final fin = json["finalDecision"] ?? {};

    return CRF(
      screeningId: id["screeningId"] ?? "",
      site: id["site"] ?? "",
      siteId: id["siteId"] ?? "",
      screeningDateTime: id["screeningDateTime"] ?? "",
      screenedBy: id["screenedBy"] ?? "",

      motherFirstName: mat["motherFirstName"] ?? "",
      motherSurname: mat["motherSurname"] ?? "",
      husbandFirstName: mat["husbandFirstName"] ?? "",
      husbandSurname: mat["husbandSurname"] ?? "",
      motherPhone: mat["motherPhone"] ?? "",
      husbandPhone: mat["husbandPhone"] ?? "",
      maternalUid: mat["maternalUid"] ?? "",
      hospitalNo: mat["hospitalNo"] ?? "",

      gestationWeeks: gest["weeks"] ?? 0,
      gestationDays: gest["days"] ?? 0,
      gestationMethod: gest["method"] ?? "",
      expectedDeliveryDate: gest["expectedDeliveryDate"] ?? "",

      // ✅ SAFE FALLBACKS FOR OLD DATA
      gestationKnownInWeeks:
          gest["gestationKnownInWeeks"] ?? false,
      eddKnown:
          gest["eddKnown"] ?? false,

      exclusion: exc["present"] ?? false,
      exclusionReason: exc["reason"] ?? "",
      anomalyDetails: exc["anomalyDetails"] ?? "",

      eligibilityStatus: fin["eligibilityStatus"] ?? "",
      consentStatus: fin["consentStatus"] ?? "",
      consentRefusalReason: fin["consentRefusalReason"] ?? "",
      relationshipToParticipant:
          fin["relationshipToParticipant"] ?? "",
      relationshipOther: fin["relationshipOther"] ?? "",
      consentTakenBy: fin["consentTakenBy"] ?? "",

      enrollmentId: json["enrollmentId"] ?? "",
    );
  }

  String toRawJson() => jsonEncode(toJson());
}