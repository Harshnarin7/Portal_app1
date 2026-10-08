/// Shared Form A / Form B mobile-number labels and checks.
const String primaryMobileLabel = "17. Mobile number - Primary";
const String secondaryMobileLabel = "Mobile number - Secondary";
const String formBPrimaryMobileLabel = "5. Mobile number - Primary";
const String formBSecondaryMobileLabel = "5. Mobile number - Secondary";

const String errMobileRequired = "Required";
const String errMobileDigits = "Must be exactly 10 digits";
const String errMobileStart = "Indian mobile must start with 6, 7, 8, or 9";
const String errMobileSame =
    "Primary and secondary must not be the same number";

String? mobileNumberError(String? value, {required bool required}) {
  final text = (value ?? "").trim();
  if (text.isEmpty) return required ? errMobileRequired : null;
  if (!RegExp(r'^\d{10}$').hasMatch(text)) return errMobileDigits;
  if (!RegExp(r'^[6-9]').hasMatch(text)) return errMobileStart;
  return null;
}

/// Primary is always required. Secondary is checked only when it has a value.
({String? primary, String? secondary}) mobilePairErrors(
  String? primary,
  String? secondary,
) {
  final primaryError = mobileNumberError(primary, required: true);
  var secondaryError = mobileNumberError(secondary, required: false);
  final primaryText = (primary ?? "").trim();
  final secondaryText = (secondary ?? "").trim();
  if (primaryError == null &&
      secondaryError == null &&
      primaryText.isNotEmpty &&
      secondaryText.isNotEmpty &&
      primaryText == secondaryText) {
    secondaryError = errMobileSame;
  }
  return (primary: primaryError, secondary: secondaryError);
}
