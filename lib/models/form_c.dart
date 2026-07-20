class FormC {
  final String screeningId;

  final bool ventilation;
  final String device;
  final bool sibPeep;
  final String interface;
  final String ventilationDuration;

  final bool intubation;
  final bool chestCompression;
  final String chestCompressionDuration;

  final bool epinephrine;
  final String epinephrineDoses;

  final bool fluidBolus;

  final bool placentalTransfusion;
  final String placentalMethod;

  final String cordClampedAt;      // ← ADD
  final String cordClampTime;
  final String timeToRespiration;
  final String timeToSpo2Above80;  // ← ADD
  final String spo2At5Min;
  final String totalTime;          // ← ADD

  final String fio2Exit;
  final String spo2Exit;

  final String ph;
  final String be;
  final String pco2;

  final bool cordBloodDone;
  final bool resusFailure;
  final String exitReason;
  final Map<String, Map<int, bool>> timelineChecks;
  final Map<int, String> apgarScores;

  FormC({
    required this.screeningId,
    required this.ventilation,
    required this.device,
    required this.sibPeep,
    required this.interface,
    required this.ventilationDuration,
    required this.intubation,
    required this.chestCompression,
    required this.chestCompressionDuration,
    required this.epinephrine,
    required this.epinephrineDoses,
    required this.fluidBolus,
    required this.placentalTransfusion,
    required this.placentalMethod,
    required this.cordClampedAt,      // ← ADD
    required this.cordClampTime,
    required this.timeToRespiration,
    required this.timeToSpo2Above80,  // ← ADD
    required this.spo2At5Min,
    required this.totalTime,          // ← ADD
    required this.timelineChecks,
    required this.apgarScores,
    required this.fio2Exit,
    required this.spo2Exit,
    required this.ph,
    required this.be,
    required this.pco2,
    required this.cordBloodDone,
    required this.resusFailure,
    required this.exitReason,
  });

  factory FormC.fromJson(Map<String, dynamic> json) {
    return FormC(
      screeningId: json["screeningId"] ?? "",
      ventilation: json["ventilation"] ?? false,
      device: json["device"] ?? "",
      sibPeep: json["sibPeep"] ?? false,
      interface: json["interface"] ?? "",
      ventilationDuration: json["ventilationDuration"] ?? "",
      intubation: json["intubation"] ?? false,
      chestCompression: json["chestCompression"] ?? false,
      chestCompressionDuration: json["chestCompressionDuration"] ?? "",
      epinephrine: json["epinephrine"] ?? false,
      epinephrineDoses: json["epinephrineDoses"] ?? "",
      fluidBolus: json["fluidBolus"] ?? false,
      placentalTransfusion: json["placentalTransfusion"] ?? false,
      placentalMethod: json["placentalMethod"] ?? "",
      cordClampedAt: json["cordClampedAt"] ?? "",        // ← ADD
      cordClampTime: json["cordClampTime"] ?? "",
      timeToRespiration: json["timeToRespiration"] ?? "",
      timeToSpo2Above80: json["timeToSpo2Above80"] ?? "", // ← ADD
      spo2At5Min: json["spo2At5Min"] ?? "",
      totalTime: json["totalTime"] ?? "",                 // ← ADD
      fio2Exit: json["fio2Exit"] ?? "",
      spo2Exit: json["spo2Exit"] ?? "",
      ph: json["ph"] ?? "",
      be: json["be"] ?? "",
      pco2: json["pco2"] ?? "",
      cordBloodDone: json["cordBloodDone"] ?? false,
      resusFailure: json["resusFailure"] ?? false,
      exitReason: json["exitReason"] ?? "",
      timelineChecks: (json["timelineChecks"] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(
                k,
                (v as Map<String, dynamic>).map(
                  (min, val) => MapEntry(int.parse(min), val as bool),
                ),
              )),
      apgarScores: (json["apgarScores"] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(int.parse(k), v as String)),
    );
  }

  Map<String, dynamic> toJson() => {
        "screeningId": screeningId,
        "ventilation": ventilation,
        "device": device,
        "sibPeep": sibPeep,
        "interface": interface,
        "ventilationDuration": ventilationDuration,
        "intubation": intubation,
        "chestCompression": chestCompression,
        "chestCompressionDuration": chestCompressionDuration,
        "epinephrine": epinephrine,
        "epinephrineDoses": epinephrineDoses,
        "fluidBolus": fluidBolus,
        "placentalTransfusion": placentalTransfusion,
        "placentalMethod": placentalMethod,
        "cordClampedAt": cordClampedAt,        // ← ADD
        "cordClampTime": cordClampTime,
        "timeToRespiration": timeToRespiration,
        "timeToSpo2Above80": timeToSpo2Above80, // ← ADD
        "spo2At5Min": spo2At5Min,
        "totalTime": totalTime,                 // ← ADD
        "fio2Exit": fio2Exit,
        "spo2Exit": spo2Exit,
        "ph": ph,
        "be": be,
        "pco2": pco2,
        "cordBloodDone": cordBloodDone,
        "resusFailure": resusFailure,
        "exitReason": exitReason,
        "timelineChecks": timelineChecks.map(
          (k, v) => MapEntry(
            k,
            v.map((min, val) => MapEntry(min.toString(), val)),
          ),
        ),
        "apgarScores": apgarScores.map(
          (k, v) => MapEntry(k.toString(), v),
        ),
      };
}