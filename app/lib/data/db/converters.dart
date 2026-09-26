import 'dart:convert';

import 'package:drift/drift.dart';

/// Stores a Postgres `jsonb` object as JSON text.
class JsonObjectConverter extends TypeConverter<Map<String, Object?>, String> {
  const new();

  @override
  Map<String, Object?> fromSql(String fromDb) =>
      jsonDecode(fromDb) as Map<String, Object?>;

  @override
  String toSql(Map<String, Object?> value) => jsonEncode(value);
}

/// Stores a Postgres `jsonb` array as JSON text.
class JsonArrayConverter extends TypeConverter<List<Object?>, String> {
  const new();

  @override
  List<Object?> fromSql(String fromDb) => jsonDecode(fromDb) as List<Object?>;

  @override
  String toSql(List<Object?> value) => jsonEncode(value);
}

/// Stores a Postgres `text[]` or `uuid[]` as a JSON array of strings.
class StringListConverter extends TypeConverter<List<String>, String> {
  const new();

  @override
  List<String> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as List<Object?>).cast<String>();

  @override
  String toSql(List<String> value) => jsonEncode(value);
}
