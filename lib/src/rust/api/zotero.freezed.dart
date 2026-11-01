// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'zotero.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ZoteroEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ZoteroEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ZoteroEvent()';
}


}

/// @nodoc
class $ZoteroEventCopyWith<$Res>  {
$ZoteroEventCopyWith(ZoteroEvent _, $Res Function(ZoteroEvent) __);
}


/// Adds pattern-matching-related methods to [ZoteroEvent].
extension ZoteroEventPatterns on ZoteroEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ZoteroEvent_Failed value)?  failed,TResult Function( ZoteroEvent_Progress value)?  progress,TResult Function( ZoteroEvent_LocalReady value)?  localReady,TResult Function( ZoteroEvent_Imported value)?  imported,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ZoteroEvent_Failed() when failed != null:
return failed(_that);case ZoteroEvent_Progress() when progress != null:
return progress(_that);case ZoteroEvent_LocalReady() when localReady != null:
return localReady(_that);case ZoteroEvent_Imported() when imported != null:
return imported(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ZoteroEvent_Failed value)  failed,required TResult Function( ZoteroEvent_Progress value)  progress,required TResult Function( ZoteroEvent_LocalReady value)  localReady,required TResult Function( ZoteroEvent_Imported value)  imported,}){
final _that = this;
switch (_that) {
case ZoteroEvent_Failed():
return failed(_that);case ZoteroEvent_Progress():
return progress(_that);case ZoteroEvent_LocalReady():
return localReady(_that);case ZoteroEvent_Imported():
return imported(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ZoteroEvent_Failed value)?  failed,TResult? Function( ZoteroEvent_Progress value)?  progress,TResult? Function( ZoteroEvent_LocalReady value)?  localReady,TResult? Function( ZoteroEvent_Imported value)?  imported,}){
final _that = this;
switch (_that) {
case ZoteroEvent_Failed() when failed != null:
return failed(_that);case ZoteroEvent_Progress() when progress != null:
return progress(_that);case ZoteroEvent_LocalReady() when localReady != null:
return localReady(_that);case ZoteroEvent_Imported() when imported != null:
return imported(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OtterError error)?  failed,TResult Function( FetchProgress progress)?  progress,TResult Function( LocalZoteroSnapshot snapshot,  List<ImportCandidate> candidates)?  localReady,TResult Function( ImportReport report)?  imported,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ZoteroEvent_Failed() when failed != null:
return failed(_that.error);case ZoteroEvent_Progress() when progress != null:
return progress(_that.progress);case ZoteroEvent_LocalReady() when localReady != null:
return localReady(_that.snapshot,_that.candidates);case ZoteroEvent_Imported() when imported != null:
return imported(_that.report);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OtterError error)  failed,required TResult Function( FetchProgress progress)  progress,required TResult Function( LocalZoteroSnapshot snapshot,  List<ImportCandidate> candidates)  localReady,required TResult Function( ImportReport report)  imported,}) {final _that = this;
switch (_that) {
case ZoteroEvent_Failed():
return failed(_that.error);case ZoteroEvent_Progress():
return progress(_that.progress);case ZoteroEvent_LocalReady():
return localReady(_that.snapshot,_that.candidates);case ZoteroEvent_Imported():
return imported(_that.report);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OtterError error)?  failed,TResult? Function( FetchProgress progress)?  progress,TResult? Function( LocalZoteroSnapshot snapshot,  List<ImportCandidate> candidates)?  localReady,TResult? Function( ImportReport report)?  imported,}) {final _that = this;
switch (_that) {
case ZoteroEvent_Failed() when failed != null:
return failed(_that.error);case ZoteroEvent_Progress() when progress != null:
return progress(_that.progress);case ZoteroEvent_LocalReady() when localReady != null:
return localReady(_that.snapshot,_that.candidates);case ZoteroEvent_Imported() when imported != null:
return imported(_that.report);case _:
  return null;

}
}

}

/// @nodoc


class ZoteroEvent_Failed extends ZoteroEvent {
  const ZoteroEvent_Failed({required this.error}): super._();
  

 final  OtterError error;

/// Create a copy of ZoteroEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ZoteroEvent_FailedCopyWith<ZoteroEvent_Failed> get copyWith => _$ZoteroEvent_FailedCopyWithImpl<ZoteroEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ZoteroEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'ZoteroEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $ZoteroEvent_FailedCopyWith<$Res> implements $ZoteroEventCopyWith<$Res> {
  factory $ZoteroEvent_FailedCopyWith(ZoteroEvent_Failed value, $Res Function(ZoteroEvent_Failed) _then) = _$ZoteroEvent_FailedCopyWithImpl;
@useResult
$Res call({
 OtterError error
});




}
/// @nodoc
class _$ZoteroEvent_FailedCopyWithImpl<$Res>
    implements $ZoteroEvent_FailedCopyWith<$Res> {
  _$ZoteroEvent_FailedCopyWithImpl(this._self, this._then);

  final ZoteroEvent_Failed _self;
  final $Res Function(ZoteroEvent_Failed) _then;

/// Create a copy of ZoteroEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(ZoteroEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as OtterError,
  ));
}


}

/// @nodoc


class ZoteroEvent_Progress extends ZoteroEvent {
  const ZoteroEvent_Progress({required this.progress}): super._();
  

 final  FetchProgress progress;

/// Create a copy of ZoteroEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ZoteroEvent_ProgressCopyWith<ZoteroEvent_Progress> get copyWith => _$ZoteroEvent_ProgressCopyWithImpl<ZoteroEvent_Progress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ZoteroEvent_Progress&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode => Object.hash(runtimeType,progress);

@override
String toString() {
  return 'ZoteroEvent.progress(progress: $progress)';
}


}

/// @nodoc
abstract mixin class $ZoteroEvent_ProgressCopyWith<$Res> implements $ZoteroEventCopyWith<$Res> {
  factory $ZoteroEvent_ProgressCopyWith(ZoteroEvent_Progress value, $Res Function(ZoteroEvent_Progress) _then) = _$ZoteroEvent_ProgressCopyWithImpl;
@useResult
$Res call({
 FetchProgress progress
});




}
/// @nodoc
class _$ZoteroEvent_ProgressCopyWithImpl<$Res>
    implements $ZoteroEvent_ProgressCopyWith<$Res> {
  _$ZoteroEvent_ProgressCopyWithImpl(this._self, this._then);

  final ZoteroEvent_Progress _self;
  final $Res Function(ZoteroEvent_Progress) _then;

/// Create a copy of ZoteroEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? progress = null,}) {
  return _then(ZoteroEvent_Progress(
progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as FetchProgress,
  ));
}


}

/// @nodoc


class ZoteroEvent_LocalReady extends ZoteroEvent {
  const ZoteroEvent_LocalReady({required this.snapshot, required final  List<ImportCandidate> candidates}): _candidates = candidates,super._();
  

 final  LocalZoteroSnapshot snapshot;
 final  List<ImportCandidate> _candidates;
 List<ImportCandidate> get candidates {
  if (_candidates is EqualUnmodifiableListView) return _candidates;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_candidates);
}


/// Create a copy of ZoteroEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ZoteroEvent_LocalReadyCopyWith<ZoteroEvent_LocalReady> get copyWith => _$ZoteroEvent_LocalReadyCopyWithImpl<ZoteroEvent_LocalReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ZoteroEvent_LocalReady&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot)&&const DeepCollectionEquality().equals(other._candidates, _candidates));
}


@override
int get hashCode => Object.hash(runtimeType,snapshot,const DeepCollectionEquality().hash(_candidates));

@override
String toString() {
  return 'ZoteroEvent.localReady(snapshot: $snapshot, candidates: $candidates)';
}


}

/// @nodoc
abstract mixin class $ZoteroEvent_LocalReadyCopyWith<$Res> implements $ZoteroEventCopyWith<$Res> {
  factory $ZoteroEvent_LocalReadyCopyWith(ZoteroEvent_LocalReady value, $Res Function(ZoteroEvent_LocalReady) _then) = _$ZoteroEvent_LocalReadyCopyWithImpl;
@useResult
$Res call({
 LocalZoteroSnapshot snapshot, List<ImportCandidate> candidates
});




}
/// @nodoc
class _$ZoteroEvent_LocalReadyCopyWithImpl<$Res>
    implements $ZoteroEvent_LocalReadyCopyWith<$Res> {
  _$ZoteroEvent_LocalReadyCopyWithImpl(this._self, this._then);

  final ZoteroEvent_LocalReady _self;
  final $Res Function(ZoteroEvent_LocalReady) _then;

/// Create a copy of ZoteroEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? snapshot = null,Object? candidates = null,}) {
  return _then(ZoteroEvent_LocalReady(
snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as LocalZoteroSnapshot,candidates: null == candidates ? _self._candidates : candidates // ignore: cast_nullable_to_non_nullable
as List<ImportCandidate>,
  ));
}


}

/// @nodoc


class ZoteroEvent_Imported extends ZoteroEvent {
  const ZoteroEvent_Imported({required this.report}): super._();
  

 final  ImportReport report;

/// Create a copy of ZoteroEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ZoteroEvent_ImportedCopyWith<ZoteroEvent_Imported> get copyWith => _$ZoteroEvent_ImportedCopyWithImpl<ZoteroEvent_Imported>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ZoteroEvent_Imported&&(identical(other.report, report) || other.report == report));
}


@override
int get hashCode => Object.hash(runtimeType,report);

@override
String toString() {
  return 'ZoteroEvent.imported(report: $report)';
}


}

/// @nodoc
abstract mixin class $ZoteroEvent_ImportedCopyWith<$Res> implements $ZoteroEventCopyWith<$Res> {
  factory $ZoteroEvent_ImportedCopyWith(ZoteroEvent_Imported value, $Res Function(ZoteroEvent_Imported) _then) = _$ZoteroEvent_ImportedCopyWithImpl;
@useResult
$Res call({
 ImportReport report
});




}
/// @nodoc
class _$ZoteroEvent_ImportedCopyWithImpl<$Res>
    implements $ZoteroEvent_ImportedCopyWith<$Res> {
  _$ZoteroEvent_ImportedCopyWithImpl(this._self, this._then);

  final ZoteroEvent_Imported _self;
  final $Res Function(ZoteroEvent_Imported) _then;

/// Create a copy of ZoteroEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? report = null,}) {
  return _then(ZoteroEvent_Imported(
report: null == report ? _self.report : report // ignore: cast_nullable_to_non_nullable
as ImportReport,
  ));
}


}

// dart format on
