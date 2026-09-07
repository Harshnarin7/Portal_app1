import 'birth_resuscitation.dart';

/// Local cache model for mobile Form C (SharedPreferences).
/// Includes every UI field so drafts never lose resuscitation details.
class FormC {
  final String screeningId;

  final bool? ventilation;
  final String device;
  final bool? sibPeep;
  final String? sibPeepWith;
  final String sibPeepCmh2o;
  final String tpiecePip;
  final String tpiecePeep;
  final String tpieceFlow;
  final String interface;
  final String ventilationDuration;

  final bool? intubation;
  final bool? chestCompression;
  final String chestCompressionDuration;

  final bool? epinephrine;
  final String epinephrineDoses;
  final String? adrenalineDilution;
  final String? adrenalineRoute;

  final bool? fluidBolus;
  final String fluidBolusDoses;
  final String fluidBolusCumulative;

  final bool? placentalTransfusion;
  final String placentalMethod;

  final String cordClampedAt;
  final String cordClampTime;
  final String timeToRespiration;
  final String timeToSpo2Above80;
  final String spo2At5Min;
  final String totalTime;

  final String fio2Exit;
  final String spo2Exit;

  final String ph;
  final String be;
  final String pco2;

  final bool? cordBloodDone;
  final bool? cordBloodWithin1hr;
  final String? cordBloodSource;
  final bool? resusFailure;
  final String exitReason;
  final bool? blenderStopped;
  final List<String> blenderInterruptReasons;
  final String blenderStoppedDescription;
  final String blenderLetter;

  /// Minute-wise Y / N / NR (string) — preserves NR unlike bool map.
  final Map<String, Map<int, String>> timelineChecks;
  final Map<int, String> apgarScores;

  FormC({
    required this.screeningId,
    this.ventilation,
    required this.device,
    this.sibPeep,
    this.sibPeepWith,
    this.sibPeepCmh2o = "",
    this.tpiecePip = "",
    this.tpiecePeep = "",
    this.tpieceFlow = "",
    required this.interface,
    required this.ventilationDuration,
    this.intubation,
    this.chestCompression,
    required this.chestCompressionDuration,
    this.epinephrine,
    this.epinephrineDoses = "",
    this.adrenalineDilution,
    this.adrenalineRoute,
    this.fluidBolus,
    this.fluidBolusDoses = "",
    this.fluidBolusCumulative = "",
    this.placentalTransfusion,
    required this.placentalMethod,
    required this.cordClampedAt,
    required this.cordClampTime,
    required this.timeToRespiration,
    required this.timeToSpo2Above80,
    required this.spo2At5Min,
    required this.totalTime,
    required this.timelineChecks,
    required this.apgarScores,
    this.fio2Exit = "",
    required this.spo2Exit,
    required this.ph,
    required this.be,
    required this.pco2,
    this.cordBloodDone,
    this.cordBloodWithin1hr,
    this.cordBloodSource,
    this.resusFailure,
    required this.exitReason,
    this.blenderStopped,
    this.blenderInterruptReasons = const [],
    this.blenderStoppedDescription = "",
    this.blenderLetter = "",
  });

  static Map<String, Map<int, String>> _parseTimeline(dynamic raw) {
    final out = <String, Map<int, String>>{};
    if (raw is! Map) return out;
    raw.forEach((k, v) {
      if (v is! Map) return;
      final mins = <int, String>{};
      v.forEach((minKey, val) {
        final m = int.tryParse(minKey.toString());
        if (m == null) return;
        if (val == null) return;
        if (val is bool) {
          mins[m] = val ? "Y" : "N";
        } else {
          final s = val.toString().trim();
          if (s.isEmpty) return;
          // Normalize legacy Yes/No
          if (s == "Yes" || s == "Y") {
            mins[m] = "Y";
          } else if (s == "No" || s == "N") {
            mins[m] = "N";
          } else {
            mins[m] = s; // NR or other
          }
        }
      });
      out[k.toString()] = mins;
    });
    return out;
  }

  factory FormC.fromJson(Map<String, dynamic> json) {
    return FormC(
      screeningId: (json["screeningId"] ?? "").toString(),
      ventilation: json["ventilation"] as bool?,
      device: (json["device"] ?? "").toString(),
      sibPeep: json["sibPeep"] as bool?,
      sibPeepWith: json["sibPeepWith"]?.toString(),
      sibPeepCmh2o: (json["sibPeepCmh2o"] ?? "").toString(),
      tpiecePip: (json["tpiecePip"] ?? "").toString(),
      tpiecePeep: (json["tpiecePeep"] ?? "").toString(),
      tpieceFlow: (json["tpieceFlow"] ?? "").toString(),
      interface: (json["interface"] ?? "").toString(),
      ventilationDuration: (json["ventilationDuration"] ?? "").toString(),
      intubation: json["intubation"] as bool?,
      chestCompression: json["chestCompression"] as bool?,
      chestCompressionDuration:
          (json["chestCompressionDuration"] ?? "").toString(),
      epinephrine: json["epinephrine"] as bool?,
      epinephrineDoses: (json["epinephrineDoses"] ?? "").toString(),
      adrenalineDilution: json["adrenalineDilution"]?.toString(),
      adrenalineRoute: json["adrenalineRoute"]?.toString(),
      fluidBolus: json["fluidBolus"] as bool?,
      fluidBolusDoses: (json["fluidBolusDoses"] ?? "").toString(),
      fluidBolusCumulative: (json["fluidBolusCumulative"] ?? "").toString(),
      placentalTransfusion: json["placentalTransfusion"] as bool?,
      placentalMethod: (json["placentalMethod"] ?? "").toString(),
      cordClampedAt: (json["cordClampedAt"] ?? "").toString(),
      cordClampTime: (json["cordClampTime"] ?? "").toString(),
      timeToRespiration: (json["timeToRespiration"] ?? "").toString(),
      timeToSpo2Above80: (json["timeToSpo2Above80"] ?? "").toString(),
      spo2At5Min: (json["spo2At5Min"] ?? "").toString(),
      totalTime: (json["totalTime"] ?? "").toString(),
      fio2Exit: (json["fio2Exit"] ?? "").toString(),
      spo2Exit: (json["spo2Exit"] ?? "").toString(),
      ph: (json["ph"] ?? "").toString(),
      be: (json["be"] ?? "").toString(),
      pco2: (json["pco2"] ?? "").toString(),
      cordBloodDone: json["cordBloodDone"] as bool?,
      cordBloodWithin1hr: json["cordBloodWithin1hr"] as bool?,
      cordBloodSource: json["cordBloodSource"]?.toString(),
      resusFailure: json["resusFailure"] as bool?,
      exitReason: (json["exitReason"] ?? "").toString(),
      blenderStopped: json["blenderStopped"] as bool?,
      blenderInterruptReasons: parseBlenderInterruptReasons(
        json["blenderInterruptReasons"] ?? json["blender_interrupt_reasons"],
      ),
      blenderStoppedDescription:
          (json["blenderStoppedDescription"] ?? "").toString(),
      blenderLetter: (json["blenderLetter"] ?? "").toString(),
      timelineChecks: _parseTimeline(json["timelineChecks"]),
      apgarScores: (json["apgarScores"] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(int.parse(k), v.toString()),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        "screeningId": screeningId,
        "ventilation": ventilation,
        "device": device,
        "sibPeep": sibPeep,
        "sibPeepWith": sibPeepWith,
        "sibPeepCmh2o": sibPeepCmh2o,
        "tpiecePip": tpiecePip,
        "tpiecePeep": tpiecePeep,
        "tpieceFlow": tpieceFlow,
        "interface": interface,
        "ventilationDuration": ventilationDuration,
        "intubation": intubation,
        "chestCompression": chestCompression,
        "chestCompressionDuration": chestCompressionDuration,
        "epinephrine": epinephrine,
        "epinephrineDoses": epinephrineDoses,
        "adrenalineDilution": adrenalineDilution,
        "adrenalineRoute": adrenalineRoute,
        "fluidBolus": fluidBolus,
        "fluidBolusDoses": fluidBolusDoses,
        "fluidBolusCumulative": fluidBolusCumulative,
        "placentalTransfusion": placentalTransfusion,
        "placentalMethod": placentalMethod,
        "cordClampedAt": cordClampedAt,
        "cordClampTime": cordClampTime,
        "timeToRespiration": timeToRespiration,
        "timeToSpo2Above80": timeToSpo2Above80,
        "spo2At5Min": spo2At5Min,
        "totalTime": totalTime,
        "fio2Exit": fio2Exit,
        "spo2Exit": spo2Exit,
        "ph": ph,
        "be": be,
        "pco2": pco2,
        "cordBloodDone": cordBloodDone,
        "cordBloodWithin1hr": cordBloodWithin1hr,
        "cordBloodSource": cordBloodSource,
        "resusFailure": resusFailure,
        "exitReason": exitReason,
        "blenderStopped": blenderStopped,
        "blenderInterruptReasons": blenderInterruptReasons,
        "blenderStoppedDescription": blenderStoppedDescription,
        "blenderLetter": blenderLetter,
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
