// lib/services/api_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/crf.dart';
import '../models/form_b.dart';
import '../models/form_c.dart';
import '../utils/form_b_local_guard.dart';


class ApiService {
  static const String _storageKey = 'crfs';

  Future<dynamic> getFullData(String enrollmentId) async {
  await Future.delayed(const Duration(seconds: 1));

  return {
    "crf": {
      "gestationWeeks": 38,
      "gestationDays": 2,
      "motherFirstName": "Test",
      "motherSurname": "User"
    },
    "formB": {
      "babyUid": "BABY123"
    }
  };
}

  // ===============================
  // SAVE CRF
  // ===============================
  Future<void> saveCRF(CRF crf) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> existing =
        prefs.getStringList(_storageKey) ?? [];

    existing.add(crf.toRawJson());

    await prefs.setStringList(_storageKey, existing);
  }

  // ===============================
  // LOAD ALL CRFs
  // ===============================
  Future<List<CRF>> loadAllCRFs() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> existing =
        prefs.getStringList(_storageKey) ?? [];

    return existing.map<CRF>((s) {
      try {
        final Map<String, dynamic> jsonData =
            json.decode(s) as Map<String, dynamic>;
        return CRF.fromJson(jsonData);
      } catch (e) {
        // 🔒 SAFETY FALLBACK (must include ALL required fields)
        return CRF(
          // IDENTIFICATION
          screeningId: "",
          site: "",
          siteId: "",
          screeningDateTime: "",
          screenedBy: "",

          // MATERNAL DETAILS
          motherFirstName: "",
          motherSurname: "",
          husbandFirstName: "",
          husbandSurname: "",
          motherPhone: "",
          husbandPhone: "",
          maternalUid: "",
          hospitalNo: "",

          // GESTATION
          gestationWeeks: 0,
          gestationDays: 0,
          gestationMethod: "",
          expectedDeliveryDate: "",
          gestationKnownInWeeks: false,
          eddKnown: false, 


          // EXCLUSION
          exclusion: false,
          exclusionReason: "",
          anomalyDetails: "",

          // FINAL DECISION & CONSENT
          eligibilityStatus: "",
          consentStatus: "",
          consentRefusalReason: "",
          relationshipToParticipant: "",
          relationshipOther: "",
          consentTakenBy: "",
        );
      }
    }).toList();
  }
// ===============================
// SAVE FORM B
// ===============================
Future<void> saveFormB(FormB formB) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    "formB_${formB.screeningId}",
    jsonEncode(formB.toJson()),
  );
}

// ===============================
// LOAD FORM B
// ===============================
Future<FormB?> loadFormB(
  String screeningId, {
  String maternalUid = '',
  String motherFirstName = '',
  DateTime? screeningCreatedAt,
  bool serverHasBirthLink = false,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final data = prefs.getString("formB_$screeningId");

  if (data == null) return null;

  final formB = FormB.fromJson(jsonDecode(data));
  if (!localFormBIsForPatient(
    local: formB,
    screeningId: screeningId,
    maternalUid: maternalUid,
    motherFirstName: motherFirstName,
    screeningCreatedAt: screeningCreatedAt,
    serverHasBirthLink: serverHasBirthLink,
  )) {
    await prefs.remove("formB_$screeningId");
    return null;
  }
  return formB;
}

Future<void> clearFormB(String screeningId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove("formB_$screeningId");
}

// ===============================
// SAVE FORM C
// ===============================
Future<void> saveFormC(FormC formC) async {
  final prefs = await SharedPreferences.getInstance();
  final key = "formC_${formC.screeningId}";
  await prefs.setString(key, jsonEncode(formC.toJson()));
}

// ===============================
// LOAD FORM C
// ===============================
Future<FormC?> loadFormC(String screeningId) async {
  final prefs = await SharedPreferences.getInstance();
  final data = prefs.getString("formC_$screeningId");

  if (data == null) return null;

  return FormC.fromJson(jsonDecode(data));
}

Future<void> clearFormC(String screeningId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove("formC_$screeningId");
}

  // ===============================
  // CLEAR ALL DATA
  // ===============================
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
