// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'backup.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BackupEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BackupEvent()';
}


}

/// @nodoc
class $BackupEventCopyWith<$Res>  {
$BackupEventCopyWith(BackupEvent _, $Res Function(BackupEvent) __);
}


/// Adds pattern-matching-related methods to [BackupEvent].
extension BackupEventPatterns on BackupEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BackupEvent_Failed value)?  failed,TResult Function( BackupEvent_Progress value)?  progress,TResult Function( BackupEvent_Created value)?  created,TResult Function( BackupEvent_Prepared value)?  prepared,TResult Function( BackupEvent_Restored value)?  restored,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BackupEvent_Failed() when failed != null:
return failed(_that);case BackupEvent_Progress() when progress != null:
return progress(_that);case BackupEvent_Created() when created != null:
return created(_that);case BackupEvent_Prepared() when prepared != null:
return prepared(_that);case BackupEvent_Restored() when restored != null:
return restored(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BackupEvent_Failed value)  failed,required TResult Function( BackupEvent_Progress value)  progress,required TResult Function( BackupEvent_Created value)  created,required TResult Function( BackupEvent_Prepared value)  prepared,required TResult Function( BackupEvent_Restored value)  restored,}){
final _that = this;
switch (_that) {
case BackupEvent_Failed():
return failed(_that);case BackupEvent_Progress():
return progress(_that);case BackupEvent_Created():
return created(_that);case BackupEvent_Prepared():
return prepared(_that);case BackupEvent_Restored():
return restored(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BackupEvent_Failed value)?  failed,TResult? Function( BackupEvent_Progress value)?  progress,TResult? Function( BackupEvent_Created value)?  created,TResult? Function( BackupEvent_Prepared value)?  prepared,TResult? Function( BackupEvent_Restored value)?  restored,}){
final _that = this;
switch (_that) {
case BackupEvent_Failed() when failed != null:
return failed(_that);case BackupEvent_Progress() when progress != null:
return progress(_that);case BackupEvent_Created() when created != null:
return created(_that);case BackupEvent_Prepared() when prepared != null:
return prepared(_that);case BackupEvent_Restored() when restored != null:
return restored(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OtterError error)?  failed,TResult Function( BackupProgress progress)?  progress,TResult Function( BackupManifest manifest)?  created,TResult Function( RestorePreview preview)?  prepared,TResult Function( RestoreReport report)?  restored,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BackupEvent_Failed() when failed != null:
return failed(_that.error);case BackupEvent_Progress() when progress != null:
return progress(_that.progress);case BackupEvent_Created() when created != null:
return created(_that.manifest);case BackupEvent_Prepared() when prepared != null:
return prepared(_that.preview);case BackupEvent_Restored() when restored != null:
return restored(_that.report);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OtterError error)  failed,required TResult Function( BackupProgress progress)  progress,required TResult Function( BackupManifest manifest)  created,required TResult Function( RestorePreview preview)  prepared,required TResult Function( RestoreReport report)  restored,}) {final _that = this;
switch (_that) {
case BackupEvent_Failed():
return failed(_that.error);case BackupEvent_Progress():
return progress(_that.progress);case BackupEvent_Created():
return created(_that.manifest);case BackupEvent_Prepared():
return prepared(_that.preview);case BackupEvent_Restored():
return restored(_that.report);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OtterError error)?  failed,TResult? Function( BackupProgress progress)?  progress,TResult? Function( BackupManifest manifest)?  created,TResult? Function( RestorePreview preview)?  prepared,TResult? Function( RestoreReport report)?  restored,}) {final _that = this;
switch (_that) {
case BackupEvent_Failed() when failed != null:
return failed(_that.error);case BackupEvent_Progress() when progress != null:
return progress(_that.progress);case BackupEvent_Created() when created != null:
return created(_that.manifest);case BackupEvent_Prepared() when prepared != null:
return prepared(_that.preview);case BackupEvent_Restored() when restored != null:
return restored(_that.report);case _:
  return null;

}
}

}

/// @nodoc


class BackupEvent_Failed extends BackupEvent {
  const BackupEvent_Failed({required this.error}): super._();
  

 final  OtterError error;

/// Create a copy of BackupEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackupEvent_FailedCopyWith<BackupEvent_Failed> get copyWith => _$BackupEvent_FailedCopyWithImpl<BackupEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'BackupEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $BackupEvent_FailedCopyWith<$Res> implements $BackupEventCopyWith<$Res> {
  factory $BackupEvent_FailedCopyWith(BackupEvent_Failed value, $Res Function(BackupEvent_Failed) _then) = _$BackupEvent_FailedCopyWithImpl;
@useResult
$Res call({
 OtterError error
});




}
/// @nodoc
class _$BackupEvent_FailedCopyWithImpl<$Res>
    implements $BackupEvent_FailedCopyWith<$Res> {
  _$BackupEvent_FailedCopyWithImpl(this._self, this._then);

  final BackupEvent_Failed _self;
  final $Res Function(BackupEvent_Failed) _then;

/// Create a copy of BackupEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(BackupEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as OtterError,
  ));
}


}

/// @nodoc


class BackupEvent_Progress extends BackupEvent {
  const BackupEvent_Progress({required this.progress}): super._();
  

 final  BackupProgress progress;

/// Create a copy of BackupEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackupEvent_ProgressCopyWith<BackupEvent_Progress> get copyWith => _$BackupEvent_ProgressCopyWithImpl<BackupEvent_Progress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupEvent_Progress&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode => Object.hash(runtimeType,progress);

@override
String toString() {
  return 'BackupEvent.progress(progress: $progress)';
}


}

/// @nodoc
abstract mixin class $BackupEvent_ProgressCopyWith<$Res> implements $BackupEventCopyWith<$Res> {
  factory $BackupEvent_ProgressCopyWith(BackupEvent_Progress value, $Res Function(BackupEvent_Progress) _then) = _$BackupEvent_ProgressCopyWithImpl;
@useResult
$Res call({
 BackupProgress progress
});




}
/// @nodoc
class _$BackupEvent_ProgressCopyWithImpl<$Res>
    implements $BackupEvent_ProgressCopyWith<$Res> {
  _$BackupEvent_ProgressCopyWithImpl(this._self, this._then);

  final BackupEvent_Progress _self;
  final $Res Function(BackupEvent_Progress) _then;

/// Create a copy of BackupEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? progress = null,}) {
  return _then(BackupEvent_Progress(
progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as BackupProgress,
  ));
}


}

/// @nodoc


class BackupEvent_Created extends BackupEvent {
  const BackupEvent_Created({required this.manifest}): super._();
  

 final  BackupManifest manifest;

/// Create a copy of BackupEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackupEvent_CreatedCopyWith<BackupEvent_Created> get copyWith => _$BackupEvent_CreatedCopyWithImpl<BackupEvent_Created>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupEvent_Created&&(identical(other.manifest, manifest) || other.manifest == manifest));
}


@override
int get hashCode => Object.hash(runtimeType,manifest);

@override
String toString() {
  return 'BackupEvent.created(manifest: $manifest)';
}


}

/// @nodoc
abstract mixin class $BackupEvent_CreatedCopyWith<$Res> implements $BackupEventCopyWith<$Res> {
  factory $BackupEvent_CreatedCopyWith(BackupEvent_Created value, $Res Function(BackupEvent_Created) _then) = _$BackupEvent_CreatedCopyWithImpl;
@useResult
$Res call({
 BackupManifest manifest
});




}
/// @nodoc
class _$BackupEvent_CreatedCopyWithImpl<$Res>
    implements $BackupEvent_CreatedCopyWith<$Res> {
  _$BackupEvent_CreatedCopyWithImpl(this._self, this._then);

  final BackupEvent_Created _self;
  final $Res Function(BackupEvent_Created) _then;

/// Create a copy of BackupEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? manifest = null,}) {
  return _then(BackupEvent_Created(
manifest: null == manifest ? _self.manifest : manifest // ignore: cast_nullable_to_non_nullable
as BackupManifest,
  ));
}


}

/// @nodoc


class BackupEvent_Prepared extends BackupEvent {
  const BackupEvent_Prepared({required this.preview}): super._();
  

 final  RestorePreview preview;

/// Create a copy of BackupEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackupEvent_PreparedCopyWith<BackupEvent_Prepared> get copyWith => _$BackupEvent_PreparedCopyWithImpl<BackupEvent_Prepared>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupEvent_Prepared&&(identical(other.preview, preview) || other.preview == preview));
}


@override
int get hashCode => Object.hash(runtimeType,preview);

@override
String toString() {
  return 'BackupEvent.prepared(preview: $preview)';
}


}

/// @nodoc
abstract mixin class $BackupEvent_PreparedCopyWith<$Res> implements $BackupEventCopyWith<$Res> {
  factory $BackupEvent_PreparedCopyWith(BackupEvent_Prepared value, $Res Function(BackupEvent_Prepared) _then) = _$BackupEvent_PreparedCopyWithImpl;
@useResult
$Res call({
 RestorePreview preview
});




}
/// @nodoc
class _$BackupEvent_PreparedCopyWithImpl<$Res>
    implements $BackupEvent_PreparedCopyWith<$Res> {
  _$BackupEvent_PreparedCopyWithImpl(this._self, this._then);

  final BackupEvent_Prepared _self;
  final $Res Function(BackupEvent_Prepared) _then;

/// Create a copy of BackupEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? preview = null,}) {
  return _then(BackupEvent_Prepared(
preview: null == preview ? _self.preview : preview // ignore: cast_nullable_to_non_nullable
as RestorePreview,
  ));
}


}

/// @nodoc


class BackupEvent_Restored extends BackupEvent {
  const BackupEvent_Restored({required this.report}): super._();
  

 final  RestoreReport report;

/// Create a copy of BackupEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackupEvent_RestoredCopyWith<BackupEvent_Restored> get copyWith => _$BackupEvent_RestoredCopyWithImpl<BackupEvent_Restored>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupEvent_Restored&&(identical(other.report, report) || other.report == report));
}


@override
int get hashCode => Object.hash(runtimeType,report);

@override
String toString() {
  return 'BackupEvent.restored(report: $report)';
}


}

/// @nodoc
abstract mixin class $BackupEvent_RestoredCopyWith<$Res> implements $BackupEventCopyWith<$Res> {
  factory $BackupEvent_RestoredCopyWith(BackupEvent_Restored value, $Res Function(BackupEvent_Restored) _then) = _$BackupEvent_RestoredCopyWithImpl;
@useResult
$Res call({
 RestoreReport report
});




}
/// @nodoc
class _$BackupEvent_RestoredCopyWithImpl<$Res>
    implements $BackupEvent_RestoredCopyWith<$Res> {
  _$BackupEvent_RestoredCopyWithImpl(this._self, this._then);

  final BackupEvent_Restored _self;
  final $Res Function(BackupEvent_Restored) _then;

/// Create a copy of BackupEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? report = null,}) {
  return _then(BackupEvent_Restored(
report: null == report ? _self.report : report // ignore: cast_nullable_to_non_nullable
as RestoreReport,
  ));
}


}

// dart format on
