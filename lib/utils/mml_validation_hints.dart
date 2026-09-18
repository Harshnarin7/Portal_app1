// Helper Form 5 — validation hint copy (parity with web MinimalMonitoringLog.jsx).

const kMmlHintMaxFio2 = 'Must be between 21 and 100 (%)';
const kMmlHintPh = 'Usually 6.6–7.8';
const kMmlHintPao2 = 'Usually 20–600 mmHg';
const kMmlHintPaco2 = 'Usually 15–150 mmHg';
const kMmlHintEpisodeCount = 'Whole number, 0 or more';
const kMmlHintSevereDesat =
    'Whole number, 0 or more — cannot exceed the desaturation episodes count above';
const kMmlHintSteroidOther = "Required when 'Other' is selected above";
const kMmlHintSymptomaticDetail =
    'Required when Symptomatic is selected above';
const kMmlHintTransfusionCount = 'Whole number, 0 or more';
const kMmlDateStampHint =
    'Must be on or before the active sheet date — cannot be in the future';
const kMmlTimeStampHint =
    'Cannot be later than the current time on the selected date';
