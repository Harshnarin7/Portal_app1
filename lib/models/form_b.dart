class FormB {
  final String screeningId;
  final String babyUid;
  final String birthWeight;
  final String indication;
  final String delivery;
  final String labor;
  final String gender;
  final String dateOfBirth;
final String timeOfBirth;
  final bool requiredResuscitation;
  final bool randomized;

  final bool? poorRespiratoryEffort;
  final bool? poorMuscleTone;
  final bool? initialStepsRequired;

  final String enrollmentId;

  FormB({
    required this.screeningId,
    required this.babyUid,
    required this.birthWeight,
    required this.dateOfBirth,
  required this.timeOfBirth,
    required this.indication,
    required this.delivery,
    required this.labor,
    required this.gender,
    required this.requiredResuscitation,
    required this.randomized,
    required this.enrollmentId,
    this.poorRespiratoryEffort,
    this.poorMuscleTone,
    this.initialStepsRequired,

  });

  Map<String, dynamic> toJson() => {
        "screeningId": screeningId,
        "babyUid": babyUid,
        "birthWeight": birthWeight,
        "dateOfBirth": dateOfBirth,
  "timeOfBirth": timeOfBirth,
        "indication": indication,
        "delivery": delivery,
        "labor": labor,
        "gender": gender,
        "requiredResuscitation": requiredResuscitation,
        "randomized": randomized,
        "enrollmentId": enrollmentId,
        "poorRespiratoryEffort": poorRespiratoryEffort,
        "poorMuscleTone": poorMuscleTone,
        "initialStepsRequired": initialStepsRequired,

      };

  factory FormB.fromJson(Map<String, dynamic> json) {
    return FormB(
      screeningId: json["screeningId"],
      babyUid: json["babyUid"],
      birthWeight: json["birthWeight"],
      dateOfBirth: json["dateOfBirth"] ?? "",
    timeOfBirth: json["timeOfBirth"] ?? "",
      indication: json["indication"],
      delivery: json["delivery"],
      labor: json["labor"],
      gender: json["gender"],
      requiredResuscitation: json["requiredResuscitation"],
      randomized: json["randomized"],
      enrollmentId: json["enrollmentId"],
      poorRespiratoryEffort: json["poorRespiratoryEffort"],
      poorMuscleTone: json["poorMuscleTone"],
      initialStepsRequired: json["initialStepsRequired"],

    );
  }
}
