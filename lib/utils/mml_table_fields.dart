// Summary table columns for Daily Monitoring Sheet — mirrors web MinimalMonitoringLog.jsx
// BLOCK_FIELDS + tableFieldsForBlock().

import '../models/minimal_monitoring.dart';

class MmlTableField {
  final String key;
  final String label;
  final String? unit;
  final bool list;
  final bool boolField;

  const MmlTableField(
    this.key,
    this.label, {
    this.unit,
    this.list = false,
    this.boolField = false,
  });
}

const _blockFields = <String, List<MmlTableField>>{
  'cv_a': [
    MmlTableField('axillary_temp', 'Skin/Axillary Temp', unit: '°C'),
    MmlTableField('sbp', 'SBP', unit: 'mm Hg'),
    MmlTableField('dbp', 'DBP', unit: 'mm Hg'),
    MmlTableField('map_value', 'MAP', unit: 'mm Hg'),
  ],
  'cv_b': [MmlTableField('fluid_bolus_given', 'Fluid Bolus')],
  'cv_c': [
    MmlTableField('vasoactive_drugs', 'Vasoactive', list: true),
    MmlTableField('vasoactive_dose', 'Dose'),
    MmlTableField('vasoactive_unit', 'Unit'),
  ],
  'cv_d': [
    MmlTableField('pda_agent', 'PDA Agent', list: true),
    MmlTableField('pda_dose', 'Dose', unit: 'mg/kg'),
  ],
  'resp_b': [
    MmlTableField('ph', 'pH'),
    MmlTableField('pao2', 'PaO₂', unit: 'mm Hg'),
    MmlTableField('paco2', 'PaCO₂', unit: 'mm Hg'),
  ],
  'resp_c': [
    MmlTableField('apnea_episodes', 'Apnea eps.'),
    MmlTableField('desaturation_episodes', 'Desat eps.'),
    MmlTableField('severe_desaturation_episodes', 'Sev. desat eps.'),
  ],
  'resp_d': [
    MmlTableField('postnatal_steroids', 'Steroids', list: true),
    MmlTableField('steroid_dose', 'Dose', unit: 'mg/kg'),
    MmlTableField('steroid_other', 'Other'),
  ],
  'met_a': [MmlTableField('glucose', 'Glucose', unit: 'mg/dL')],
  'met_b': [
    MmlTableField('alp', 'ALP', unit: 'IU/L'),
    MmlTableField('total_calcium', 'Total Ca', unit: 'mg/dL'),
    MmlTableField('phosphorus', 'Phosphorus', unit: 'mg/dL'),
  ],
  'met_c': [
    MmlTableField('electrolyte_abnormality', 'Electrolyte abn.', boolField: true),
    MmlTableField('electrolytes', 'Electrolytes', list: true),
    MmlTableField('hypo_hyper', 'Hypo/Hyper'),
    MmlTableField('symptomatic_status', 'Symptomatic'),
    MmlTableField('symptomatic_detail', 'Details'),
  ],
  'gi_a': [
    MmlTableField('cumulative_feed_volume', 'Cum. Feed Vol.', unit: 'ml'),
  ],
  'gi_b': [
    MmlTableField('direct_bilirubin', 'Direct Bilirubin', unit: 'mg/dL'),
  ],
  'neuro_a': [
    MmlTableField('ventriculomegaly_severity', 'Severity'),
    MmlTableField('vi', 'VI', unit: 'mm'),
    MmlTableField('ahw', 'AHW', unit: 'mm'),
  ],
  'neuro_b': [
    MmlTableField('tod', 'TOD', unit: 'mm'),
    MmlTableField('aca_ri', 'ACA RI'),
    MmlTableField('mca_ri', 'MCA RI'),
  ],
  'heme_a': [
    MmlTableField('transfusion_products', 'Products', list: true),
    MmlTableField('transfusion_count', 'No. of Transfusions'),
    MmlTableField('prbc_volume', 'PRBC Volume', unit: 'ml/kg'),
  ],
};

List<MmlTableField> mmlTableFieldsForBlock(String blockKey) {
  if (blockKey == 'resp_a') {
    return const [
      MmlTableField('time_range', 'Time'),
      MmlTableField('respiratory_modes', 'Respiratory support', list: true),
    ];
  }
  return _blockFields[blockKey] ?? const [];
}

String mmlFormatTableCell(MmlTableField field, MmlEntry entry) {
  final v = entry[field.key];
  if (field.key == 'time_range') {
    final raw = v?.toString() ?? '';
    return raw.trim().isEmpty ? '—' : raw;
  }
  if (field.boolField) {
    if (v == true) return 'Yes';
    if (v == false) return 'No';
    return '—';
  }
  if (field.list) {
    if (v is List) {
      return v.isEmpty ? '—' : v.map((e) => e.toString()).join(', ');
    }
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? '—' : s;
  }
  if (v == null || v.toString().trim().isEmpty) return '—';
  var s = v.toString();
  if (field.key == 'fluid_bolus_given') {
    s = mmlNormalizeFluidBolusValue(s);
    if (s.isEmpty) return '—';
  }
  return field.unit != null ? '$s ${field.unit}' : s;
}
