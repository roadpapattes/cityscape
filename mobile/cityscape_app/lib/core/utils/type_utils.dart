// lib/core/utils/type_utils.dart

/// Converts a dynamic value to int with optional fallback
int asInt(dynamic v, [int? fallback]) {
  if (v == null) return fallback ?? 0;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? (fallback ?? 0);
}

/// Converts a dynamic value to double with fallback
double asDouble(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? fallback;
}
