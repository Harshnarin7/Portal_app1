/// Pending seed from Gestation Log → Form A.
/// ScreeningForm can consume this later; this pass only stores it.
class GaCheckSeedStore {
  GaCheckSeedStore._();

  static int? pendingId;
  static String motherName = '';
  static String motherUid = '';
  static dynamic gestationWeeks;
  static dynamic gestationDays;
  static String gestationMethod = '';

  static void setFromEntry(Map<String, dynamic> entry) {
    pendingId = entry['id'] is int ? entry['id'] as int : int.tryParse('${entry['id']}');
    motherName = (entry['mother_name'] ?? '').toString();
    motherUid = (entry['mother_uid'] ?? '').toString();
    gestationWeeks = entry['gestation_weeks'];
    gestationDays = entry['gestation_days'];
    gestationMethod = (entry['gestation_method'] ?? '').toString();
  }

  static void clear() {
    pendingId = null;
    motherName = '';
    motherUid = '';
    gestationWeeks = null;
    gestationDays = null;
    gestationMethod = '';
  }
}
