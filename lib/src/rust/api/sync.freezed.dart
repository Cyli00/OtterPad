// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sync.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SyncEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SyncEvent()';
}


}

/// @nodoc
class $SyncEventCopyWith<$Res>  {
$SyncEventCopyWith(SyncEvent _, $Res Function(SyncEvent) __);
}


/// Adds pattern-matching-related methods to [SyncEvent].
extension SyncEventPatterns on SyncEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SyncEvent_Failed value)?  failed,TResult Function( SyncEvent_Packing value)?  packing,TResult Function( SyncEvent_Uploading value)?  uploading,TResult Function( SyncEvent_Skipped value)?  skipped,TResult Function( SyncEvent_Uploaded value)?  uploaded,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SyncEvent_Failed() when failed != null:
return failed(_that);case SyncEvent_Packing() when packing != null:
return packing(_that);case SyncEvent_Uploading() when uploading != null:
return uploading(_that);case SyncEvent_Skipped() when skipped != null:
return skipped(_that);case SyncEvent_Uploaded() when uploaded != null:
return uploaded(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SyncEvent_Failed value)  failed,required TResult Function( SyncEvent_Packing value)  packing,required TResult Function( SyncEvent_Uploading value)  uploading,required TResult Function( SyncEvent_Skipped value)  skipped,required TResult Function( SyncEvent_Uploaded value)  uploaded,}){
final _that = this;
switch (_that) {
case SyncEvent_Failed():
return failed(_that);case SyncEvent_Packing():
return packing(_that);case SyncEvent_Uploading():
return uploading(_that);case SyncEvent_Skipped():
return skipped(_that);case SyncEvent_Uploaded():
return uploaded(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SyncEvent_Failed value)?  failed,TResult? Function( SyncEvent_Packing value)?  packing,TResult? Function( SyncEvent_Uploading value)?  uploading,TResult? Function( SyncEvent_Skipped value)?  skipped,TResult? Function( SyncEvent_Uploaded value)?  uploaded,}){
final _that = this;
switch (_that) {
case SyncEvent_Failed() when failed != null:
return failed(_that);case SyncEvent_Packing() when packing != null:
return packing(_that);case SyncEvent_Uploading() when uploading != null:
return uploading(_that);case SyncEvent_Skipped() when skipped != null:
return skipped(_that);case SyncEvent_Uploaded() when uploaded != null:
return uploaded(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OtterError error)?  failed,TResult Function( BackupProgress progress)?  packing,TResult Function( TransferProgress progress)?  uploading,TResult Function()?  skipped,TResult Function( String name,  BackupManifest manifest,  List<ErrorCode> warnings)?  uploaded,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SyncEvent_Failed() when failed != null:
return failed(_that.error);case SyncEvent_Packing() when packing != null:
return packing(_that.progress);case SyncEvent_Uploading() when uploading != null:
return uploading(_that.progress);case SyncEvent_Skipped() when skipped != null:
return skipped();case SyncEvent_Uploaded() when uploaded != null:
return uploaded(_that.name,_that.manifest,_that.warnings);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OtterError error)  failed,required TResult Function( BackupProgress progress)  packing,required TResult Function( TransferProgress progress)  uploading,required TResult Function()  skipped,required TResult Function( String name,  BackupManifest manifest,  List<ErrorCode> warnings)  uploaded,}) {final _that = this;
switch (_that) {
case SyncEvent_Failed():
return failed(_that.error);case SyncEvent_Packing():
return packing(_that.progress);case SyncEvent_Uploading():
return uploading(_that.progress);case SyncEvent_Skipped():
return skipped();case SyncEvent_Uploaded():
return uploaded(_that.name,_that.manifest,_that.warnings);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OtterError error)?  failed,TResult? Function( BackupProgress progress)?  packing,TResult? Function( TransferProgress progress)?  uploading,TResult? Function()?  skipped,TResult? Function( String name,  BackupManifest manifest,  List<ErrorCode> warnings)?  uploaded,}) {final _that = this;
switch (_that) {
case SyncEvent_Failed() when failed != null:
return failed(_that.error);case SyncEvent_Packing() when packing != null:
return packing(_that.progress);case SyncEvent_Uploading() when uploading != null:
return uploading(_that.progress);case SyncEvent_Skipped() when skipped != null:
return skipped();case SyncEvent_Uploaded() when uploaded != null:
return uploaded(_that.name,_that.manifest,_that.warnings);case _:
  return null;

}
}

}

/// @nodoc


class SyncEvent_Failed extends SyncEvent {
  const SyncEvent_Failed({required this.error}): super._();
  

 final  OtterError error;

/// Create a copy of SyncEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncEvent_FailedCopyWith<SyncEvent_Failed> get copyWith => _$SyncEvent_FailedCopyWithImpl<SyncEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'SyncEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $SyncEvent_FailedCopyWith<$Res> implements $SyncEventCopyWith<$Res> {
  factory $SyncEvent_FailedCopyWith(SyncEvent_Failed value, $Res Function(SyncEvent_Failed) _then) = _$SyncEvent_FailedCopyWithImpl;
@useResult
$Res call({
 OtterError error
});




}
/// @nodoc
class _$SyncEvent_FailedCopyWithImpl<$Res>
    implements $SyncEvent_FailedCopyWith<$Res> {
  _$SyncEvent_FailedCopyWithImpl(this._self, this._then);

  final SyncEvent_Failed _self;
  final $Res Function(SyncEvent_Failed) _then;

/// Create a copy of SyncEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(SyncEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as OtterError,
  ));
}


}

/// @nodoc


class SyncEvent_Packing extends SyncEvent {
  const SyncEvent_Packing({required this.progress}): super._();
  

 final  BackupProgress progress;

/// Create a copy of SyncEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncEvent_PackingCopyWith<SyncEvent_Packing> get copyWith => _$SyncEvent_PackingCopyWithImpl<SyncEvent_Packing>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncEvent_Packing&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode => Object.hash(runtimeType,progress);

@override
String toString() {
  return 'SyncEvent.packing(progress: $progress)';
}


}

/// @nodoc
abstract mixin class $SyncEvent_PackingCopyWith<$Res> implements $SyncEventCopyWith<$Res> {
  factory $SyncEvent_PackingCopyWith(SyncEvent_Packing value, $Res Function(SyncEvent_Packing) _then) = _$SyncEvent_PackingCopyWithImpl;
@useResult
$Res call({
 BackupProgress progress
});




}
/// @nodoc
class _$SyncEvent_PackingCopyWithImpl<$Res>
    implements $SyncEvent_PackingCopyWith<$Res> {
  _$SyncEvent_PackingCopyWithImpl(this._self, this._then);

  final SyncEvent_Packing _self;
  final $Res Function(SyncEvent_Packing) _then;

/// Create a copy of SyncEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? progress = null,}) {
  return _then(SyncEvent_Packing(
progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as BackupProgress,
  ));
}


}

/// @nodoc


class SyncEvent_Uploading extends SyncEvent {
  const SyncEvent_Uploading({required this.progress}): super._();
  

 final  TransferProgress progress;

/// Create a copy of SyncEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncEvent_UploadingCopyWith<SyncEvent_Uploading> get copyWith => _$SyncEvent_UploadingCopyWithImpl<SyncEvent_Uploading>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncEvent_Uploading&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode => Object.hash(runtimeType,progress);

@override
String toString() {
  return 'SyncEvent.uploading(progress: $progress)';
}


}

/// @nodoc
abstract mixin class $SyncEvent_UploadingCopyWith<$Res> implements $SyncEventCopyWith<$Res> {
  factory $SyncEvent_UploadingCopyWith(SyncEvent_Uploading value, $Res Function(SyncEvent_Uploading) _then) = _$SyncEvent_UploadingCopyWithImpl;
@useResult
$Res call({
 TransferProgress progress
});




}
/// @nodoc
class _$SyncEvent_UploadingCopyWithImpl<$Res>
    implements $SyncEvent_UploadingCopyWith<$Res> {
  _$SyncEvent_UploadingCopyWithImpl(this._self, this._then);

  final SyncEvent_Uploading _self;
  final $Res Function(SyncEvent_Uploading) _then;

/// Create a copy of SyncEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? progress = null,}) {
  return _then(SyncEvent_Uploading(
progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as TransferProgress,
  ));
}


}

/// @nodoc


class SyncEvent_Skipped extends SyncEvent {
  const SyncEvent_Skipped(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncEvent_Skipped);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SyncEvent.skipped()';
}


}




/// @nodoc


class SyncEvent_Uploaded extends SyncEvent {
  const SyncEvent_Uploaded({required this.name, required this.manifest, required final  List<ErrorCode> warnings}): _warnings = warnings,super._();
  

 final  String name;
 final  BackupManifest manifest;
 final  List<ErrorCode> _warnings;
 List<ErrorCode> get warnings {
  if (_warnings is EqualUnmodifiableListView) return _warnings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_warnings);
}


/// Create a copy of SyncEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncEvent_UploadedCopyWith<SyncEvent_Uploaded> get copyWith => _$SyncEvent_UploadedCopyWithImpl<SyncEvent_Uploaded>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncEvent_Uploaded&&(identical(other.name, name) || other.name == name)&&(identical(other.manifest, manifest) || other.manifest == manifest)&&const DeepCollectionEquality().equals(other._warnings, _warnings));
}


@override
int get hashCode => Object.hash(runtimeType,name,manifest,const DeepCollectionEquality().hash(_warnings));

@override
String toString() {
  return 'SyncEvent.uploaded(name: $name, manifest: $manifest, warnings: $warnings)';
}


}

/// @nodoc
abstract mixin class $SyncEvent_UploadedCopyWith<$Res> implements $SyncEventCopyWith<$Res> {
  factory $SyncEvent_UploadedCopyWith(SyncEvent_Uploaded value, $Res Function(SyncEvent_Uploaded) _then) = _$SyncEvent_UploadedCopyWithImpl;
@useResult
$Res call({
 String name, BackupManifest manifest, List<ErrorCode> warnings
});




}
/// @nodoc
class _$SyncEvent_UploadedCopyWithImpl<$Res>
    implements $SyncEvent_UploadedCopyWith<$Res> {
  _$SyncEvent_UploadedCopyWithImpl(this._self, this._then);

  final SyncEvent_Uploaded _self;
  final $Res Function(SyncEvent_Uploaded) _then;

/// Create a copy of SyncEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? manifest = null,Object? warnings = null,}) {
  return _then(SyncEvent_Uploaded(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,manifest: null == manifest ? _self.manifest : manifest // ignore: cast_nullable_to_non_nullable
as BackupManifest,warnings: null == warnings ? _self._warnings : warnings // ignore: cast_nullable_to_non_nullable
as List<ErrorCode>,
  ));
}


}

// dart format on
