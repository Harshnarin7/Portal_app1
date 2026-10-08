/// Local filter for the Gestation (Inclusion Criteria) Screening Log.
/// The full list is already loaded, so search stays on the device.
String collapseSearchSpaces(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

bool gaCheckMatchesQuery(Map<String, dynamic> entry, String query) {
  final q = collapseSearchSpaces(query);
  if (q.isEmpty) return true;
  final name = collapseSearchSpaces((entry['mother_name'] ?? '').toString());
  final id = (entry['mother_uid'] ?? '').toString().trim().toLowerCase();
  final idQuery = q.replaceAll(' ', '');
  return name.contains(q) || (idQuery.isNotEmpty && id.contains(idQuery));
}

List<Map<String, dynamic>> filterGaChecks(
  List<Map<String, dynamic>> entries,
  String query,
) {
  if (collapseSearchSpaces(query).isEmpty) return entries;
  return entries.where((e) => gaCheckMatchesQuery(e, query)).toList();
}
