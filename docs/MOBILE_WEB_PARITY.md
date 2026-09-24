# Mobile ↔ Web form parity audit

**Date:** 2026-09-21 (Phase 0) · **Updated:** 2026-09-21 (Phase 1 item 3 — DMS 5.7.A)  
**Web (canonical):** `Portal_FInal` — React `frontend-app` + FastAPI/PostgreSQL  
**Mobile:** `PORTAL_APP-main` (Flutter)  
**Rule:** web serials, labels, options, validations, logic, and lock/edit rules are source of truth. Backend contracts are not changed in this phase.

Phase 1 in progress. Rows marked **RESOLVED** were fixed on mobile to match web. Helper day-strip still last-7 (item 3 remainder).

---

## How to read Status

| Status | Meaning |
|---|---|
| MATCH | Same serial, label, JSON key, type, options, validation, logic, save |
| LABEL | Same key/behaviour; wording or numbering differs |
| KEY | JSON key missing, extra, or different |
| TYPE | Stored type, option strings, or UI control differs |
| VALIDATION | Range / required / regex differs |
| LOGIC | Show/hide, auto-fill, skip, lock, or day-window differs |
| MISSING_ON_MOBILE | Web has it; Flutter has no screen or no field |
| EXTRA_ON_MOBILE | Flutter has it; web does not |

---

## Inventory vs web sidebar

Canonical order from `frontend-app/src/config/formsConfig.js` (and `SidebarFormProgress.jsx`).

| # | Web sidebar | Web file / table / API | Mobile screen | Presence |
|---|---|---|---|---|
| 1 | Form A – Screening | `ScreeningForm.jsx` · `screenings` · POST/PUT `/screenings/` | `lib/screens/screening_form.dart` | Both |
| 2 | Form B – Birth & Resuscitation | `BirthResuscitationForm.jsx` · `birth_resuscitation` · POST/PUT `/birth-resuscitation/` | B1 `form_b_birth_resuscitation.dart` + B2 `form_c_resuscitation.dart` | Both (split UI) |
| 3 | Form C – Maternal Details | `FormC.jsx` · `maternal_details` · `/maternal-details/` | **None** (`form_c_resuscitation.dart` is Form B2) | Web only |
| 4 | Form D – Postnatal Day 1 | `FormD.jsx` · `postnatal_day1` | **None** | Web only |
| 5 | Form E – NICU Admission | `FormE.jsx` · `nicu_admission` | **None** (helpers only GET `/nicu-admission/{eid}/day1-date`) | Web only |
| 6 | Form F – Cranial USG | `FormF.jsx` · `cranial_usg_records` · `/form-h/` (historical path) | **None** | Web only |
| 7 | Form G – ROP Screening | `FormG.jsx` · `rop_screening` · `/rop-screening/` | **None** | Web only |
| 8 | Form H – Morbidities | `FormH.jsx` · `neonatal_morbidities` | **None** | Web only |
| 9 | Form I – Study Outcomes | `FormI.jsx` · `study_outcomes` · `/study-outcomes/` | **None** | Web only |
| 10 | Form J – External Hospital Outcomes | `FormJ.jsx` · `external_hospital_assessments` | **None** | Web only |
| 11 | Form K – MRI Brain Assessment | `FormK.jsx` · `mri_brain_assessments` · `/form-k/` | **None** | Web only |
| 12 | Form L – Blender Data & Summary | `FormL.jsx` · `blender_study_summaries` · `/form-l/` | **None** | Web only |
| H1 | Daily Monitoring Sheet (DMS) | `MinimalMonitoringLog.jsx` · PUT `/minimal-monitoring/{eid}/on/{ymd}` | `helper_form5_minimal_monitoring.dart` | Both |
| H2 | Helper 2 – Resp / CV / Neuro | `RespCVNeuroLog.jsx` · `/resp-cv-neuro/` | `helper_form2_resp_cv_neuro.dart` | Both |
| H3 | Helper 3 – FiO₂ Logging | `FiO2AUC.jsx` · PUT `/fio2-auc/{eid}` | `helper_fio2_auc.dart` | Both |
| H4 | Helper 4 – Infect / GI / Hema | `InfectGIHemaLog.jsx` · `/infect-gi-hema/` | `helper_form3_infect_gi_hema.dart` (**class name Helper 3**) | Both |
| H5 | Helper 5 – Metab / Renal / Eye | `MetabRenalVascEyeLog.jsx` · `/metab-renal-vasc-eye/` | `helper_form4_metab_renal_vasc_eye.dart` (**class name Helper 4**) | Both |
| Y | Form Y – SAE | `FormY_SAE.jsx` | **None** | Web only |
| AE | Helper – Adverse Events | `AdverseEventsForm.jsx` · `/adverse-events/` | **None** | Web only |
| SAE | Helper – SAE Listing | `SeriousAdverseEventsList.jsx` · `/sae-list/` | **None** | Web only |

Web-only (not CRF): Dashboard, View Entries, Manage Staff, Trial Monitoring, Audit Trail, Helper Form Records. Mobile has role dashboards + user management (admin) instead.

---

## Naming traps (read before Phase 1)

1. **Web Form A = Screening.** There is no separate “Screening” form besides Form A.
2. **Web Form B is one page (B1–B6).** Mobile splits B1 (identification–randomisation) and B2 (resuscitation–exit). B2 file is named `form_c_resuscitation.dart` and local model `form_c.dart` — **not** web Form C.
3. **Web Form C = Maternal Details** (`maternal_details`). Completely missing on mobile. Dashboard already tells nurses to finish it on web.
4. **Mobile helper class numbers are off by one vs sidebar:**  
   DMS = `helper_form5_*` · Infect = `HelperForm3*` (web Helper 4) · Metab = `HelperForm4*` (web Helper 5).
5. **Form F lives at `/form-h/`** for historical reasons. Live Form H is `/neonatal-morbidities/`.
6. **Form G / I swap:** live web matches canonical sidebar (**G = ROP, I = Outcomes**). Stale comment in `backend/main.py` still says “FORM G – STUDY OUTCOMES” on the Form I route. Mobile has neither screen, so **no swap to fix on mobile**.

---

## Cross-cutting: stale-write / concurrent edit

Web: `frontend-app/src/utils/staleWrite.js`  
Backend: `backend/concurrent_writes.py` (`assert_fresh_write`, 409 `stale_write`)

| Surface | `expected_updated_at` | 409 behaviour | Notes |
|---|---|---|---|
| Form A `/screenings/` | No | Last-write-wins | No `updated_at` compare |
| Form B `/birth-resuscitation/` | No | Last-write-wins | Table has `created_at` only; 409 is duplicate UID/enrollment, not stale_write |
| Forms C–L | Not audited as mobile-missing | — | Phase 1 only if those screens are built |
| Helper 2 / 4 / 5 day PUT | **Yes (web + mobile)** | Reload day + message | MATCH |
| DMS | No | Server **merges** `entries_json` | MATCH (by design) |
| FiO₂ | No | Server **merges** logs by `(day, block)` | MATCH (by design) |
| AE / SAE | No helper lock | MISSING_ON_MOBILE | — |

Mobile helper 409: show `e.message`, reload day. Web: `STALE_WRITE_MESSAGE` + reload nonce.

---

## 1. Form A – Screening

**Save:** POST `/screenings/` create, PUT `/screenings/{screening_id}` update. PII via same payload then `participant_pii`. Status is server `compute_screening_status`. Draft = omit `explicitly_saved`. Save = `explicitly_saved: true`.

REST keys are snake_case (`_buildSyncPayload` / `buildPayloadFrom`). Flutter `CRF.toJson()` camelCase is **device/PDF only**.

| Serial | Web label | Mobile label | JSON key | Type / options | Validation | Logic | Save | Status |
|---|---|---|---|---|---|---|---|---|
| 1 | Gestation in weeks clearly mentioned * | Same | `gestation_known` | Yes / No | Required on Save | Clears method/LMP/EDD/weeks | POST/PUT `/screenings/` | MATCH |
| 2 | Best estimate GA — Weeks * | Same | `gestation_weeks` | int | **25–31 weeks (25w0d–31w6d with days 0–6)** | Out of window (LMP/EDD auto-GA) still hides A2–A5 | Same | MATCH |
| 3 | Days * | Same | `gestation_days` | 0–6 | Both 0–6 | — | Same | MATCH |
| 4 | Method of gestation assessment * | Same | `gestation_method` | LMP / Early USG / Fundal Height / Unknown | Required if Q1=Yes | Clears LMP/EDD | Same | MATCH |
| 5–6 | LMP * + EDD auto | Same | `lmp_date`, `expected_delivery_date` | YYYY-MM-DD | LMP required if method=LMP; max today | EDD = LMP+280 | Same | MATCH |
| 7 | If No, is any of the following known? * | Same | `ga_source` | LMP / EDD / Neither | Required if Q1=No | Neither → Screen Failure | Same | MATCH |
| 8–10 | LMP / EDD / calculated GA on No path | Same | same date + weeks/days | — | Required per source | **GA as-of `screening_datetime` on both. Load keeps stored weeks (no overwrite).** | Same | RESOLVED (was LOGIC) |
| 11 | Calculated gestational age (auto) | Same | stored weeks/days (no extra key) | display N weeks ; D days | Read-only | Anchored to screening_datetime; not recomputed on load | Same | RESOLVED (was LOGIC) |
| 12 | Screening ID (auto) | Same | `screening_id` | `01-0007` | Not editable | Server `generate_screening_id`. Mobile offline `01-LOCAL-0001` | POST omit; PUT include | LOGIC (offline extra; keep) |
| 13 | Site * | Same | `site_name` | PGIMER, GMCH, IOG, AFMC, GMCH-A, AMC | Required | JWT lock. Superadmin + scientist with no site unlocked (web project_scientist / superadmin). `superadmin` JWT maps to admin. | Same | RESOLVED (was LOGIC) |
| 14 | Site ID (auto) | Same | `site_id` | 01–06 | Read-only | Server overwrites from site_name | Same | MATCH |
| 15 | Screening Date & Time * | Same | `screening_datetime` | ISO; display dd-MM-yyyy HH:mm | Required; not future | **Defaults to now on new/empty draft (web). GA as-of this value.** Load of existing keeps stored datetime. | Same | RESOLVED (was LOGIC) |
| 16 | Screened by * | Same | `screened_by` | roster GET `/sites/{site}/screeners` | Required | Autofill JWT name only if on roster | Draft web `"DRAFT"` | MATCH |
| 17–18 | Mother first * / surname | Same | `mother_first_name`, `mother_surname` | PII | First required; letters | Duplicate-name warning (mobile uses `/pii/batch`) | Same | MATCH |
| 19–20 | Husband first * / surname | Same | `husband_first_name`, `husband_surname` | PII | First required | — | Same | MATCH |
| 21 | Maternal UID (CR number) | Same | `maternal_uid` | PII | PGIMER 12 digits required; AMC `n/yyyy` required; others optional | Site regex match | Same | MATCH |
| 22 | Hospital Admission Number | Same | `hospital_admission_number` | PII | Site patterns. **PGIMER optional on both (format still 10 digits if filled)** | — | Same | RESOLVED (was VALIDATION) |
| 23–24 | Mobile mother * / husband * | Same | `mother_contact`, `husband_contact` | 10 digits, `^[6-9]` | Indian mobile both sides | Strip non-digits | Same | MATCH |
| 25–34 | Exclusions 18–25 (anomaly, hydrops, forego resus, insufficient time, IUFD) | Same tokens | `exclusion_present`, `exclusion_reasons`, detail keys | Yes/No + specify / multi | Required when A4 visible | Any Yes → Screen Failure, skip consent | Same | MATCH |
| 35 | (derived) exclusion_reasons | same | `exclusion_reasons` | comma list | — | **All-No → null on both** | PUT | RESOLVED (was TYPE) |
| 36–42 | Consent 26–30 | Same | `consent_given`, relationship, refusal, not approached, `consent_taken_by` | Yes / No / Trial run / Not approached | Required if no exclusion | Hide A5 if exclusion Yes | Same | MATCH |
| 43 | Video PIS shown * | Same | `video_pis_shown` | Yes/No | Required if any consent value | — | Same | MATCH |
| 44–46 | ICF signature + timestamp | Same | `consent_signature_image`, `consent_signature_captured_at` | PNG data URL | Required if Yes/No/Trial run | **Web pad onChange. Mobile must tap Save Signature** | Same keys | LOGIC |
| 47 | PIS English/Hindi/Punjabi | Same | not stored | PDF links | Punjabi PGIMER+GMCH only | Mobile also ships assets | N/A | MATCH |
| 48–50 | Hidden consent version/language/datetime | Hidden | `consent_form_version` v1.0, `consent_language` English, `consent_datetime` | — | — | Always sent when consent active | MATCH |
| 51 | explicitly_saved | Hidden | `explicitly_saved` | bool | — | Save true; draft omit. **Ineligible GA Save now sets true (web)** | Same | RESOLVED (was LOGIC) |
| 52 | Notes | Notes | local `notes_form_a_{id}` | not API | 500 chars | Device-local | MATCH |
| 53 | QR scan CR | Scan | writes `maternal_uid` | — | — | Web has no scanner | EXTRA_ON_MOBILE |

**Highest-impact Form A mismatches (Phase 1 items 1–2)**

All five original items are RESOLVED on mobile: GA as-of `screening_datetime`, direct GA **25w0d–31w6d** (same as web), PGIMER HAN optional, ineligible-GA Save sets `explicitly_saved`, JWT `superadmin`→admin / scientist-with-no-site unlocked.

Still open on Form A (not data-wipe): serial 12 offline local IDs; serial 44–46 ICF pad requires tap **Save Signature** (web writes on stroke).

---

## 2. Form B – Birth & Resuscitation

**Web:** one form B1–B6. **Mobile:** B1 then B2 (file misnamed Form C). **Same table and POST `/birth-resuscitation/` upsert.** PUT exists; mobile B1/B2 usually POST. Nulls **do not clear** columns (`if value is None: continue`). No `expected_updated_at`.

Not-randomised / no-PPV: enrollment `NR-{screening_id}` on both.

| Serial | Web label | Mobile label | JSON key | Type / options | Validation | Logic | Save | Status |
|---|---|---|---|---|---|---|---|---|
| 1 | Screening ID (RO) | Same | `screening_id` | string | — | From Form A | Both | MATCH |
| 2 | Maternal UID (RO) | Same (display) | `maternal_uid` | string | — | Form A PII | **Sent when non-empty; omitted when empty so web values are not wiped** | RESOLVED (was KEY) |
| 3 | Mother's First Name (RO) | First name only (not concatenated) | `mother_name_first`, `mother_name_surname` | string | — | Form A PII | **Both keys sent when non-empty** | RESOLVED (was KEY + LABEL) |
| 5 | Mobile mother/husband (RO) | Same display | `contact_mother`, `contact_husband` | string | — | Form A PII | **Sent when non-empty** | RESOLVED (was KEY) |
| 4 | Baby UID | Same | `baby_uid` | 1–12 digits | Live GET `/check-baby-uid`; 409 on save | Same-site unique | Both | MATCH |
| 6 | Site-specific admission / MRD | Same maps | `baby_admission_no` | digits min–max | Optional if empty; IOG RO = UID | PGIMER 10; GMCH 9–11; GMCH-A 4–6; IOG 4–6; AMC 11 | MATCH |
| 7 | Annual / SNCU / logbook | Same hide rules | `baby_annual_no` | PGIMER/IOG 4 digits; AMC ≤20 text | Hidden GMCH/GMCH-A/AFMC | Both | MATCH |
| 8–9 | DOB * / TOB * | Same | `date_of_birth`, `time_of_birth` | YYYY-MM-DD, HH:MM:SS | Not future; birth ≥ screening datetime | Min date = screening day | MATCH |
| 10 | Gender * | Same | `gender` | Female / Male / DSD | Required | INTERGROWTH | MATCH |
| 11 | Gestation at Screening (RO) | Same | `gestation_weeks`, `gestation_days` | 18–42 / 0–6 | From Form A | MATCH |
| 12 | Gestation at Randomization (auto) | Same | `gestation_rand_weeks`, `gestation_rand_days` | screening + (DOB−screen) | Not screening-GA fallback | MATCH |
| 13–14 | Birth weight * / intrauterine centile auto | Same | `birth_weight`, `intrauterine_centile` | 300–6000 g; centile or `"<3rd centile"` | INTERGROWTH 24+0–32+6 | MATCH |
| 15–18 | Delivery mode / vaginal / LSCS / indications | Same | `delivery_mode`, `vaginal_delivery_type`, `lscs_type`, `indication_for_delivery` (+ `_other`) | Vaginal/LSCS; multi comma | ≥1 indication; Other text | MATCH |
| 19–21 | Resp effort / tone / HR <100 | Same | `poor_resp_efforts`, `poor_muscle_tone`, `hr_above_100` | bool; Q21 inverted | All-normal gate | MATCH |
| 22 | Initial steps | Same | `initial_steps` | bool | Hidden if all-normal; No → Q23 No | MATCH |
| 23 | Did baby require respiratory support for resuscitation (T-piece CPAP or PPV)? | Same | `required_resuscitation` | bool | Required if Q22 Required | Yes → randomise; No → hide B4–B6 / skip B2 | RESOLVED (was LABEL) |
| — | (derived) | same | `ppv_required` | bool | Q23 Yes ⇒ true | MATCH |
| 24–28 | Randomised / date / enrollment ID / strata / reason not randomised | Same | `randomised`, `randomisation_date`, `enrollment_id`, `strata`, `enrollment_reason_not_randomized` | ID `^\d{2}-[A-D]-\d{3}$` | Duplicate GET `/check-enrollment-id`; NR- if not randomised / no PPV | MATCH |
| 29–42 | B4 device, PEEP/PIP/flow, interface, PPV dur, intubation, CC, epinephrine, fluid, placental transfusion, cord clamp | Same options | matching snake_case | T-piece / SIB / Both; interface Mask/LMA/ETT | Required on B4 path | Mobile B2 only | MATCH (SIB/T-piece 0–3 digit ints on both) |
| 36 | Dilution 1:10,000 / 1:1,000 | display commas, store `1:10000` / `1:1000` | `adrenaline_dilution` | stored without commas | Same values | RESOLVED (was LABEL) |
| 45 | Time to spontaneous respiratory efforts (seconds text) | Same | `time_to_respiration` | **int seconds** | Optional; ≤ Q57 | JSON seconds both | RESOLVED (was TYPE + LABEL) |
| 47 | Time to SpO₂ >80% (MM:SS) | MM:SS picker, stored seconds | `time_to_spo2_80` | int seconds | — | RESOLVED (was TYPE) |
| 48–50 | O₂ / CPAP / Apgar grid | Same | `interventions.oxygen/cpap/apgar` | Yes/No/NR; Apgar 0–10 | Later Apgar **not** gated | MATCH |
| 51–54 | Cord blood | Same | `cord_blood_*`, `cord_ph`, `cord_sbe`, `cord_pco2` | pH 6.8–7.8 | MATCH |
| 55 | Resuscitation failure | Same | `resus_failure` | bool | **Hides “Responded…” if Yes on both** | RESOLVED (was LOGIC) |
| 56 | SpO₂ (%) at EXIT from TRIAL BLENDER | Same | `spo2_exit_trial_gas` | 1–100 | RESOLVED (was LABEL) |
| 57 | Total time for Resuscitation (in seconds) (stores MM:SS) | Same | `total_resus_time` | string MM:SS | ≥ Q45 | RESOLVED (was LABEL) |
| 58 | Reason for resuscitation exit | Same options | `reason_exit_trial_gas` | Other folded into same key | MATCH |
| 59 | Was the TRIAL blender interrupted before 30 minutes from BIRTH? | Same | `blender_stopped` | bool | RESOLVED (was LABEL) |
| 60 | Reason * (CRF 2026-09 wording) | Same + old→new mapping on load | `blender_interrupt_reasons` | comma-joined | Maps old→new on load; saves new strings | RESOLVED (was TYPE + LOGIC) |
| 61 | Blender Unit ID A–D auto | Same | `blender_letter` | from enrollment letter | MATCH |
| — | explicitly_saved | same | `explicitly_saved` | bool | Save true; draft omit | MATCH |
| — | NotesBox | none | notes API | — | EXTRA on web (not this table) |

**Q60 strings (must match — now do)**

Both: `Blender stopped working abruptly` · `To decide need for Surfactant` · `To decide need for Intubation` · `For transfer to NICU (have to switch to routine blender)` · `Reached 21% or 100% FiO2`  
Load maps the old short labels onto these.

---

## 3. Form C – Maternal Details

**MISSING_ON_MOBILE.**

- Route `/form-c/:enrollmentId` · table `maternal_details` · GET/PUT `/maternal-details/{eid}` · POST `/maternal-details/`
- Sections: C1 Identification · C2 Obstetric history / antenatal treatment · C3 Medical disorders · C4 Obstetric problems (includes FGR) · C5 Infection · C6 Intrapartum · Completion
- Flutter `form_c_resuscitation.dart` is **Form B2**, not this form.

---

## 4. Form D – Postnatal Day 1

**MISSING_ON_MOBILE.**

- `/form-d/:eid` · `postnatal_day1` · GET/PUT/POST `/postnatal-day1/`
- D1 Identification (carried from B) · D2 Golden hour · D3 Surfactant · D4 Early respiratory support · Completion
- GA postnatal day 1 vs screening GA; NBS vs USG logic is web-only.

---

## 5. Form E – NICU Admission

**MISSING_ON_MOBILE** as a form.

- `/form-e/:eid` · `nicu_admission` · GET/PUT/POST `/nicu-admission/`
- E1 ID · E2 Admission · E3 Transport · E4 Respiratory support · Completion
- Mobile helpers only use GET `/nicu-admission/{eid}/day1-date` for DMS Day 1.

---

## 6. Form F – Cranial USG

**MISSING_ON_MOBILE.**

- UI `/form-f/:eid` · **API `/form-h/`** · table `cranial_usg_records`
- F1 scan list (Papile / De Vries grades) · F2 max IVH/cPVL, PHVD, VP shunt, other findings · brain-injury composite
- Legacy `cranial_ultrasound` unused by live Form F.

---

## 7. Form G – ROP Screening

**MISSING_ON_MOBILE.** Canonical: G = ROP (not Outcomes).

- `/form-g/:eid` · `rop_screening` · GET `/rop-screening/{eid}` · POST upsert (no PUT)
- Eligibility copy · G1 screening rows (linked from Helper 5 ROP days) · G2 treatment & outcome per eye · Completion

---

## 8. Form H – Neonatal Morbidities

**MISSING_ON_MOBILE.**

- `/form-h/:eid` · `neonatal_morbidities` · `/neonatal-morbidities/`
- H1–H12 domains (neuro through hospital course) + many helper prefill endpoints
- Hypothermia auto-trigger from logs is still TODO on web (noted previously); do not invent on mobile.

---

## 9. Form I – Study Outcomes

**MISSING_ON_MOBILE.** Canonical: I = Outcomes (not ROP).

- `/form-i/:eid` · `study_outcomes` · GET/POST upsert `/study-outcomes/`
- I.1 Resuscitation (from Form B) · I.2 Post-resus · I.3–I.5 PMA 36/40/44 · I.6 Overall · Completion
- Backend comment still says “FORM G – STUDY OUTCOMES” — web bug to report, not change in Phase 0.

---

## 10. Form J – External Hospital Outcomes

**MISSING_ON_MOBILE.** `/form-j/:eid` · `external_hospital_assessments` · POST `/external-hospital-assessment/` upsert. J.1 PMA visits · death · resp at 36w · NEC · brain injury · ROP · sepsis · MRI · Completion.

---

## 11. Form K – MRI Brain Assessment

**MISSING_ON_MOBILE.** `/form-k/:eid` · `mri_brain_assessments` · GET/POST/PUT `/form-k/` · PATCH submit.

---

## 12. Form L – Blender Data & Summary

**MISSING_ON_MOBILE.** `/form-l/:eid` · `blender_study_summaries`. Sidebar `formsConfig` label “Study Completion”; live title is blender/summary.

---

## Helper 1 – Daily Monitoring Sheet (DMS)

**Save:** PUT `/minimal-monitoring/{eid}/on/{ymd}` (and `/today?boundary_hour=8`). **No** `expected_updated_at`. Server merges `entries_json`. NICU day grace **08:00** both sides.

| Serial | Web | Mobile | JSON | Notes | Status |
|---|---|---|---|---|---|
| 5.1.A | Skin/Axillary temp, SBP, DBP, MAP | Same | `cv_a[]` | Flowsheet | MATCH |
| 5.1.B | Fluid bolus | Same | `cv_b[].fluid_bolus_given` | → Helper 2 #29 Yes | MATCH |
| 5.1.C | Vasoactive agent/dose/unit | Same | vasoactive list | → Helper 2 drugs | MATCH |
| 5.1.D | PDA agent/dose | Same | `pda_agent`, `pda_dose` | → Helper 2 hidden `pda_medical_rx` | MATCH |
| 5.2.A | Time, mode, max MAP/CPAP, max FiO₂ | Same | modes, `max_map_cpap`, secondary, `max_fio2` | **MAP/CPAP carry only CPAP↔BOTH**; invasive → ETT | MATCH |
| 5.2.B | pH, PaO₂, PaCO₂ | Same | `ph`, `pao2`, `paco2` | → Helper 2 #8–10 | MATCH |
| 5.2.C | Apnea / desat / severe desat | Same | episode ints | → Helper 2 #13–15 | MATCH |
| 5.2.D | Steroids | Same | list + dose | → Helper 2 #22 | MATCH |
| 5.3.A | Glucose mg/dL | Same | `met_a[].glucose` | High **>125**; low <45 → Helper 5 | MATCH |
| 5.3.B | ALP, Ca, P | Same | nums | MATCH |
| 5.3.C | — | Electrolyte abnormality block | `met_c[]` | Not on web | EXTRA_ON_MOBILE |
| 5.4.A | Feeds EF/NPO | Same | `gi_a[]` | → Helper 4 #13–15 | MATCH |
| 5.4.B | Direct bilirubin | Same | `direct_bilirubin` | MATCH |
| 5.5 | Neuro VI/AHW + Doppler | Same | `neuro_a` / `neuro_b` | MATCH |
| 5.6.A | Transfusions | Same | products, count, PRBC vol | Split → Helper 4 #28–30 **Yes-only** | MATCH |
| 5.7.A | Weight (g) cadence | Same | `growth_a[].weight_g` + `weight_frequency_hours` 12/24 | Feeds Helper 4 ml/kg/d | RESOLVED |

Dead mobile helper blob `POST /forms/helper/save` still in `forms_api_service.dart`; DMS screen does not use it.

---

## Helper 2 – Resp / CV / Neuro

**Save:** POST `/resp-cv-neuro/` or PUT `/{eid}/{day}?expected_updated_at=` · 409 reload. MATCH on lock.

| Serial | Web | Mobile | JSON | Notes | Status |
|---|---|---|---|---|---|
| Day strip | All NICU days (floor 14) | **Last 7** + Earlier | — | Intentional product difference previously requested | LOGIC |
| Copy previous day | Web **clears** on day change | Mobile **Copy from previous day** | — | EXTRA_ON_MOBILE |
| 2.1 Weight | Same | `weight_kg` | ±2% vs previous day warning; 200–8000 g / 0.2–8 kg | MATCH |
| 1–7 | Support, ETT, modes, MAP/CPAP, FiO₂, flow, supp O₂ | Same | matching | Invasive → ETT; CPAP↔BOTH only; supp O₂ gates FiO₂ form | MATCH |
| 4–6 status sidecar | Not Recorded on web | Missing on mobile | `*_status` | LOGIC |
| 8–10 | pH / PaO₂ / PaCO₂ | Same | ranges or Not Done | DMS one-way | MATCH |
| 11–22 | Surfactant, caffeine, apnea/desat, extub, pulm hem, PTX, drain, PPHN, steroids | Same | matching | MATCH (mobile apnea max 50 extra VALIDATION) |
| 23–29 | PDA / echo / shock / vasoactives / bolus | Same | CSV drugs; hidden `pda_medical_rx` | MATCH |
| 30–37 | USG / IVH / cPVL / ventriculomegaly / seizures / AEDs / ICH | Same | Y/N | MATCH |
| 31+ | — | IVH Grade I–IV | `ivh_grade` | Not on web Helper 2 | EXTRA_ON_MOBILE |

---

## Helper 3 – FiO₂ Logging

**Save:** PUT `/fio2-auc/{eid}` (POST fallback). Body: `total_auc`, `mean_daily_fio2`, `excess_o2_auc`, `fio2_logs[{day,block,start_time,entries:[{fio2,dur}]}]`. No stale 409; merge omitted days.

| Item | Web | Mobile | Status |
|---|---|---|---|
| Days from Helper 2 `supp_o2=Yes` | Same | MATCH |
| Blocks `0-12h` / `12-24h`, 12 hours each | Same | MATCH |
| AUC = (FiO₂/100)×hours | Same | MATCH |
| Day strip | All O₂ days | Last 7 + show earlier | LOGIC |

---

## Helper 4 – Infect / GI / Hema

Mobile class `HelperForm3InfectGIHema`. **Save:** POST/PUT + `expected_updated_at`. 409 MATCH.

| Serial | Web | Mobile | JSON | Notes | Status |
|---|---|---|---|---|---|
| 1–3 | Sepsis suspected / culture sent / positive | Same | matching + `blood_culture_status` | Result Awaited sidecar load/save/completion | RESOLVED (was LOGIC) |
| Extra | Sepsis screen rows | Same | `sepsis_screens_json` | MATCH |
| 4–9 | Antibiotics, LP, meningitis, CLABSI, VAP | Same | MATCH |
| 10–15 | NPO, MEN, feeds, type, cumulative ml, ml/kg/d | Same | `*_status` Not Recorded load/save. **#15 = cum ml ÷ effective weight** (latest 5.7.A if ≥ birth weight, else Form B `birth_weight`) | RESOLVED |
| 16–22 | IV fluids, PN, probiotic, intolerance, NEC, cholestasis | Same | MATCH |
| 23–27 | Hb, jaundice, phototherapy, TSB, exchange | Same | `hb_value_status` / `peak_tsb_status` Awaited/Not Recorded | RESOLVED (was LOGIC) |
| 28–30 | PRBC / platelets / FFP-Cryo | Same | DMS Yes-only split | MATCH |
| Day strip / copy | All days; no copy | Last 7; copy previous | LOGIC + EXTRA |

---

## Helper 5 – Metab / Renal / Eye

Mobile class `HelperForm4MetabRenalVascEye`. **Save:** POST/PUT + `expected_updated_at`. 409 MATCH.

| Serial | Web | Mobile | JSON | Notes | Status |
|---|---|---|---|---|---|
| 1–2 | Lowest glucose if <45; hypo episode count | Same | DMS 5.3.A | MATCH |
| 3 | Hypoglycemia Rx (required if low) | Same gating, shorter label | `hypoglycemia_rx` | LABEL |
| 4–5 | Highest glucose if **>125**; insulin | Same cutoff 125 | MATCH |
| 6 | Metabolic acidosis pH&lt;7.2 | Same readings JSON | Web Not Recorded | LOGIC |
| 7–9 | Na / K / iCa readings | Same | MATCH |
| 10–14 | Osteopenia, AKI, creatinine, urine 13a–c, dialysis | Same | Urine web `*_status` | LOGIC |
| 15 | Axillary temp | Same | DMS overlay | MATCH |
| 16–22 | Lines / extravasation / line cx | Same | MATCH |
| 23–25 | ROP due / screened / detected | Same | MATCH |
| — | `rop_stage` in state, **no picker** | model Stage 1–5, **no picker** | Dead both sides; format `1` vs `Stage 1` risk | TYPE (latent) |
| Plus / treatment | Same | MATCH |
| 4.6–4.7 | Location multi; survived the day | Same | MATCH |

---

## Form Y / Adverse Events / SAE Listing

**All MISSING_ON_MOBILE.**

| Form | Web API | Fields (web) |
|---|---|---|
| Form Y SAE | `/form-y-sae/` (and SAE report helpers) | Reporter, SAE narrative, ICH-GCP-style notification |
| Adverse Events | POST/PUT `/adverse-events/` | `has_adverse_event`; events[] description, definition_no, dates, grade 1–5, converted_to_sae; completed_by |
| SAE Listing | POST/PUT `/sae-list/` | rows[] sae, definition, dates, 24h/10d/resolution notify |

Mobile has no models or `forms_api_service` methods for these.

---

## Roles and site visibility

| Topic | Web | Mobile | Status |
|---|---|---|---|
| Site-scoped lists | JWT `site_name`; `ensure_same_site` | Same APIs | MATCH for screenings/helpers |
| All-sites | `superadmin`, `global_scientist` | `UserRole.admin` and `monitor` (`isGlobal`) | RESOLVED — JWT `superadmin`→admin; `project_scientist`/`global_scientist`→scientist |
| Completed-by roster | GET `/users/roster` (Mannat NULL-site = PGIMER only) | Form D–H are web-only; mobile N/A | Web-only forms |
| Can add participant | nurse + admin | `canAddParticipant` nurse + admin | MATCH |

---

## Sync risks (data already in DB)

1. Form A all-No now sends `exclusion_reasons: null` (clears). Empty-string wipe is gone.  
2. Form B Q60 old strings map to new on load; save uses new CRF wording.  
3. Form B PII keys sent when non-empty; omitted when empty so web values are not wiped.  
4. Helper 4 ml/kg/d uses DMS 5.7.A + birth-weight fallback (mobile hydrate/persist now keep `growth_a`).  
5. Concurrent Form A/B last-write-wins (no 409). Helpers 2/4/5 protected. DMS/FiO₂ merge.

---

## Phase 1 progress

Items 1–2 done (Form A, Form B, Helper 4 `*_status` sidecars). **Item 3 slice done: DMS 5.7.A Weight + Helper 4 ml/kg/d.** Day strip still last-7. No commits.

Remaining helper work (pause for review):

1. Drop 5.3.C extra **or** confirm extra is wanted.  
2. Helper 2/5 remaining status sidecars + confirm last-7 day strip is still required.  
3. Decision: port Forms C–L and AE/SAE to mobile, or keep “web only” and document in-app.

---
