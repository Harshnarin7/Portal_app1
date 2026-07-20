# Form B / Form C → web `BirthResuscitationForm.jsx` field mapping

One backend record (`birth_resuscitation` table), split across two mobile
screens. Every field below must use the **exact key** shown (already wired
into `birth_resuscitation.dart`) — this is what makes sync work.

Legend: ✅ already in mobile (needs key rename only) · ❌ missing, needs adding

## Screen: FormBBirthResuscitation → B1, B2, B3

| # | Web label | Backend key | Mobile status |
|---|---|---|---|
| B1.4 | Baby UID | `baby_uid` | ✅ (`_babyUidCtrl`) |
| B1.6 | Baby Admission No. | `baby_admission_no` | ✅ (`_babyAdmissionCtrl`) |
| B1.7 | Baby Annual No. | `baby_annual_no` | ✅ (`_babyAnnualNumberCtrl`) |
| B2.8 | Date of Birth | `date_of_birth` | ✅ (`_dobController`) |
| B2.9 | Time of Birth | `time_of_birth` | ✅ (`_timeController`) |
| B2.10 | Gender | `gender` | ✅ (`_gender`) |
| B2.13 | Birth Weight (g) | `birth_weight` | ✅ (`_birthWeightCtrl`) |
| B2.14 | Intrauterine centile | `intrauterine_centile` | ✅ (`_growthCentileCtrl`) |
| B2.15 | Delivery Mode | `delivery_mode` | ✅ (`_delivery`) |
| B2.16 | Vaginal Delivery Type | `vaginal_delivery_type` | ✅ (`_vaginalType`) |
| B2.17 | LSCS Type | `lscs_type` | ✅ (`_lscsType`) |
| B2.18 | Indication for Delivery (multi-select) | `indication_for_delivery` | ✅ (`_indications`) |
| B2.18 | Absent/Reversed EDF detail | `indication_edf_detail` | ❌ add text field, shown only if indication includes that option |
| B2.18 | Fetal indication detail | `fetal_indication_detail` | ❌ add, conditional |
| B2.18 | Obstetric indication detail | `obstetric_indication_detail` | ❌ add, conditional |
| B2.18 | Other delivery indication | `indication_for_delivery_other` | ✅ (`_indicationOtherCtrl`) |
| B3.19 | Respiratory Effort absent/poor | `poor_resp_efforts` | ✅ (`_poorRespiratoryEffort`) |
| B3.20 | Muscle Tone limp/poor | `poor_muscle_tone` | ✅ (`_poorMuscleTone`) |
| B3.21 | Heart Rate > 100 | `hr_above_100` | ❌ add Yes/No toggle |
| B3.22 | Initial Steps Required | `initial_steps` | ✅ (`_initialStepsRequired`) |
| B3.23 | Resuscitation Beyond Initial Steps | `required_resuscitation` | ✅ (`_requiredResuscitation`) |
| B3.24 | Randomised? | `randomised` | ✅ (`_randomized`) |
| B3.25 | Randomization Date | `randomisation_date` | ✅ (`_randomizationDateCtrl`) |
| B3.26 | Enrollment ID | `enrollment_id` | ✅ (built from Site ID + Blender Code + Subject No — keep this UX, just ensure the composed string is written to `enrollment_id`) |
| B3.27 | Strata | `strata` | ✅ (`_strata` getter) |
| B3.28 | Reason Not Randomized | `enrollment_reason_not_randomized` | ✅ (`_notRandomizedReason`) |
| B3.28 | Other reason | `enrollment_reason_not_randomized_other` | ✅ (`_notRandomizedOtherCtrl`) |

## Screen: FormCResuscitationDetails → B4, B5, B6

| # | Web label | Backend key | Mobile status |
|---|---|---|---|
| B4.29 | PPV Required | `ppv_required` | ✅ (`ventilation`, rename) |
| B4.29 | Device used | `device_ppv` | ✅ (`device`, rename — keep same 3 options) |
| B4.29a | SIB — with PEEP valve? | `sib_peep_with` | ❌ add (currently only bool `sibPeep`, needs Yes/No + value split) |
| B4.29a | PEEP value (cmH₂O) | `sib_peep_cmh2o` | ❌ add numeric field |
| B4.29b | T-piece PIP (cmH₂O) | `tpiece_pip` | ❌ add |
| B4.29b | T-piece PEEP (cmH₂O) | `tpiece_peep` | ❌ add |
| B4.29b | T-piece Flow (L/min) | `tpiece_flow` | ❌ add |
| B4.30 | Interface | `interface_used` | ✅ (`interface`, rename) |
| B4.31 | Duration of PPV (sec) | `ppv_duration` | ✅ (`_ventDurationCtrl`, rename) |
| B4.32 | Endotracheal Intubation | `intubation` | ✅ |
| B4.33 | Chest Compressions | `chest_compression` | ✅ |
| B4.34 | Duration of CC (sec) | `cc_duration` | ✅ (`_ccDurationCtrl`, rename) |
| B4.35 | Epinephrine | `adrenaline` | ✅ (`epinephrine`, rename) |
| B4.36 | Dilution | `adrenaline_dilution` | ❌ add dropdown |
| B4.37 | Route | `adrenaline_route` | ❌ add dropdown |
| B4.39 | Number of Doses | `med_doses` | ✅ (`_epiDoseCtrl`, rename) |
| B4.40 | Cumulative Dose (ml/mg) | `adrenaline_cumulative` | ❌ add numeric field |
| B4.41 | Fluid Bolus | `fluid_bolus` | ✅ |
| B4.42 | Number of Doses | `fluid_bolus_doses` | ❌ add |
| B4.43 | Cumulative Volume/Dose | `fluid_bolus_cumulative` | ❌ add |
| B4.44 | Placental Transfusion | `placental_transfusion` | ✅ |
| B4.45 | Method | `transfusion_method` | ✅ (`placentalMethod`, rename) |
| B4.46 | Cord clamped at (HH:MM:SS) | `cord_clamp_timestamp` | ✅ (`cordClampedAt`, rename — keep plain-string handling, not a controller) |
| B4.47 | Cord clamping time from birth (sec) | `cord_clamp_time` | ✅ (`_cordClampTimeCtrl`, rename) |
| B4.48 | Time to Resp Efforts (MM:SS→sec) | `time_to_respiration` | ✅ (`_timeToRespCtrl`, rename) |
| B4.48 | If longer — Days | `respiration_days` | ❌ add |
| B4.48 | If longer — Hours | `respiration_hours` | ❌ add |
| B4.49 | SpO₂ at 5 min | `spo2_5min` | ✅ (`_spo2At5Ctrl`, rename) |
| B4.50 | Time to SpO₂ > 80% | `time_to_spo2_80` | ✅ (`_timeToSpo2Ctrl`, rename) |
| B5.51–55 | Minute-wise table (oxygen/ventilation/chest_compression/intubation/medication/fluid_bolus/cpap) + Apgar | `interventions` (nested JSON) | ✅ close match (`timelineChecks`, `apgarScores`) — just nest under a single `interventions` map with those exact sub-keys instead of two separate top-level maps |
| B6.56 | Cord Blood Analysis Done | `cord_blood_done` | ✅ |
| B6.57 | Within 1hr of birth | `cord_blood_within_1hr` | ❌ add Yes/No |
| B6.58 | Source | `cord_blood_source` | ❌ add dropdown |
| B6.59 | pH / SBE / pCO2 | `cord_ph` / `cord_sbe` / `cord_pco2` | ✅ (`ph`/`be`/`pco2`, rename) |
| B6.60 | Resuscitation Failure | `resus_failure` | ✅ |
| B6.61 | SpO2 at exit | `spo2_exit_trial_gas` | ✅ (`spo2Exit`, rename) |
| B6.62 | Total Resuscitation Time | `total_resus_time` | ✅ (`_totalTimeCtrl`, rename) |
| B6.63 | Reason for Exit | `reason_exit_trial_gas` | ✅ (`exitReason`, rename) |
| B6.63 | Other reason | `reason_exit_trial_gas_other` | ✅ (`_exitOtherCtrl`, rename) |
| B6.64 | PORTAL Blender Status | `blender_stopped` | ❌ add Yes/No |
| B6.64 | Blender Stop Description | `blender_stopped_description` | ❌ add, conditional textarea |

## What's NOT in your current mobile fields at all (net-new UI needed)

- Heart Rate > 100 toggle (B3.21)
- Delivery-indication conditional detail fields ×3 (B2.18)
- SIB PEEP valve Yes/No + value (B4.29a)
- T-piece PIP/PEEP/Flow trio (B4.29b)
- Adrenaline dilution + route dropdowns (B4.36/37)
- Adrenaline cumulative dose (B4.40)
- Fluid bolus doses + cumulative (B4.42/43)
- Respiration days/hours if >MM:SS (B4.48)
- Cord blood within-1hr + source (B6.57/58)
- PORTAL Blender Status + description (B6.64)

## Wiring instructions for both screens

1. Both screens should hold a shared `BirthResuscitationData` instance —
   easiest is to load it once in `FormBBirthResuscitation` via
   `FormsApiService.instance.loadBirthResuscitation(enrollmentId)` (if editing)
   or start blank (if new), populate fields the B-screen owns, save with
   `saveBirthResuscitation(data.toJson())`, then pass the **same populated
   `data` object** forward to `FormCResuscitationDetails` (like `screeningId`
   is passed today) instead of starting Form C from scratch.
2. Form C fills in its section of the same `data` object, then calls
   `saveBirthResuscitation(data.toJson())` again — since the backend POST
   upserts by `enrollment_id`, this merges cleanly into the same row rather
   than creating a second record.
3. Delete `models/form_b.dart` and `models/form_c.dart` once both screens
   are migrated to `BirthResuscitationData` — keeping both around risks
   someone importing the stale one again.
