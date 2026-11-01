// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$JsonData {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonData);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'JsonData()';
}


}

/// @nodoc
class $JsonDataCopyWith<$Res>  {
$JsonDataCopyWith(JsonData _, $Res Function(JsonData) __);
}


/// Adds pattern-matching-related methods to [JsonData].
extension JsonDataPatterns on JsonData {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( JsonData_Null value)?  null_,TResult Function( JsonData_Bool value)?  bool,TResult Function( JsonData_Integer value)?  integer,TResult Function( JsonData_Unsigned value)?  unsigned,TResult Function( JsonData_Number value)?  number,TResult Function( JsonData_String value)?  string,TResult Function( JsonData_Array value)?  array,TResult Function( JsonData_Object value)?  object,required TResult orElse(),}){
final _that = this;
switch (_that) {
case JsonData_Null() when null_ != null:
return null_(_that);case JsonData_Bool() when bool != null:
return bool(_that);case JsonData_Integer() when integer != null:
return integer(_that);case JsonData_Unsigned() when unsigned != null:
return unsigned(_that);case JsonData_Number() when number != null:
return number(_that);case JsonData_String() when string != null:
return string(_that);case JsonData_Array() when array != null:
return array(_that);case JsonData_Object() when object != null:
return object(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( JsonData_Null value)  null_,required TResult Function( JsonData_Bool value)  bool,required TResult Function( JsonData_Integer value)  integer,required TResult Function( JsonData_Unsigned value)  unsigned,required TResult Function( JsonData_Number value)  number,required TResult Function( JsonData_String value)  string,required TResult Function( JsonData_Array value)  array,required TResult Function( JsonData_Object value)  object,}){
final _that = this;
switch (_that) {
case JsonData_Null():
return null_(_that);case JsonData_Bool():
return bool(_that);case JsonData_Integer():
return integer(_that);case JsonData_Unsigned():
return unsigned(_that);case JsonData_Number():
return number(_that);case JsonData_String():
return string(_that);case JsonData_Array():
return array(_that);case JsonData_Object():
return object(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( JsonData_Null value)?  null_,TResult? Function( JsonData_Bool value)?  bool,TResult? Function( JsonData_Integer value)?  integer,TResult? Function( JsonData_Unsigned value)?  unsigned,TResult? Function( JsonData_Number value)?  number,TResult? Function( JsonData_String value)?  string,TResult? Function( JsonData_Array value)?  array,TResult? Function( JsonData_Object value)?  object,}){
final _that = this;
switch (_that) {
case JsonData_Null() when null_ != null:
return null_(_that);case JsonData_Bool() when bool != null:
return bool(_that);case JsonData_Integer() when integer != null:
return integer(_that);case JsonData_Unsigned() when unsigned != null:
return unsigned(_that);case JsonData_Number() when number != null:
return number(_that);case JsonData_String() when string != null:
return string(_that);case JsonData_Array() when array != null:
return array(_that);case JsonData_Object() when object != null:
return object(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  null_,TResult Function( bool value)?  bool,TResult Function( PlatformInt64 value)?  integer,TResult Function( BigInt value)?  unsigned,TResult Function( double value)?  number,TResult Function( String value)?  string,TResult Function( List<JsonData> values)?  array,TResult Function( List<JsonEntry> entries)?  object,required TResult orElse(),}) {final _that = this;
switch (_that) {
case JsonData_Null() when null_ != null:
return null_();case JsonData_Bool() when bool != null:
return bool(_that.value);case JsonData_Integer() when integer != null:
return integer(_that.value);case JsonData_Unsigned() when unsigned != null:
return unsigned(_that.value);case JsonData_Number() when number != null:
return number(_that.value);case JsonData_String() when string != null:
return string(_that.value);case JsonData_Array() when array != null:
return array(_that.values);case JsonData_Object() when object != null:
return object(_that.entries);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  null_,required TResult Function( bool value)  bool,required TResult Function( PlatformInt64 value)  integer,required TResult Function( BigInt value)  unsigned,required TResult Function( double value)  number,required TResult Function( String value)  string,required TResult Function( List<JsonData> values)  array,required TResult Function( List<JsonEntry> entries)  object,}) {final _that = this;
switch (_that) {
case JsonData_Null():
return null_();case JsonData_Bool():
return bool(_that.value);case JsonData_Integer():
return integer(_that.value);case JsonData_Unsigned():
return unsigned(_that.value);case JsonData_Number():
return number(_that.value);case JsonData_String():
return string(_that.value);case JsonData_Array():
return array(_that.values);case JsonData_Object():
return object(_that.entries);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  null_,TResult? Function( bool value)?  bool,TResult? Function( PlatformInt64 value)?  integer,TResult? Function( BigInt value)?  unsigned,TResult? Function( double value)?  number,TResult? Function( String value)?  string,TResult? Function( List<JsonData> values)?  array,TResult? Function( List<JsonEntry> entries)?  object,}) {final _that = this;
switch (_that) {
case JsonData_Null() when null_ != null:
return null_();case JsonData_Bool() when bool != null:
return bool(_that.value);case JsonData_Integer() when integer != null:
return integer(_that.value);case JsonData_Unsigned() when unsigned != null:
return unsigned(_that.value);case JsonData_Number() when number != null:
return number(_that.value);case JsonData_String() when string != null:
return string(_that.value);case JsonData_Array() when array != null:
return array(_that.values);case JsonData_Object() when object != null:
return object(_that.entries);case _:
  return null;

}
}

}

/// @nodoc


class JsonData_Null extends JsonData {
  const JsonData_Null(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonData_Null);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'JsonData.null_()';
}


}




/// @nodoc


class JsonData_Bool extends JsonData {
  const JsonData_Bool({required this.value}): super._();
  

 final  bool value;

/// Create a copy of JsonData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JsonData_BoolCopyWith<JsonData_Bool> get copyWith => _$JsonData_BoolCopyWithImpl<JsonData_Bool>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonData_Bool&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'JsonData.bool(value: $value)';
}


}

/// @nodoc
abstract mixin class $JsonData_BoolCopyWith<$Res> implements $JsonDataCopyWith<$Res> {
  factory $JsonData_BoolCopyWith(JsonData_Bool value, $Res Function(JsonData_Bool) _then) = _$JsonData_BoolCopyWithImpl;
@useResult
$Res call({
 bool value
});




}
/// @nodoc
class _$JsonData_BoolCopyWithImpl<$Res>
    implements $JsonData_BoolCopyWith<$Res> {
  _$JsonData_BoolCopyWithImpl(this._self, this._then);

  final JsonData_Bool _self;
  final $Res Function(JsonData_Bool) _then;

/// Create a copy of JsonData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(JsonData_Bool(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class JsonData_Integer extends JsonData {
  const JsonData_Integer({required this.value}): super._();
  

 final  PlatformInt64 value;

/// Create a copy of JsonData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JsonData_IntegerCopyWith<JsonData_Integer> get copyWith => _$JsonData_IntegerCopyWithImpl<JsonData_Integer>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonData_Integer&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'JsonData.integer(value: $value)';
}


}

/// @nodoc
abstract mixin class $JsonData_IntegerCopyWith<$Res> implements $JsonDataCopyWith<$Res> {
  factory $JsonData_IntegerCopyWith(JsonData_Integer value, $Res Function(JsonData_Integer) _then) = _$JsonData_IntegerCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 value
});




}
/// @nodoc
class _$JsonData_IntegerCopyWithImpl<$Res>
    implements $JsonData_IntegerCopyWith<$Res> {
  _$JsonData_IntegerCopyWithImpl(this._self, this._then);

  final JsonData_Integer _self;
  final $Res Function(JsonData_Integer) _then;

/// Create a copy of JsonData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(JsonData_Integer(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class JsonData_Unsigned extends JsonData {
  const JsonData_Unsigned({required this.value}): super._();
  

 final  BigInt value;

/// Create a copy of JsonData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JsonData_UnsignedCopyWith<JsonData_Unsigned> get copyWith => _$JsonData_UnsignedCopyWithImpl<JsonData_Unsigned>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonData_Unsigned&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'JsonData.unsigned(value: $value)';
}


}

/// @nodoc
abstract mixin class $JsonData_UnsignedCopyWith<$Res> implements $JsonDataCopyWith<$Res> {
  factory $JsonData_UnsignedCopyWith(JsonData_Unsigned value, $Res Function(JsonData_Unsigned) _then) = _$JsonData_UnsignedCopyWithImpl;
@useResult
$Res call({
 BigInt value
});




}
/// @nodoc
class _$JsonData_UnsignedCopyWithImpl<$Res>
    implements $JsonData_UnsignedCopyWith<$Res> {
  _$JsonData_UnsignedCopyWithImpl(this._self, this._then);

  final JsonData_Unsigned _self;
  final $Res Function(JsonData_Unsigned) _then;

/// Create a copy of JsonData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(JsonData_Unsigned(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class JsonData_Number extends JsonData {
  const JsonData_Number({required this.value}): super._();
  

 final  double value;

/// Create a copy of JsonData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JsonData_NumberCopyWith<JsonData_Number> get copyWith => _$JsonData_NumberCopyWithImpl<JsonData_Number>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonData_Number&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'JsonData.number(value: $value)';
}


}

/// @nodoc
abstract mixin class $JsonData_NumberCopyWith<$Res> implements $JsonDataCopyWith<$Res> {
  factory $JsonData_NumberCopyWith(JsonData_Number value, $Res Function(JsonData_Number) _then) = _$JsonData_NumberCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$JsonData_NumberCopyWithImpl<$Res>
    implements $JsonData_NumberCopyWith<$Res> {
  _$JsonData_NumberCopyWithImpl(this._self, this._then);

  final JsonData_Number _self;
  final $Res Function(JsonData_Number) _then;

/// Create a copy of JsonData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(JsonData_Number(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class JsonData_String extends JsonData {
  const JsonData_String({required this.value}): super._();
  

 final  String value;

/// Create a copy of JsonData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JsonData_StringCopyWith<JsonData_String> get copyWith => _$JsonData_StringCopyWithImpl<JsonData_String>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonData_String&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'JsonData.string(value: $value)';
}


}

/// @nodoc
abstract mixin class $JsonData_StringCopyWith<$Res> implements $JsonDataCopyWith<$Res> {
  factory $JsonData_StringCopyWith(JsonData_String value, $Res Function(JsonData_String) _then) = _$JsonData_StringCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$JsonData_StringCopyWithImpl<$Res>
    implements $JsonData_StringCopyWith<$Res> {
  _$JsonData_StringCopyWithImpl(this._self, this._then);

  final JsonData_String _self;
  final $Res Function(JsonData_String) _then;

/// Create a copy of JsonData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(JsonData_String(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class JsonData_Array extends JsonData {
  const JsonData_Array({required final  List<JsonData> values}): _values = values,super._();
  

 final  List<JsonData> _values;
 List<JsonData> get values {
  if (_values is EqualUnmodifiableListView) return _values;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_values);
}


/// Create a copy of JsonData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JsonData_ArrayCopyWith<JsonData_Array> get copyWith => _$JsonData_ArrayCopyWithImpl<JsonData_Array>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonData_Array&&const DeepCollectionEquality().equals(other._values, _values));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_values));

@override
String toString() {
  return 'JsonData.array(values: $values)';
}


}

/// @nodoc
abstract mixin class $JsonData_ArrayCopyWith<$Res> implements $JsonDataCopyWith<$Res> {
  factory $JsonData_ArrayCopyWith(JsonData_Array value, $Res Function(JsonData_Array) _then) = _$JsonData_ArrayCopyWithImpl;
@useResult
$Res call({
 List<JsonData> values
});




}
/// @nodoc
class _$JsonData_ArrayCopyWithImpl<$Res>
    implements $JsonData_ArrayCopyWith<$Res> {
  _$JsonData_ArrayCopyWithImpl(this._self, this._then);

  final JsonData_Array _self;
  final $Res Function(JsonData_Array) _then;

/// Create a copy of JsonData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? values = null,}) {
  return _then(JsonData_Array(
values: null == values ? _self._values : values // ignore: cast_nullable_to_non_nullable
as List<JsonData>,
  ));
}


}

/// @nodoc


class JsonData_Object extends JsonData {
  const JsonData_Object({required final  List<JsonEntry> entries}): _entries = entries,super._();
  

 final  List<JsonEntry> _entries;
 List<JsonEntry> get entries {
  if (_entries is EqualUnmodifiableListView) return _entries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_entries);
}


/// Create a copy of JsonData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JsonData_ObjectCopyWith<JsonData_Object> get copyWith => _$JsonData_ObjectCopyWithImpl<JsonData_Object>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonData_Object&&const DeepCollectionEquality().equals(other._entries, _entries));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_entries));

@override
String toString() {
  return 'JsonData.object(entries: $entries)';
}


}

/// @nodoc
abstract mixin class $JsonData_ObjectCopyWith<$Res> implements $JsonDataCopyWith<$Res> {
  factory $JsonData_ObjectCopyWith(JsonData_Object value, $Res Function(JsonData_Object) _then) = _$JsonData_ObjectCopyWithImpl;
@useResult
$Res call({
 List<JsonEntry> entries
});




}
/// @nodoc
class _$JsonData_ObjectCopyWithImpl<$Res>
    implements $JsonData_ObjectCopyWith<$Res> {
  _$JsonData_ObjectCopyWithImpl(this._self, this._then);

  final JsonData_Object _self;
  final $Res Function(JsonData_Object) _then;

/// Create a copy of JsonData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? entries = null,}) {
  return _then(JsonData_Object(
entries: null == entries ? _self._entries : entries // ignore: cast_nullable_to_non_nullable
as List<JsonEntry>,
  ));
}


}

// dart format on
