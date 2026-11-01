// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InitializationEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InitializationEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'InitializationEvent()';
}


}

/// @nodoc
class $InitializationEventCopyWith<$Res>  {
$InitializationEventCopyWith(InitializationEvent _, $Res Function(InitializationEvent) __);
}


/// Adds pattern-matching-related methods to [InitializationEvent].
extension InitializationEventPatterns on InitializationEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( InitializationEvent_Failed value)?  failed,TResult Function( InitializationEvent_Migration value)?  migration,TResult Function( InitializationEvent_Ready value)?  ready,required TResult orElse(),}){
final _that = this;
switch (_that) {
case InitializationEvent_Failed() when failed != null:
return failed(_that);case InitializationEvent_Migration() when migration != null:
return migration(_that);case InitializationEvent_Ready() when ready != null:
return ready(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( InitializationEvent_Failed value)  failed,required TResult Function( InitializationEvent_Migration value)  migration,required TResult Function( InitializationEvent_Ready value)  ready,}){
final _that = this;
switch (_that) {
case InitializationEvent_Failed():
return failed(_that);case InitializationEvent_Migration():
return migration(_that);case InitializationEvent_Ready():
return ready(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( InitializationEvent_Failed value)?  failed,TResult? Function( InitializationEvent_Migration value)?  migration,TResult? Function( InitializationEvent_Ready value)?  ready,}){
final _that = this;
switch (_that) {
case InitializationEvent_Failed() when failed != null:
return failed(_that);case InitializationEvent_Migration() when migration != null:
return migration(_that);case InitializationEvent_Ready() when ready != null:
return ready(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OtterError error)?  failed,TResult Function( MigrationProgress progress)?  migration,TResult Function( Backend backend,  String directory,  MigrationReport? migration,  ErrorCode? migrationError)?  ready,required TResult orElse(),}) {final _that = this;
switch (_that) {
case InitializationEvent_Failed() when failed != null:
return failed(_that.error);case InitializationEvent_Migration() when migration != null:
return migration(_that.progress);case InitializationEvent_Ready() when ready != null:
return ready(_that.backend,_that.directory,_that.migration,_that.migrationError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OtterError error)  failed,required TResult Function( MigrationProgress progress)  migration,required TResult Function( Backend backend,  String directory,  MigrationReport? migration,  ErrorCode? migrationError)  ready,}) {final _that = this;
switch (_that) {
case InitializationEvent_Failed():
return failed(_that.error);case InitializationEvent_Migration():
return migration(_that.progress);case InitializationEvent_Ready():
return ready(_that.backend,_that.directory,_that.migration,_that.migrationError);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OtterError error)?  failed,TResult? Function( MigrationProgress progress)?  migration,TResult? Function( Backend backend,  String directory,  MigrationReport? migration,  ErrorCode? migrationError)?  ready,}) {final _that = this;
switch (_that) {
case InitializationEvent_Failed() when failed != null:
return failed(_that.error);case InitializationEvent_Migration() when migration != null:
return migration(_that.progress);case InitializationEvent_Ready() when ready != null:
return ready(_that.backend,_that.directory,_that.migration,_that.migrationError);case _:
  return null;

}
}

}

/// @nodoc


class InitializationEvent_Failed extends InitializationEvent {
  const InitializationEvent_Failed({required this.error}): super._();
  

 final  OtterError error;

/// Create a copy of InitializationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InitializationEvent_FailedCopyWith<InitializationEvent_Failed> get copyWith => _$InitializationEvent_FailedCopyWithImpl<InitializationEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InitializationEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'InitializationEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $InitializationEvent_FailedCopyWith<$Res> implements $InitializationEventCopyWith<$Res> {
  factory $InitializationEvent_FailedCopyWith(InitializationEvent_Failed value, $Res Function(InitializationEvent_Failed) _then) = _$InitializationEvent_FailedCopyWithImpl;
@useResult
$Res call({
 OtterError error
});




}
/// @nodoc
class _$InitializationEvent_FailedCopyWithImpl<$Res>
    implements $InitializationEvent_FailedCopyWith<$Res> {
  _$InitializationEvent_FailedCopyWithImpl(this._self, this._then);

  final InitializationEvent_Failed _self;
  final $Res Function(InitializationEvent_Failed) _then;

/// Create a copy of InitializationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(InitializationEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as OtterError,
  ));
}


}

/// @nodoc


class InitializationEvent_Migration extends InitializationEvent {
  const InitializationEvent_Migration({required this.progress}): super._();
  

 final  MigrationProgress progress;

/// Create a copy of InitializationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InitializationEvent_MigrationCopyWith<InitializationEvent_Migration> get copyWith => _$InitializationEvent_MigrationCopyWithImpl<InitializationEvent_Migration>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InitializationEvent_Migration&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode => Object.hash(runtimeType,progress);

@override
String toString() {
  return 'InitializationEvent.migration(progress: $progress)';
}


}

/// @nodoc
abstract mixin class $InitializationEvent_MigrationCopyWith<$Res> implements $InitializationEventCopyWith<$Res> {
  factory $InitializationEvent_MigrationCopyWith(InitializationEvent_Migration value, $Res Function(InitializationEvent_Migration) _then) = _$InitializationEvent_MigrationCopyWithImpl;
@useResult
$Res call({
 MigrationProgress progress
});




}
/// @nodoc
class _$InitializationEvent_MigrationCopyWithImpl<$Res>
    implements $InitializationEvent_MigrationCopyWith<$Res> {
  _$InitializationEvent_MigrationCopyWithImpl(this._self, this._then);

  final InitializationEvent_Migration _self;
  final $Res Function(InitializationEvent_Migration) _then;

/// Create a copy of InitializationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? progress = null,}) {
  return _then(InitializationEvent_Migration(
progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as MigrationProgress,
  ));
}


}

/// @nodoc


class InitializationEvent_Ready extends InitializationEvent {
  const InitializationEvent_Ready({required this.backend, required this.directory, this.migration, this.migrationError}): super._();
  

 final  Backend backend;
 final  String directory;
 final  MigrationReport? migration;
 final  ErrorCode? migrationError;

/// Create a copy of InitializationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InitializationEvent_ReadyCopyWith<InitializationEvent_Ready> get copyWith => _$InitializationEvent_ReadyCopyWithImpl<InitializationEvent_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InitializationEvent_Ready&&(identical(other.backend, backend) || other.backend == backend)&&(identical(other.directory, directory) || other.directory == directory)&&(identical(other.migration, migration) || other.migration == migration)&&(identical(other.migrationError, migrationError) || other.migrationError == migrationError));
}


@override
int get hashCode => Object.hash(runtimeType,backend,directory,migration,migrationError);

@override
String toString() {
  return 'InitializationEvent.ready(backend: $backend, directory: $directory, migration: $migration, migrationError: $migrationError)';
}


}

/// @nodoc
abstract mixin class $InitializationEvent_ReadyCopyWith<$Res> implements $InitializationEventCopyWith<$Res> {
  factory $InitializationEvent_ReadyCopyWith(InitializationEvent_Ready value, $Res Function(InitializationEvent_Ready) _then) = _$InitializationEvent_ReadyCopyWithImpl;
@useResult
$Res call({
 Backend backend, String directory, MigrationReport? migration, ErrorCode? migrationError
});




}
/// @nodoc
class _$InitializationEvent_ReadyCopyWithImpl<$Res>
    implements $InitializationEvent_ReadyCopyWith<$Res> {
  _$InitializationEvent_ReadyCopyWithImpl(this._self, this._then);

  final InitializationEvent_Ready _self;
  final $Res Function(InitializationEvent_Ready) _then;

/// Create a copy of InitializationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? backend = null,Object? directory = null,Object? migration = freezed,Object? migrationError = freezed,}) {
  return _then(InitializationEvent_Ready(
backend: null == backend ? _self.backend : backend // ignore: cast_nullable_to_non_nullable
as Backend,directory: null == directory ? _self.directory : directory // ignore: cast_nullable_to_non_nullable
as String,migration: freezed == migration ? _self.migration : migration // ignore: cast_nullable_to_non_nullable
as MigrationReport?,migrationError: freezed == migrationError ? _self.migrationError : migrationError // ignore: cast_nullable_to_non_nullable
as ErrorCode?,
  ));
}


}

// dart format on
