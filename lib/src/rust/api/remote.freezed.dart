// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'remote.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RemoteTransferEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoteTransferEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RemoteTransferEvent()';
}


}

/// @nodoc
class $RemoteTransferEventCopyWith<$Res>  {
$RemoteTransferEventCopyWith(RemoteTransferEvent _, $Res Function(RemoteTransferEvent) __);
}


/// Adds pattern-matching-related methods to [RemoteTransferEvent].
extension RemoteTransferEventPatterns on RemoteTransferEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RemoteTransferEvent_Failed value)?  failed,TResult Function( RemoteTransferEvent_Progress value)?  progress,TResult Function( RemoteTransferEvent_Completed value)?  completed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RemoteTransferEvent_Failed() when failed != null:
return failed(_that);case RemoteTransferEvent_Progress() when progress != null:
return progress(_that);case RemoteTransferEvent_Completed() when completed != null:
return completed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RemoteTransferEvent_Failed value)  failed,required TResult Function( RemoteTransferEvent_Progress value)  progress,required TResult Function( RemoteTransferEvent_Completed value)  completed,}){
final _that = this;
switch (_that) {
case RemoteTransferEvent_Failed():
return failed(_that);case RemoteTransferEvent_Progress():
return progress(_that);case RemoteTransferEvent_Completed():
return completed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RemoteTransferEvent_Failed value)?  failed,TResult? Function( RemoteTransferEvent_Progress value)?  progress,TResult? Function( RemoteTransferEvent_Completed value)?  completed,}){
final _that = this;
switch (_that) {
case RemoteTransferEvent_Failed() when failed != null:
return failed(_that);case RemoteTransferEvent_Progress() when progress != null:
return progress(_that);case RemoteTransferEvent_Completed() when completed != null:
return completed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OtterError error)?  failed,TResult Function( TransferProgress progress)?  progress,TResult Function()?  completed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RemoteTransferEvent_Failed() when failed != null:
return failed(_that.error);case RemoteTransferEvent_Progress() when progress != null:
return progress(_that.progress);case RemoteTransferEvent_Completed() when completed != null:
return completed();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OtterError error)  failed,required TResult Function( TransferProgress progress)  progress,required TResult Function()  completed,}) {final _that = this;
switch (_that) {
case RemoteTransferEvent_Failed():
return failed(_that.error);case RemoteTransferEvent_Progress():
return progress(_that.progress);case RemoteTransferEvent_Completed():
return completed();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OtterError error)?  failed,TResult? Function( TransferProgress progress)?  progress,TResult? Function()?  completed,}) {final _that = this;
switch (_that) {
case RemoteTransferEvent_Failed() when failed != null:
return failed(_that.error);case RemoteTransferEvent_Progress() when progress != null:
return progress(_that.progress);case RemoteTransferEvent_Completed() when completed != null:
return completed();case _:
  return null;

}
}

}

/// @nodoc


class RemoteTransferEvent_Failed extends RemoteTransferEvent {
  const RemoteTransferEvent_Failed({required this.error}): super._();
  

 final  OtterError error;

/// Create a copy of RemoteTransferEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoteTransferEvent_FailedCopyWith<RemoteTransferEvent_Failed> get copyWith => _$RemoteTransferEvent_FailedCopyWithImpl<RemoteTransferEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoteTransferEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'RemoteTransferEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $RemoteTransferEvent_FailedCopyWith<$Res> implements $RemoteTransferEventCopyWith<$Res> {
  factory $RemoteTransferEvent_FailedCopyWith(RemoteTransferEvent_Failed value, $Res Function(RemoteTransferEvent_Failed) _then) = _$RemoteTransferEvent_FailedCopyWithImpl;
@useResult
$Res call({
 OtterError error
});




}
/// @nodoc
class _$RemoteTransferEvent_FailedCopyWithImpl<$Res>
    implements $RemoteTransferEvent_FailedCopyWith<$Res> {
  _$RemoteTransferEvent_FailedCopyWithImpl(this._self, this._then);

  final RemoteTransferEvent_Failed _self;
  final $Res Function(RemoteTransferEvent_Failed) _then;

/// Create a copy of RemoteTransferEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(RemoteTransferEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as OtterError,
  ));
}


}

/// @nodoc


class RemoteTransferEvent_Progress extends RemoteTransferEvent {
  const RemoteTransferEvent_Progress({required this.progress}): super._();
  

 final  TransferProgress progress;

/// Create a copy of RemoteTransferEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoteTransferEvent_ProgressCopyWith<RemoteTransferEvent_Progress> get copyWith => _$RemoteTransferEvent_ProgressCopyWithImpl<RemoteTransferEvent_Progress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoteTransferEvent_Progress&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode => Object.hash(runtimeType,progress);

@override
String toString() {
  return 'RemoteTransferEvent.progress(progress: $progress)';
}


}

/// @nodoc
abstract mixin class $RemoteTransferEvent_ProgressCopyWith<$Res> implements $RemoteTransferEventCopyWith<$Res> {
  factory $RemoteTransferEvent_ProgressCopyWith(RemoteTransferEvent_Progress value, $Res Function(RemoteTransferEvent_Progress) _then) = _$RemoteTransferEvent_ProgressCopyWithImpl;
@useResult
$Res call({
 TransferProgress progress
});




}
/// @nodoc
class _$RemoteTransferEvent_ProgressCopyWithImpl<$Res>
    implements $RemoteTransferEvent_ProgressCopyWith<$Res> {
  _$RemoteTransferEvent_ProgressCopyWithImpl(this._self, this._then);

  final RemoteTransferEvent_Progress _self;
  final $Res Function(RemoteTransferEvent_Progress) _then;

/// Create a copy of RemoteTransferEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? progress = null,}) {
  return _then(RemoteTransferEvent_Progress(
progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as TransferProgress,
  ));
}


}

/// @nodoc


class RemoteTransferEvent_Completed extends RemoteTransferEvent {
  const RemoteTransferEvent_Completed(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoteTransferEvent_Completed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RemoteTransferEvent.completed()';
}


}




// dart format on
