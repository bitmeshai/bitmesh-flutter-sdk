/// Lenient readers for API payloads.
///
/// The API evolves; these helpers accept the common variations (numbers sent as
/// strings, aliased keys, missing fields) instead of throwing.
library;

/// Returns the first non-null value among [keys].
///
/// Each key is also tried in its other casing: the API answers real requests in
/// camelCase (`finishReason`, `promptTokens`) but documents — and returns, on
/// the `test: true` debug path — snake_case (`finish_reason`, `prompt_tokens`).
/// Callers pass one spelling and get both.
Object? pick(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value != null) return value;
  }
  for (final key in keys) {
    for (final variant in caseVariants(key)) {
      final value = json[variant];
      if (value != null) return value;
    }
  }
  return null;
}

/// The snake_case and camelCase spellings of [key], excluding [key] itself.
Iterable<String> caseVariants(String key) sync* {
  if (key.contains('_')) {
    final parts = key.split('_').where((p) => p.isNotEmpty).toList();
    if (parts.length > 1) {
      yield parts.first +
          parts
              .skip(1)
              .map((p) => p[0].toUpperCase() + p.substring(1))
              .join();
    }
  } else if (key.contains(RegExp('[A-Z]'))) {
    yield key
        .replaceAllMapped(
          RegExp('[A-Z]'),
          (m) => '_${m.group(0)!.toLowerCase()}',
        )
        .replaceAll(RegExp('^_'), '');
  }
}

String? asString(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

int? asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? asDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

bool? asBool(Object? value) {
  if (value == null) return null;
  if (value is bool) return value;
  final text = value.toString().toLowerCase();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return null;
}

Map<String, dynamic>? asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return null;
}

List<Map<String, dynamic>> asMapList(Object? value) {
  if (value is! List) return const [];
  return value
      .map(asMap)
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
}

List<String> asStringList(Object? value) {
  if (value is String) return [value];
  if (value is! List) return const [];
  return value
      .map(asString)
      .whereType<String>()
      .toList(growable: false);
}

/// Parses ISO-8601 strings and unix timestamps (seconds or milliseconds).
DateTime? asDateTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is num) {
    final asMillis = value > 100000000000 ? value.toInt() : value.toInt() * 1000;
    return DateTime.fromMillisecondsSinceEpoch(asMillis, isUtc: true);
  }
  final text = value.toString();
  final numeric = int.tryParse(text);
  if (numeric != null) return asDateTime(numeric);
  return DateTime.tryParse(text);
}

/// Drops null values so optional request fields are simply omitted.
Map<String, dynamic> compact(Map<String, dynamic> json) {
  final result = <String, dynamic>{};
  json.forEach((key, value) {
    if (value != null) result[key] = value;
  });
  return result;
}
