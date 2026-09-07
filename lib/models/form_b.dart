/// Local cache model for mobile Form B (SharedPreferences).
/// Must include every UI field so Save for Later / Cancel never drops data.
class FormB {
  final String screeningId;
  final String babyUid;
  final String babyAdmissionNo;
  final String babyAnnualNo;
  final String birthWeight;
  final String intrauterineCentile;
  final String indication;
  final String indicationOther;
  final String delivery;
  final String labor;
  final String gender;
  final String dateOfBirth;
  final String timeOfBirth;

  /// Null = unanswered (do not coerce to false on draft).
  final bool? requiredResuscitation;
  final bool? randomized;
  final bool? poorRespiratoryEffort;
  final bool? poorMuscleTone;
  final bool? hrAbove100;
  final bool? initialStepsRequired;

  final String enrollmentId;
  final String randomizationDate;
  final String notRandomizedReason;
  final String notRandomizedOther;

  FormB({
    required this.screeningId,
    required this.babyUid,
    this.babyAdmissionNo = "",
    this.babyAnnualNo = "",
    required this.birthWeight,
    this.intrauterineCentile = "",
    required this.dateOfBirth,
    required this.timeOfBirth,
    required this.indication,
    this.indicationOther = "",
    required this.delivery,
    required this.labor,
    required this.gender,
    this.requiredResuscitation,
    this.randomized,
    required this.enrollmentId,
    this.poorRespiratoryEffort,
    this.poorMuscleTone,
    this.hrAbove100,
    this.initialStepsRequired,
    this.randomizationDate = "",
    this.notRandomizedReason = "",
    this.notRandomizedOther = "",
  });

  Map<String, dynamic> toJson() => {
        "screeningId": screeningId,
        "babyUid": babyUid,
        "babyAdmissionNo": babyAdmissionNo,
        "babyAnnualNo": babyAnnualNo,
        "birthWeight": birthWeight,
        "intrauterineCentile": intrauterineCentile,
        "dateOfBirth": dateOfBirth,
        "timeOfBirth": timeOfBirth,
        "indication": indication,
        "indicationOther": indicationOther,
        "delivery": delivery,
        "labor": labor,
        "gender": gender,
        "requiredResuscitation": requiredResuscitation,
        "randomized": randomized,
        "enrollmentId": enrollmentId,
        "poorRespiratoryEffort": poorRespiratoryEffort,
        "poorMuscleTone": poorMuscleTone,
        "hrAbove100": hrAbove100,
        "initialStepsRequired": initialStepsRequired,
        "randomizationDate": randomizationDate,
        "notRandomizedReason": notRandomizedReason,
        "notRandomizedOther": notRandomizedOther,
      };

  factory FormB.fromJson(Map<String, dynamic> json) {
    return FormB(
      screeningId: (json["screeningId"] ?? "").toString(),
      babyUid: (json["babyUid"] ?? "").toString(),
      babyAdmissionNo: (json["babyAdmissionNo"] ?? "").toString(),
      babyAnnualNo: (json["babyAnnualNo"] ?? "").toString(),
      birthWeight: (json["birthWeight"] ?? "").toString(),
      intrauterineCentile: (json["intrauterineCentile"] ?? "").toString(),
      dateOfBirth: (json["dateOfBirth"] ?? "").toString(),
      timeOfBirth: (json["timeOfBirth"] ?? "").toString(),
      indication: (json["indication"] ?? "").toString(),
      indicationOther: (json["indicationOther"] ?? "").toString(),
      delivery: (json["delivery"] ?? "").toString(),
      labor: (json["labor"] ?? "").toString(),
      gender: (json["gender"] ?? "").toString(),
      requiredResuscitation: json["requiredResuscitation"] as bool?,
      randomized: json["randomized"] as bool?,
      enrollmentId: (json["enrollmentId"] ?? "").toString(),
      poorRespiratoryEffort: json["poorRespiratoryEffort"] as bool?,
      poorMuscleTone: json["poorMuscleTone"] as bool?,
      hrAbove100: json["hrAbove100"] as bool?,
      initialStepsRequired: json["initialStepsRequired"] as bool?,
      randomizationDate: (json["randomizationDate"] ?? "").toString(),
      notRandomizedReason: (json["notRandomizedReason"] ?? "").toString(),
      notRandomizedOther: (json["notRandomizedOther"] ?? "").toString(),
    );
  }
}
