/// Form B Q18 — indication for delivery (CRF v1.25+), full labels on UI.
const List<String> kFormBIndicationOptions = [
  'Preterm Premature Rupture of Membranes (pPROM)',
  'Preterm Labor (PTL)',
  'Antepartum Hemorrhage (APH)',
  'Placenta Previa',
  'Pregnancy-Induced Hypertension (PIH)',
  'Preeclampsia / Imminent Eclampsia (PE)',
  'Other',
];

const Map<String, String> kFormBIndicationLegacy = {
  'pPROM': 'Preterm Premature Rupture of Membranes (pPROM)',
  'PPROM': 'Preterm Premature Rupture of Membranes (pPROM)',
  'PTL': 'Preterm Labor (PTL)',
  'APH': 'Antepartum Hemorrhage (APH)',
  'PIH': 'Pregnancy-Induced Hypertension (PIH)',
  'PE/Imminent Eclampsia': 'Preeclampsia / Imminent Eclampsia (PE)',
};

List<String> normalizeFormBIndications(List<String> raw) =>
    raw.map((v) => kFormBIndicationLegacy[v] ?? v).toList();

List<String> normalizeFormBIndicationsFromCsv(String? csv) {
  if (csv == null || csv.trim().isEmpty) return [];
  return normalizeFormBIndications(
    csv.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
  );
}
