import 'dart:convert';

import '../../src/rust/api/types.dart';

/// Dart JSON 值转 Rust [JsonData]；带 `toJson` 的对象按 `jsonEncode` 的规则转换。
JsonData toJsonData(Object? value) => switch (value) {
  null => const JsonData.null_(),
  final bool v => JsonData.bool(value: v),
  final int v => JsonData.integer(value: v),
  final double v => JsonData.number(value: v),
  final String v => JsonData.string(value: v),
  final List<Object?> v => JsonData.array(values: [for (final e in v) toJsonData(e)]),
  final Map<Object?, Object?> v => JsonData.object(
    entries: [
      for (final e in v.entries)
        JsonEntry(key: e.key as String, value: toJsonData(e.value)),
    ],
  ),
  _ => toJsonData(jsonDecode(jsonEncode(value))),
};

/// Rust [JsonData] 转 Dart 值，类型与 `jsonDecode` 的结果一致。
Object? fromJsonData(JsonData data) => switch (data) {
  JsonData_Null() => null,
  JsonData_Bool(:final value) => value,
  JsonData_Integer(:final value) => value,
  JsonData_Unsigned(:final value) => value.toInt(),
  JsonData_Number(:final value) => value,
  JsonData_String(:final value) => value,
  JsonData_Array(:final values) => <dynamic>[
    for (final v in values) fromJsonData(v),
  ],
  JsonData_Object(:final entries) => <String, dynamic>{
    for (final e in entries) e.key: fromJsonData(e.value),
  },
};
