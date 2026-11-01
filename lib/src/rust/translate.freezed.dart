// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'translate.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TranslationEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TranslationEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TranslationEvent()';
}


}

/// @nodoc
class $TranslationEventCopyWith<$Res>  {
$TranslationEventCopyWith(TranslationEvent _, $Res Function(TranslationEvent) __);
}


/// Adds pattern-matching-related methods to [TranslationEvent].
extension TranslationEventPatterns on TranslationEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TranslationEvent_Result value)?  result,TResult Function( TranslationEvent_Progress value)?  progress,TResult Function( TranslationEvent_Failure value)?  failure,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TranslationEvent_Result() when result != null:
return result(_that);case TranslationEvent_Progress() when progress != null:
return progress(_that);case TranslationEvent_Failure() when failure != null:
return failure(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TranslationEvent_Result value)  result,required TResult Function( TranslationEvent_Progress value)  progress,required TResult Function( TranslationEvent_Failure value)  failure,}){
final _that = this;
switch (_that) {
case TranslationEvent_Result():
return result(_that);case TranslationEvent_Progress():
return progress(_that);case TranslationEvent_Failure():
return failure(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TranslationEvent_Result value)?  result,TResult? Function( TranslationEvent_Progress value)?  progress,TResult? Function( TranslationEvent_Failure value)?  failure,}){
final _that = this;
switch (_that) {
case TranslationEvent_Result() when result != null:
return result(_that);case TranslationEvent_Progress() when progress != null:
return progress(_that);case TranslationEvent_Failure() when failure != null:
return failure(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String hash,  String text)?  result,TResult Function( BigInt completed,  BigInt total)?  progress,TResult Function( String hash,  ErrorCode code)?  failure,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TranslationEvent_Result() when result != null:
return result(_that.hash,_that.text);case TranslationEvent_Progress() when progress != null:
return progress(_that.completed,_that.total);case TranslationEvent_Failure() when failure != null:
return failure(_that.hash,_that.code);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String hash,  String text)  result,required TResult Function( BigInt completed,  BigInt total)  progress,required TResult Function( String hash,  ErrorCode code)  failure,}) {final _that = this;
switch (_that) {
case TranslationEvent_Result():
return result(_that.hash,_that.text);case TranslationEvent_Progress():
return progress(_that.completed,_that.total);case TranslationEvent_Failure():
return failure(_that.hash,_that.code);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String hash,  String text)?  result,TResult? Function( BigInt completed,  BigInt total)?  progress,TResult? Function( String hash,  ErrorCode code)?  failure,}) {final _that = this;
switch (_that) {
case TranslationEvent_Result() when result != null:
return result(_that.hash,_that.text);case TranslationEvent_Progress() when progress != null:
return progress(_that.completed,_that.total);case TranslationEvent_Failure() when failure != null:
return failure(_that.hash,_that.code);case _:
  return null;

}
}

}

/// @nodoc


class TranslationEvent_Result extends TranslationEvent {
  const TranslationEvent_Result({required this.hash, required this.text}): super._();
  

 final  String hash;
 final  String text;

/// Create a copy of TranslationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TranslationEvent_ResultCopyWith<TranslationEvent_Result> get copyWith => _$TranslationEvent_ResultCopyWithImpl<TranslationEvent_Result>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TranslationEvent_Result&&(identical(other.hash, hash) || other.hash == hash)&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,hash,text);

@override
String toString() {
  return 'TranslationEvent.result(hash: $hash, text: $text)';
}


}

/// @nodoc
abstract mixin class $TranslationEvent_ResultCopyWith<$Res> implements $TranslationEventCopyWith<$Res> {
  factory $TranslationEvent_ResultCopyWith(TranslationEvent_Result value, $Res Function(TranslationEvent_Result) _then) = _$TranslationEvent_ResultCopyWithImpl;
@useResult
$Res call({
 String hash, String text
});




}
/// @nodoc
class _$TranslationEvent_ResultCopyWithImpl<$Res>
    implements $TranslationEvent_ResultCopyWith<$Res> {
  _$TranslationEvent_ResultCopyWithImpl(this._self, this._then);

  final TranslationEvent_Result _self;
  final $Res Function(TranslationEvent_Result) _then;

/// Create a copy of TranslationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? hash = null,Object? text = null,}) {
  return _then(TranslationEvent_Result(
hash: null == hash ? _self.hash : hash // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TranslationEvent_Progress extends TranslationEvent {
  const TranslationEvent_Progress({required this.completed, required this.total}): super._();
  

 final  BigInt completed;
 final  BigInt total;

/// Create a copy of TranslationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TranslationEvent_ProgressCopyWith<TranslationEvent_Progress> get copyWith => _$TranslationEvent_ProgressCopyWithImpl<TranslationEvent_Progress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TranslationEvent_Progress&&(identical(other.completed, completed) || other.completed == completed)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode => Object.hash(runtimeType,completed,total);

@override
String toString() {
  return 'TranslationEvent.progress(completed: $completed, total: $total)';
}


}

/// @nodoc
abstract mixin class $TranslationEvent_ProgressCopyWith<$Res> implements $TranslationEventCopyWith<$Res> {
  factory $TranslationEvent_ProgressCopyWith(TranslationEvent_Progress value, $Res Function(TranslationEvent_Progress) _then) = _$TranslationEvent_ProgressCopyWithImpl;
@useResult
$Res call({
 BigInt completed, BigInt total
});




}
/// @nodoc
class _$TranslationEvent_ProgressCopyWithImpl<$Res>
    implements $TranslationEvent_ProgressCopyWith<$Res> {
  _$TranslationEvent_ProgressCopyWithImpl(this._self, this._then);

  final TranslationEvent_Progress _self;
  final $Res Function(TranslationEvent_Progress) _then;

/// Create a copy of TranslationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completed = null,Object? total = null,}) {
  return _then(TranslationEvent_Progress(
completed: null == completed ? _self.completed : completed // ignore: cast_nullable_to_non_nullable
as BigInt,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class TranslationEvent_Failure extends TranslationEvent {
  const TranslationEvent_Failure({required this.hash, required this.code}): super._();
  

 final  String hash;
 final  ErrorCode code;

/// Create a copy of TranslationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TranslationEvent_FailureCopyWith<TranslationEvent_Failure> get copyWith => _$TranslationEvent_FailureCopyWithImpl<TranslationEvent_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TranslationEvent_Failure&&(identical(other.hash, hash) || other.hash == hash)&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode => Object.hash(runtimeType,hash,code);

@override
String toString() {
  return 'TranslationEvent.failure(hash: $hash, code: $code)';
}


}

/// @nodoc
abstract mixin class $TranslationEvent_FailureCopyWith<$Res> implements $TranslationEventCopyWith<$Res> {
  factory $TranslationEvent_FailureCopyWith(TranslationEvent_Failure value, $Res Function(TranslationEvent_Failure) _then) = _$TranslationEvent_FailureCopyWithImpl;
@useResult
$Res call({
 String hash, ErrorCode code
});




}
/// @nodoc
class _$TranslationEvent_FailureCopyWithImpl<$Res>
    implements $TranslationEvent_FailureCopyWith<$Res> {
  _$TranslationEvent_FailureCopyWithImpl(this._self, this._then);

  final TranslationEvent_Failure _self;
  final $Res Function(TranslationEvent_Failure) _then;

/// Create a copy of TranslationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? hash = null,Object? code = null,}) {
  return _then(TranslationEvent_Failure(
hash: null == hash ? _self.hash : hash // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as ErrorCode,
  ));
}


}

// dart format on
