// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'metadata.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MetadataEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MetadataEvent()';
}


}

/// @nodoc
class $MetadataEventCopyWith<$Res>  {
$MetadataEventCopyWith(MetadataEvent _, $Res Function(MetadataEvent) __);
}


/// Adds pattern-matching-related methods to [MetadataEvent].
extension MetadataEventPatterns on MetadataEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( MetadataEvent_Failed value)?  failed,TResult Function( MetadataEvent_ReadingPdf value)?  readingPdf,TResult Function( MetadataEvent_ResolvingIdentifier value)?  resolvingIdentifier,TResult Function( MetadataEvent_SearchingTitle value)?  searchingTitle,TResult Function( MetadataEvent_Completed value)?  completed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case MetadataEvent_Failed() when failed != null:
return failed(_that);case MetadataEvent_ReadingPdf() when readingPdf != null:
return readingPdf(_that);case MetadataEvent_ResolvingIdentifier() when resolvingIdentifier != null:
return resolvingIdentifier(_that);case MetadataEvent_SearchingTitle() when searchingTitle != null:
return searchingTitle(_that);case MetadataEvent_Completed() when completed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( MetadataEvent_Failed value)  failed,required TResult Function( MetadataEvent_ReadingPdf value)  readingPdf,required TResult Function( MetadataEvent_ResolvingIdentifier value)  resolvingIdentifier,required TResult Function( MetadataEvent_SearchingTitle value)  searchingTitle,required TResult Function( MetadataEvent_Completed value)  completed,}){
final _that = this;
switch (_that) {
case MetadataEvent_Failed():
return failed(_that);case MetadataEvent_ReadingPdf():
return readingPdf(_that);case MetadataEvent_ResolvingIdentifier():
return resolvingIdentifier(_that);case MetadataEvent_SearchingTitle():
return searchingTitle(_that);case MetadataEvent_Completed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( MetadataEvent_Failed value)?  failed,TResult? Function( MetadataEvent_ReadingPdf value)?  readingPdf,TResult? Function( MetadataEvent_ResolvingIdentifier value)?  resolvingIdentifier,TResult? Function( MetadataEvent_SearchingTitle value)?  searchingTitle,TResult? Function( MetadataEvent_Completed value)?  completed,}){
final _that = this;
switch (_that) {
case MetadataEvent_Failed() when failed != null:
return failed(_that);case MetadataEvent_ReadingPdf() when readingPdf != null:
return readingPdf(_that);case MetadataEvent_ResolvingIdentifier() when resolvingIdentifier != null:
return resolvingIdentifier(_that);case MetadataEvent_SearchingTitle() when searchingTitle != null:
return searchingTitle(_that);case MetadataEvent_Completed() when completed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OtterError error)?  failed,TResult Function()?  readingPdf,TResult Function()?  resolvingIdentifier,TResult Function()?  searchingTitle,TResult Function( MetadataRepair report)?  completed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case MetadataEvent_Failed() when failed != null:
return failed(_that.error);case MetadataEvent_ReadingPdf() when readingPdf != null:
return readingPdf();case MetadataEvent_ResolvingIdentifier() when resolvingIdentifier != null:
return resolvingIdentifier();case MetadataEvent_SearchingTitle() when searchingTitle != null:
return searchingTitle();case MetadataEvent_Completed() when completed != null:
return completed(_that.report);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OtterError error)  failed,required TResult Function()  readingPdf,required TResult Function()  resolvingIdentifier,required TResult Function()  searchingTitle,required TResult Function( MetadataRepair report)  completed,}) {final _that = this;
switch (_that) {
case MetadataEvent_Failed():
return failed(_that.error);case MetadataEvent_ReadingPdf():
return readingPdf();case MetadataEvent_ResolvingIdentifier():
return resolvingIdentifier();case MetadataEvent_SearchingTitle():
return searchingTitle();case MetadataEvent_Completed():
return completed(_that.report);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OtterError error)?  failed,TResult? Function()?  readingPdf,TResult? Function()?  resolvingIdentifier,TResult? Function()?  searchingTitle,TResult? Function( MetadataRepair report)?  completed,}) {final _that = this;
switch (_that) {
case MetadataEvent_Failed() when failed != null:
return failed(_that.error);case MetadataEvent_ReadingPdf() when readingPdf != null:
return readingPdf();case MetadataEvent_ResolvingIdentifier() when resolvingIdentifier != null:
return resolvingIdentifier();case MetadataEvent_SearchingTitle() when searchingTitle != null:
return searchingTitle();case MetadataEvent_Completed() when completed != null:
return completed(_that.report);case _:
  return null;

}
}

}

/// @nodoc


class MetadataEvent_Failed extends MetadataEvent {
  const MetadataEvent_Failed({required this.error}): super._();
  

 final  OtterError error;

/// Create a copy of MetadataEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetadataEvent_FailedCopyWith<MetadataEvent_Failed> get copyWith => _$MetadataEvent_FailedCopyWithImpl<MetadataEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'MetadataEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $MetadataEvent_FailedCopyWith<$Res> implements $MetadataEventCopyWith<$Res> {
  factory $MetadataEvent_FailedCopyWith(MetadataEvent_Failed value, $Res Function(MetadataEvent_Failed) _then) = _$MetadataEvent_FailedCopyWithImpl;
@useResult
$Res call({
 OtterError error
});




}
/// @nodoc
class _$MetadataEvent_FailedCopyWithImpl<$Res>
    implements $MetadataEvent_FailedCopyWith<$Res> {
  _$MetadataEvent_FailedCopyWithImpl(this._self, this._then);

  final MetadataEvent_Failed _self;
  final $Res Function(MetadataEvent_Failed) _then;

/// Create a copy of MetadataEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(MetadataEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as OtterError,
  ));
}


}

/// @nodoc


class MetadataEvent_ReadingPdf extends MetadataEvent {
  const MetadataEvent_ReadingPdf(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataEvent_ReadingPdf);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MetadataEvent.readingPdf()';
}


}




/// @nodoc


class MetadataEvent_ResolvingIdentifier extends MetadataEvent {
  const MetadataEvent_ResolvingIdentifier(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataEvent_ResolvingIdentifier);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MetadataEvent.resolvingIdentifier()';
}


}




/// @nodoc


class MetadataEvent_SearchingTitle extends MetadataEvent {
  const MetadataEvent_SearchingTitle(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataEvent_SearchingTitle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MetadataEvent.searchingTitle()';
}


}




/// @nodoc


class MetadataEvent_Completed extends MetadataEvent {
  const MetadataEvent_Completed({required this.report}): super._();
  

 final  MetadataRepair report;

/// Create a copy of MetadataEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetadataEvent_CompletedCopyWith<MetadataEvent_Completed> get copyWith => _$MetadataEvent_CompletedCopyWithImpl<MetadataEvent_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataEvent_Completed&&(identical(other.report, report) || other.report == report));
}


@override
int get hashCode => Object.hash(runtimeType,report);

@override
String toString() {
  return 'MetadataEvent.completed(report: $report)';
}


}

/// @nodoc
abstract mixin class $MetadataEvent_CompletedCopyWith<$Res> implements $MetadataEventCopyWith<$Res> {
  factory $MetadataEvent_CompletedCopyWith(MetadataEvent_Completed value, $Res Function(MetadataEvent_Completed) _then) = _$MetadataEvent_CompletedCopyWithImpl;
@useResult
$Res call({
 MetadataRepair report
});




}
/// @nodoc
class _$MetadataEvent_CompletedCopyWithImpl<$Res>
    implements $MetadataEvent_CompletedCopyWith<$Res> {
  _$MetadataEvent_CompletedCopyWithImpl(this._self, this._then);

  final MetadataEvent_Completed _self;
  final $Res Function(MetadataEvent_Completed) _then;

/// Create a copy of MetadataEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? report = null,}) {
  return _then(MetadataEvent_Completed(
report: null == report ? _self.report : report // ignore: cast_nullable_to_non_nullable
as MetadataRepair,
  ));
}


}

// dart format on
