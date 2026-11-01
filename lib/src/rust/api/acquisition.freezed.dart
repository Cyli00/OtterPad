// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'acquisition.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AcquisitionEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcquisitionEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AcquisitionEvent()';
}


}

/// @nodoc
class $AcquisitionEventCopyWith<$Res>  {
$AcquisitionEventCopyWith(AcquisitionEvent _, $Res Function(AcquisitionEvent) __);
}


/// Adds pattern-matching-related methods to [AcquisitionEvent].
extension AcquisitionEventPatterns on AcquisitionEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AcquisitionEvent_Failed value)?  failed,TResult Function( AcquisitionEvent_ResolvingMetadata value)?  resolvingMetadata,TResult Function( AcquisitionEvent_MetadataSaved value)?  metadataSaved,TResult Function( AcquisitionEvent_Downloading value)?  downloading,TResult Function( AcquisitionEvent_ValidatingPdf value)?  validatingPdf,TResult Function( AcquisitionEvent_Completed value)?  completed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AcquisitionEvent_Failed() when failed != null:
return failed(_that);case AcquisitionEvent_ResolvingMetadata() when resolvingMetadata != null:
return resolvingMetadata(_that);case AcquisitionEvent_MetadataSaved() when metadataSaved != null:
return metadataSaved(_that);case AcquisitionEvent_Downloading() when downloading != null:
return downloading(_that);case AcquisitionEvent_ValidatingPdf() when validatingPdf != null:
return validatingPdf(_that);case AcquisitionEvent_Completed() when completed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AcquisitionEvent_Failed value)  failed,required TResult Function( AcquisitionEvent_ResolvingMetadata value)  resolvingMetadata,required TResult Function( AcquisitionEvent_MetadataSaved value)  metadataSaved,required TResult Function( AcquisitionEvent_Downloading value)  downloading,required TResult Function( AcquisitionEvent_ValidatingPdf value)  validatingPdf,required TResult Function( AcquisitionEvent_Completed value)  completed,}){
final _that = this;
switch (_that) {
case AcquisitionEvent_Failed():
return failed(_that);case AcquisitionEvent_ResolvingMetadata():
return resolvingMetadata(_that);case AcquisitionEvent_MetadataSaved():
return metadataSaved(_that);case AcquisitionEvent_Downloading():
return downloading(_that);case AcquisitionEvent_ValidatingPdf():
return validatingPdf(_that);case AcquisitionEvent_Completed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AcquisitionEvent_Failed value)?  failed,TResult? Function( AcquisitionEvent_ResolvingMetadata value)?  resolvingMetadata,TResult? Function( AcquisitionEvent_MetadataSaved value)?  metadataSaved,TResult? Function( AcquisitionEvent_Downloading value)?  downloading,TResult? Function( AcquisitionEvent_ValidatingPdf value)?  validatingPdf,TResult? Function( AcquisitionEvent_Completed value)?  completed,}){
final _that = this;
switch (_that) {
case AcquisitionEvent_Failed() when failed != null:
return failed(_that);case AcquisitionEvent_ResolvingMetadata() when resolvingMetadata != null:
return resolvingMetadata(_that);case AcquisitionEvent_MetadataSaved() when metadataSaved != null:
return metadataSaved(_that);case AcquisitionEvent_Downloading() when downloading != null:
return downloading(_that);case AcquisitionEvent_ValidatingPdf() when validatingPdf != null:
return validatingPdf(_that);case AcquisitionEvent_Completed() when completed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OtterError error)?  failed,TResult Function()?  resolvingMetadata,TResult Function( Document document,  bool duplicate)?  metadataSaved,TResult Function( TransferProgress progress)?  downloading,TResult Function()?  validatingPdf,TResult Function( PdfDownloadReport report)?  completed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AcquisitionEvent_Failed() when failed != null:
return failed(_that.error);case AcquisitionEvent_ResolvingMetadata() when resolvingMetadata != null:
return resolvingMetadata();case AcquisitionEvent_MetadataSaved() when metadataSaved != null:
return metadataSaved(_that.document,_that.duplicate);case AcquisitionEvent_Downloading() when downloading != null:
return downloading(_that.progress);case AcquisitionEvent_ValidatingPdf() when validatingPdf != null:
return validatingPdf();case AcquisitionEvent_Completed() when completed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OtterError error)  failed,required TResult Function()  resolvingMetadata,required TResult Function( Document document,  bool duplicate)  metadataSaved,required TResult Function( TransferProgress progress)  downloading,required TResult Function()  validatingPdf,required TResult Function( PdfDownloadReport report)  completed,}) {final _that = this;
switch (_that) {
case AcquisitionEvent_Failed():
return failed(_that.error);case AcquisitionEvent_ResolvingMetadata():
return resolvingMetadata();case AcquisitionEvent_MetadataSaved():
return metadataSaved(_that.document,_that.duplicate);case AcquisitionEvent_Downloading():
return downloading(_that.progress);case AcquisitionEvent_ValidatingPdf():
return validatingPdf();case AcquisitionEvent_Completed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OtterError error)?  failed,TResult? Function()?  resolvingMetadata,TResult? Function( Document document,  bool duplicate)?  metadataSaved,TResult? Function( TransferProgress progress)?  downloading,TResult? Function()?  validatingPdf,TResult? Function( PdfDownloadReport report)?  completed,}) {final _that = this;
switch (_that) {
case AcquisitionEvent_Failed() when failed != null:
return failed(_that.error);case AcquisitionEvent_ResolvingMetadata() when resolvingMetadata != null:
return resolvingMetadata();case AcquisitionEvent_MetadataSaved() when metadataSaved != null:
return metadataSaved(_that.document,_that.duplicate);case AcquisitionEvent_Downloading() when downloading != null:
return downloading(_that.progress);case AcquisitionEvent_ValidatingPdf() when validatingPdf != null:
return validatingPdf();case AcquisitionEvent_Completed() when completed != null:
return completed(_that.report);case _:
  return null;

}
}

}

/// @nodoc


class AcquisitionEvent_Failed extends AcquisitionEvent {
  const AcquisitionEvent_Failed({required this.error}): super._();
  

 final  OtterError error;

/// Create a copy of AcquisitionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcquisitionEvent_FailedCopyWith<AcquisitionEvent_Failed> get copyWith => _$AcquisitionEvent_FailedCopyWithImpl<AcquisitionEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcquisitionEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'AcquisitionEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $AcquisitionEvent_FailedCopyWith<$Res> implements $AcquisitionEventCopyWith<$Res> {
  factory $AcquisitionEvent_FailedCopyWith(AcquisitionEvent_Failed value, $Res Function(AcquisitionEvent_Failed) _then) = _$AcquisitionEvent_FailedCopyWithImpl;
@useResult
$Res call({
 OtterError error
});




}
/// @nodoc
class _$AcquisitionEvent_FailedCopyWithImpl<$Res>
    implements $AcquisitionEvent_FailedCopyWith<$Res> {
  _$AcquisitionEvent_FailedCopyWithImpl(this._self, this._then);

  final AcquisitionEvent_Failed _self;
  final $Res Function(AcquisitionEvent_Failed) _then;

/// Create a copy of AcquisitionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(AcquisitionEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as OtterError,
  ));
}


}

/// @nodoc


class AcquisitionEvent_ResolvingMetadata extends AcquisitionEvent {
  const AcquisitionEvent_ResolvingMetadata(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcquisitionEvent_ResolvingMetadata);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AcquisitionEvent.resolvingMetadata()';
}


}




/// @nodoc


class AcquisitionEvent_MetadataSaved extends AcquisitionEvent {
  const AcquisitionEvent_MetadataSaved({required this.document, required this.duplicate}): super._();
  

 final  Document document;
 final  bool duplicate;

/// Create a copy of AcquisitionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcquisitionEvent_MetadataSavedCopyWith<AcquisitionEvent_MetadataSaved> get copyWith => _$AcquisitionEvent_MetadataSavedCopyWithImpl<AcquisitionEvent_MetadataSaved>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcquisitionEvent_MetadataSaved&&(identical(other.document, document) || other.document == document)&&(identical(other.duplicate, duplicate) || other.duplicate == duplicate));
}


@override
int get hashCode => Object.hash(runtimeType,document,duplicate);

@override
String toString() {
  return 'AcquisitionEvent.metadataSaved(document: $document, duplicate: $duplicate)';
}


}

/// @nodoc
abstract mixin class $AcquisitionEvent_MetadataSavedCopyWith<$Res> implements $AcquisitionEventCopyWith<$Res> {
  factory $AcquisitionEvent_MetadataSavedCopyWith(AcquisitionEvent_MetadataSaved value, $Res Function(AcquisitionEvent_MetadataSaved) _then) = _$AcquisitionEvent_MetadataSavedCopyWithImpl;
@useResult
$Res call({
 Document document, bool duplicate
});




}
/// @nodoc
class _$AcquisitionEvent_MetadataSavedCopyWithImpl<$Res>
    implements $AcquisitionEvent_MetadataSavedCopyWith<$Res> {
  _$AcquisitionEvent_MetadataSavedCopyWithImpl(this._self, this._then);

  final AcquisitionEvent_MetadataSaved _self;
  final $Res Function(AcquisitionEvent_MetadataSaved) _then;

/// Create a copy of AcquisitionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? document = null,Object? duplicate = null,}) {
  return _then(AcquisitionEvent_MetadataSaved(
document: null == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as Document,duplicate: null == duplicate ? _self.duplicate : duplicate // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class AcquisitionEvent_Downloading extends AcquisitionEvent {
  const AcquisitionEvent_Downloading({required this.progress}): super._();
  

 final  TransferProgress progress;

/// Create a copy of AcquisitionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcquisitionEvent_DownloadingCopyWith<AcquisitionEvent_Downloading> get copyWith => _$AcquisitionEvent_DownloadingCopyWithImpl<AcquisitionEvent_Downloading>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcquisitionEvent_Downloading&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode => Object.hash(runtimeType,progress);

@override
String toString() {
  return 'AcquisitionEvent.downloading(progress: $progress)';
}


}

/// @nodoc
abstract mixin class $AcquisitionEvent_DownloadingCopyWith<$Res> implements $AcquisitionEventCopyWith<$Res> {
  factory $AcquisitionEvent_DownloadingCopyWith(AcquisitionEvent_Downloading value, $Res Function(AcquisitionEvent_Downloading) _then) = _$AcquisitionEvent_DownloadingCopyWithImpl;
@useResult
$Res call({
 TransferProgress progress
});




}
/// @nodoc
class _$AcquisitionEvent_DownloadingCopyWithImpl<$Res>
    implements $AcquisitionEvent_DownloadingCopyWith<$Res> {
  _$AcquisitionEvent_DownloadingCopyWithImpl(this._self, this._then);

  final AcquisitionEvent_Downloading _self;
  final $Res Function(AcquisitionEvent_Downloading) _then;

/// Create a copy of AcquisitionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? progress = null,}) {
  return _then(AcquisitionEvent_Downloading(
progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as TransferProgress,
  ));
}


}

/// @nodoc


class AcquisitionEvent_ValidatingPdf extends AcquisitionEvent {
  const AcquisitionEvent_ValidatingPdf(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcquisitionEvent_ValidatingPdf);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AcquisitionEvent.validatingPdf()';
}


}




/// @nodoc


class AcquisitionEvent_Completed extends AcquisitionEvent {
  const AcquisitionEvent_Completed({required this.report}): super._();
  

 final  PdfDownloadReport report;

/// Create a copy of AcquisitionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcquisitionEvent_CompletedCopyWith<AcquisitionEvent_Completed> get copyWith => _$AcquisitionEvent_CompletedCopyWithImpl<AcquisitionEvent_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcquisitionEvent_Completed&&(identical(other.report, report) || other.report == report));
}


@override
int get hashCode => Object.hash(runtimeType,report);

@override
String toString() {
  return 'AcquisitionEvent.completed(report: $report)';
}


}

/// @nodoc
abstract mixin class $AcquisitionEvent_CompletedCopyWith<$Res> implements $AcquisitionEventCopyWith<$Res> {
  factory $AcquisitionEvent_CompletedCopyWith(AcquisitionEvent_Completed value, $Res Function(AcquisitionEvent_Completed) _then) = _$AcquisitionEvent_CompletedCopyWithImpl;
@useResult
$Res call({
 PdfDownloadReport report
});




}
/// @nodoc
class _$AcquisitionEvent_CompletedCopyWithImpl<$Res>
    implements $AcquisitionEvent_CompletedCopyWith<$Res> {
  _$AcquisitionEvent_CompletedCopyWithImpl(this._self, this._then);

  final AcquisitionEvent_Completed _self;
  final $Res Function(AcquisitionEvent_Completed) _then;

/// Create a copy of AcquisitionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? report = null,}) {
  return _then(AcquisitionEvent_Completed(
report: null == report ? _self.report : report // ignore: cast_nullable_to_non_nullable
as PdfDownloadReport,
  ));
}


}

// dart format on
