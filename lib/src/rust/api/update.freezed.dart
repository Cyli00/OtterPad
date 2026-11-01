// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'update.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UpdateDownloadEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateDownloadEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'UpdateDownloadEvent()';
}


}

/// @nodoc
class $UpdateDownloadEventCopyWith<$Res>  {
$UpdateDownloadEventCopyWith(UpdateDownloadEvent _, $Res Function(UpdateDownloadEvent) __);
}


/// Adds pattern-matching-related methods to [UpdateDownloadEvent].
extension UpdateDownloadEventPatterns on UpdateDownloadEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UpdateDownloadEvent_Failed value)?  failed,TResult Function( UpdateDownloadEvent_Progress value)?  progress,TResult Function( UpdateDownloadEvent_Completed value)?  completed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UpdateDownloadEvent_Failed() when failed != null:
return failed(_that);case UpdateDownloadEvent_Progress() when progress != null:
return progress(_that);case UpdateDownloadEvent_Completed() when completed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UpdateDownloadEvent_Failed value)  failed,required TResult Function( UpdateDownloadEvent_Progress value)  progress,required TResult Function( UpdateDownloadEvent_Completed value)  completed,}){
final _that = this;
switch (_that) {
case UpdateDownloadEvent_Failed():
return failed(_that);case UpdateDownloadEvent_Progress():
return progress(_that);case UpdateDownloadEvent_Completed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UpdateDownloadEvent_Failed value)?  failed,TResult? Function( UpdateDownloadEvent_Progress value)?  progress,TResult? Function( UpdateDownloadEvent_Completed value)?  completed,}){
final _that = this;
switch (_that) {
case UpdateDownloadEvent_Failed() when failed != null:
return failed(_that);case UpdateDownloadEvent_Progress() when progress != null:
return progress(_that);case UpdateDownloadEvent_Completed() when completed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OtterError error)?  failed,TResult Function( TransferProgress progress)?  progress,TResult Function( String path)?  completed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UpdateDownloadEvent_Failed() when failed != null:
return failed(_that.error);case UpdateDownloadEvent_Progress() when progress != null:
return progress(_that.progress);case UpdateDownloadEvent_Completed() when completed != null:
return completed(_that.path);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OtterError error)  failed,required TResult Function( TransferProgress progress)  progress,required TResult Function( String path)  completed,}) {final _that = this;
switch (_that) {
case UpdateDownloadEvent_Failed():
return failed(_that.error);case UpdateDownloadEvent_Progress():
return progress(_that.progress);case UpdateDownloadEvent_Completed():
return completed(_that.path);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OtterError error)?  failed,TResult? Function( TransferProgress progress)?  progress,TResult? Function( String path)?  completed,}) {final _that = this;
switch (_that) {
case UpdateDownloadEvent_Failed() when failed != null:
return failed(_that.error);case UpdateDownloadEvent_Progress() when progress != null:
return progress(_that.progress);case UpdateDownloadEvent_Completed() when completed != null:
return completed(_that.path);case _:
  return null;

}
}

}

/// @nodoc


class UpdateDownloadEvent_Failed extends UpdateDownloadEvent {
  const UpdateDownloadEvent_Failed({required this.error}): super._();
  

 final  OtterError error;

/// Create a copy of UpdateDownloadEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateDownloadEvent_FailedCopyWith<UpdateDownloadEvent_Failed> get copyWith => _$UpdateDownloadEvent_FailedCopyWithImpl<UpdateDownloadEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateDownloadEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'UpdateDownloadEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $UpdateDownloadEvent_FailedCopyWith<$Res> implements $UpdateDownloadEventCopyWith<$Res> {
  factory $UpdateDownloadEvent_FailedCopyWith(UpdateDownloadEvent_Failed value, $Res Function(UpdateDownloadEvent_Failed) _then) = _$UpdateDownloadEvent_FailedCopyWithImpl;
@useResult
$Res call({
 OtterError error
});




}
/// @nodoc
class _$UpdateDownloadEvent_FailedCopyWithImpl<$Res>
    implements $UpdateDownloadEvent_FailedCopyWith<$Res> {
  _$UpdateDownloadEvent_FailedCopyWithImpl(this._self, this._then);

  final UpdateDownloadEvent_Failed _self;
  final $Res Function(UpdateDownloadEvent_Failed) _then;

/// Create a copy of UpdateDownloadEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(UpdateDownloadEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as OtterError,
  ));
}


}

/// @nodoc


class UpdateDownloadEvent_Progress extends UpdateDownloadEvent {
  const UpdateDownloadEvent_Progress({required this.progress}): super._();
  

 final  TransferProgress progress;

/// Create a copy of UpdateDownloadEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateDownloadEvent_ProgressCopyWith<UpdateDownloadEvent_Progress> get copyWith => _$UpdateDownloadEvent_ProgressCopyWithImpl<UpdateDownloadEvent_Progress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateDownloadEvent_Progress&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode => Object.hash(runtimeType,progress);

@override
String toString() {
  return 'UpdateDownloadEvent.progress(progress: $progress)';
}


}

/// @nodoc
abstract mixin class $UpdateDownloadEvent_ProgressCopyWith<$Res> implements $UpdateDownloadEventCopyWith<$Res> {
  factory $UpdateDownloadEvent_ProgressCopyWith(UpdateDownloadEvent_Progress value, $Res Function(UpdateDownloadEvent_Progress) _then) = _$UpdateDownloadEvent_ProgressCopyWithImpl;
@useResult
$Res call({
 TransferProgress progress
});




}
/// @nodoc
class _$UpdateDownloadEvent_ProgressCopyWithImpl<$Res>
    implements $UpdateDownloadEvent_ProgressCopyWith<$Res> {
  _$UpdateDownloadEvent_ProgressCopyWithImpl(this._self, this._then);

  final UpdateDownloadEvent_Progress _self;
  final $Res Function(UpdateDownloadEvent_Progress) _then;

/// Create a copy of UpdateDownloadEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? progress = null,}) {
  return _then(UpdateDownloadEvent_Progress(
progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as TransferProgress,
  ));
}


}

/// @nodoc


class UpdateDownloadEvent_Completed extends UpdateDownloadEvent {
  const UpdateDownloadEvent_Completed({required this.path}): super._();
  

 final  String path;

/// Create a copy of UpdateDownloadEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateDownloadEvent_CompletedCopyWith<UpdateDownloadEvent_Completed> get copyWith => _$UpdateDownloadEvent_CompletedCopyWithImpl<UpdateDownloadEvent_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateDownloadEvent_Completed&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode => Object.hash(runtimeType,path);

@override
String toString() {
  return 'UpdateDownloadEvent.completed(path: $path)';
}


}

/// @nodoc
abstract mixin class $UpdateDownloadEvent_CompletedCopyWith<$Res> implements $UpdateDownloadEventCopyWith<$Res> {
  factory $UpdateDownloadEvent_CompletedCopyWith(UpdateDownloadEvent_Completed value, $Res Function(UpdateDownloadEvent_Completed) _then) = _$UpdateDownloadEvent_CompletedCopyWithImpl;
@useResult
$Res call({
 String path
});




}
/// @nodoc
class _$UpdateDownloadEvent_CompletedCopyWithImpl<$Res>
    implements $UpdateDownloadEvent_CompletedCopyWith<$Res> {
  _$UpdateDownloadEvent_CompletedCopyWithImpl(this._self, this._then);

  final UpdateDownloadEvent_Completed _self;
  final $Res Function(UpdateDownloadEvent_Completed) _then;

/// Create a copy of UpdateDownloadEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,}) {
  return _then(UpdateDownloadEvent_Completed(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
