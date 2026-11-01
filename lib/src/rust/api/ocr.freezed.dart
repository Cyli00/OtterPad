// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ocr.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ExtractionBatchEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtractionBatchEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ExtractionBatchEvent()';
}


}

/// @nodoc
class $ExtractionBatchEventCopyWith<$Res>  {
$ExtractionBatchEventCopyWith(ExtractionBatchEvent _, $Res Function(ExtractionBatchEvent) __);
}


/// Adds pattern-matching-related methods to [ExtractionBatchEvent].
extension ExtractionBatchEventPatterns on ExtractionBatchEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ExtractionBatchEvent_Failed value)?  failed,TResult Function( ExtractionBatchEvent_Document value)?  document,TResult Function( ExtractionBatchEvent_Completed value)?  completed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ExtractionBatchEvent_Failed() when failed != null:
return failed(_that);case ExtractionBatchEvent_Document() when document != null:
return document(_that);case ExtractionBatchEvent_Completed() when completed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ExtractionBatchEvent_Failed value)  failed,required TResult Function( ExtractionBatchEvent_Document value)  document,required TResult Function( ExtractionBatchEvent_Completed value)  completed,}){
final _that = this;
switch (_that) {
case ExtractionBatchEvent_Failed():
return failed(_that);case ExtractionBatchEvent_Document():
return document(_that);case ExtractionBatchEvent_Completed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ExtractionBatchEvent_Failed value)?  failed,TResult? Function( ExtractionBatchEvent_Document value)?  document,TResult? Function( ExtractionBatchEvent_Completed value)?  completed,}){
final _that = this;
switch (_that) {
case ExtractionBatchEvent_Failed() when failed != null:
return failed(_that);case ExtractionBatchEvent_Document() when document != null:
return document(_that);case ExtractionBatchEvent_Completed() when completed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OtterError error)?  failed,TResult Function( String documentId,  ExtractionEvent event)?  document,TResult Function( int succeeded,  int failed,  int cancelled)?  completed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ExtractionBatchEvent_Failed() when failed != null:
return failed(_that.error);case ExtractionBatchEvent_Document() when document != null:
return document(_that.documentId,_that.event);case ExtractionBatchEvent_Completed() when completed != null:
return completed(_that.succeeded,_that.failed,_that.cancelled);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OtterError error)  failed,required TResult Function( String documentId,  ExtractionEvent event)  document,required TResult Function( int succeeded,  int failed,  int cancelled)  completed,}) {final _that = this;
switch (_that) {
case ExtractionBatchEvent_Failed():
return failed(_that.error);case ExtractionBatchEvent_Document():
return document(_that.documentId,_that.event);case ExtractionBatchEvent_Completed():
return completed(_that.succeeded,_that.failed,_that.cancelled);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OtterError error)?  failed,TResult? Function( String documentId,  ExtractionEvent event)?  document,TResult? Function( int succeeded,  int failed,  int cancelled)?  completed,}) {final _that = this;
switch (_that) {
case ExtractionBatchEvent_Failed() when failed != null:
return failed(_that.error);case ExtractionBatchEvent_Document() when document != null:
return document(_that.documentId,_that.event);case ExtractionBatchEvent_Completed() when completed != null:
return completed(_that.succeeded,_that.failed,_that.cancelled);case _:
  return null;

}
}

}

/// @nodoc


class ExtractionBatchEvent_Failed extends ExtractionBatchEvent {
  const ExtractionBatchEvent_Failed({required this.error}): super._();
  

 final  OtterError error;

/// Create a copy of ExtractionBatchEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExtractionBatchEvent_FailedCopyWith<ExtractionBatchEvent_Failed> get copyWith => _$ExtractionBatchEvent_FailedCopyWithImpl<ExtractionBatchEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtractionBatchEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'ExtractionBatchEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $ExtractionBatchEvent_FailedCopyWith<$Res> implements $ExtractionBatchEventCopyWith<$Res> {
  factory $ExtractionBatchEvent_FailedCopyWith(ExtractionBatchEvent_Failed value, $Res Function(ExtractionBatchEvent_Failed) _then) = _$ExtractionBatchEvent_FailedCopyWithImpl;
@useResult
$Res call({
 OtterError error
});




}
/// @nodoc
class _$ExtractionBatchEvent_FailedCopyWithImpl<$Res>
    implements $ExtractionBatchEvent_FailedCopyWith<$Res> {
  _$ExtractionBatchEvent_FailedCopyWithImpl(this._self, this._then);

  final ExtractionBatchEvent_Failed _self;
  final $Res Function(ExtractionBatchEvent_Failed) _then;

/// Create a copy of ExtractionBatchEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(ExtractionBatchEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as OtterError,
  ));
}


}

/// @nodoc


class ExtractionBatchEvent_Document extends ExtractionBatchEvent {
  const ExtractionBatchEvent_Document({required this.documentId, required this.event}): super._();
  

 final  String documentId;
 final  ExtractionEvent event;

/// Create a copy of ExtractionBatchEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExtractionBatchEvent_DocumentCopyWith<ExtractionBatchEvent_Document> get copyWith => _$ExtractionBatchEvent_DocumentCopyWithImpl<ExtractionBatchEvent_Document>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtractionBatchEvent_Document&&(identical(other.documentId, documentId) || other.documentId == documentId)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode => Object.hash(runtimeType,documentId,event);

@override
String toString() {
  return 'ExtractionBatchEvent.document(documentId: $documentId, event: $event)';
}


}

/// @nodoc
abstract mixin class $ExtractionBatchEvent_DocumentCopyWith<$Res> implements $ExtractionBatchEventCopyWith<$Res> {
  factory $ExtractionBatchEvent_DocumentCopyWith(ExtractionBatchEvent_Document value, $Res Function(ExtractionBatchEvent_Document) _then) = _$ExtractionBatchEvent_DocumentCopyWithImpl;
@useResult
$Res call({
 String documentId, ExtractionEvent event
});


$ExtractionEventCopyWith<$Res> get event;

}
/// @nodoc
class _$ExtractionBatchEvent_DocumentCopyWithImpl<$Res>
    implements $ExtractionBatchEvent_DocumentCopyWith<$Res> {
  _$ExtractionBatchEvent_DocumentCopyWithImpl(this._self, this._then);

  final ExtractionBatchEvent_Document _self;
  final $Res Function(ExtractionBatchEvent_Document) _then;

/// Create a copy of ExtractionBatchEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? documentId = null,Object? event = null,}) {
  return _then(ExtractionBatchEvent_Document(
documentId: null == documentId ? _self.documentId : documentId // ignore: cast_nullable_to_non_nullable
as String,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as ExtractionEvent,
  ));
}

/// Create a copy of ExtractionBatchEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ExtractionEventCopyWith<$Res> get event {
  
  return $ExtractionEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class ExtractionBatchEvent_Completed extends ExtractionBatchEvent {
  const ExtractionBatchEvent_Completed({required this.succeeded, required this.failed, required this.cancelled}): super._();
  

 final  int succeeded;
 final  int failed;
 final  int cancelled;

/// Create a copy of ExtractionBatchEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExtractionBatchEvent_CompletedCopyWith<ExtractionBatchEvent_Completed> get copyWith => _$ExtractionBatchEvent_CompletedCopyWithImpl<ExtractionBatchEvent_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtractionBatchEvent_Completed&&(identical(other.succeeded, succeeded) || other.succeeded == succeeded)&&(identical(other.failed, failed) || other.failed == failed)&&(identical(other.cancelled, cancelled) || other.cancelled == cancelled));
}


@override
int get hashCode => Object.hash(runtimeType,succeeded,failed,cancelled);

@override
String toString() {
  return 'ExtractionBatchEvent.completed(succeeded: $succeeded, failed: $failed, cancelled: $cancelled)';
}


}

/// @nodoc
abstract mixin class $ExtractionBatchEvent_CompletedCopyWith<$Res> implements $ExtractionBatchEventCopyWith<$Res> {
  factory $ExtractionBatchEvent_CompletedCopyWith(ExtractionBatchEvent_Completed value, $Res Function(ExtractionBatchEvent_Completed) _then) = _$ExtractionBatchEvent_CompletedCopyWithImpl;
@useResult
$Res call({
 int succeeded, int failed, int cancelled
});




}
/// @nodoc
class _$ExtractionBatchEvent_CompletedCopyWithImpl<$Res>
    implements $ExtractionBatchEvent_CompletedCopyWith<$Res> {
  _$ExtractionBatchEvent_CompletedCopyWithImpl(this._self, this._then);

  final ExtractionBatchEvent_Completed _self;
  final $Res Function(ExtractionBatchEvent_Completed) _then;

/// Create a copy of ExtractionBatchEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? succeeded = null,Object? failed = null,Object? cancelled = null,}) {
  return _then(ExtractionBatchEvent_Completed(
succeeded: null == succeeded ? _self.succeeded : succeeded // ignore: cast_nullable_to_non_nullable
as int,failed: null == failed ? _self.failed : failed // ignore: cast_nullable_to_non_nullable
as int,cancelled: null == cancelled ? _self.cancelled : cancelled // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ExtractionEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtractionEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ExtractionEvent()';
}


}

/// @nodoc
class $ExtractionEventCopyWith<$Res>  {
$ExtractionEventCopyWith(ExtractionEvent _, $Res Function(ExtractionEvent) __);
}


/// Adds pattern-matching-related methods to [ExtractionEvent].
extension ExtractionEventPatterns on ExtractionEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ExtractionEvent_Failed value)?  failed,TResult Function( ExtractionEvent_Progress value)?  progress,TResult Function( ExtractionEvent_Published value)?  published,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ExtractionEvent_Failed() when failed != null:
return failed(_that);case ExtractionEvent_Progress() when progress != null:
return progress(_that);case ExtractionEvent_Published() when published != null:
return published(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ExtractionEvent_Failed value)  failed,required TResult Function( ExtractionEvent_Progress value)  progress,required TResult Function( ExtractionEvent_Published value)  published,}){
final _that = this;
switch (_that) {
case ExtractionEvent_Failed():
return failed(_that);case ExtractionEvent_Progress():
return progress(_that);case ExtractionEvent_Published():
return published(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ExtractionEvent_Failed value)?  failed,TResult? Function( ExtractionEvent_Progress value)?  progress,TResult? Function( ExtractionEvent_Published value)?  published,}){
final _that = this;
switch (_that) {
case ExtractionEvent_Failed() when failed != null:
return failed(_that);case ExtractionEvent_Progress() when progress != null:
return progress(_that);case ExtractionEvent_Published() when published != null:
return published(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OtterError error)?  failed,TResult Function( Progress progress)?  progress,TResult Function( String documentId,  String generation)?  published,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ExtractionEvent_Failed() when failed != null:
return failed(_that.error);case ExtractionEvent_Progress() when progress != null:
return progress(_that.progress);case ExtractionEvent_Published() when published != null:
return published(_that.documentId,_that.generation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OtterError error)  failed,required TResult Function( Progress progress)  progress,required TResult Function( String documentId,  String generation)  published,}) {final _that = this;
switch (_that) {
case ExtractionEvent_Failed():
return failed(_that.error);case ExtractionEvent_Progress():
return progress(_that.progress);case ExtractionEvent_Published():
return published(_that.documentId,_that.generation);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OtterError error)?  failed,TResult? Function( Progress progress)?  progress,TResult? Function( String documentId,  String generation)?  published,}) {final _that = this;
switch (_that) {
case ExtractionEvent_Failed() when failed != null:
return failed(_that.error);case ExtractionEvent_Progress() when progress != null:
return progress(_that.progress);case ExtractionEvent_Published() when published != null:
return published(_that.documentId,_that.generation);case _:
  return null;

}
}

}

/// @nodoc


class ExtractionEvent_Failed extends ExtractionEvent {
  const ExtractionEvent_Failed({required this.error}): super._();
  

 final  OtterError error;

/// Create a copy of ExtractionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExtractionEvent_FailedCopyWith<ExtractionEvent_Failed> get copyWith => _$ExtractionEvent_FailedCopyWithImpl<ExtractionEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtractionEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'ExtractionEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $ExtractionEvent_FailedCopyWith<$Res> implements $ExtractionEventCopyWith<$Res> {
  factory $ExtractionEvent_FailedCopyWith(ExtractionEvent_Failed value, $Res Function(ExtractionEvent_Failed) _then) = _$ExtractionEvent_FailedCopyWithImpl;
@useResult
$Res call({
 OtterError error
});




}
/// @nodoc
class _$ExtractionEvent_FailedCopyWithImpl<$Res>
    implements $ExtractionEvent_FailedCopyWith<$Res> {
  _$ExtractionEvent_FailedCopyWithImpl(this._self, this._then);

  final ExtractionEvent_Failed _self;
  final $Res Function(ExtractionEvent_Failed) _then;

/// Create a copy of ExtractionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(ExtractionEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as OtterError,
  ));
}


}

/// @nodoc


class ExtractionEvent_Progress extends ExtractionEvent {
  const ExtractionEvent_Progress({required this.progress}): super._();
  

 final  Progress progress;

/// Create a copy of ExtractionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExtractionEvent_ProgressCopyWith<ExtractionEvent_Progress> get copyWith => _$ExtractionEvent_ProgressCopyWithImpl<ExtractionEvent_Progress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtractionEvent_Progress&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode => Object.hash(runtimeType,progress);

@override
String toString() {
  return 'ExtractionEvent.progress(progress: $progress)';
}


}

/// @nodoc
abstract mixin class $ExtractionEvent_ProgressCopyWith<$Res> implements $ExtractionEventCopyWith<$Res> {
  factory $ExtractionEvent_ProgressCopyWith(ExtractionEvent_Progress value, $Res Function(ExtractionEvent_Progress) _then) = _$ExtractionEvent_ProgressCopyWithImpl;
@useResult
$Res call({
 Progress progress
});




}
/// @nodoc
class _$ExtractionEvent_ProgressCopyWithImpl<$Res>
    implements $ExtractionEvent_ProgressCopyWith<$Res> {
  _$ExtractionEvent_ProgressCopyWithImpl(this._self, this._then);

  final ExtractionEvent_Progress _self;
  final $Res Function(ExtractionEvent_Progress) _then;

/// Create a copy of ExtractionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? progress = null,}) {
  return _then(ExtractionEvent_Progress(
progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as Progress,
  ));
}


}

/// @nodoc


class ExtractionEvent_Published extends ExtractionEvent {
  const ExtractionEvent_Published({required this.documentId, required this.generation}): super._();
  

 final  String documentId;
 final  String generation;

/// Create a copy of ExtractionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExtractionEvent_PublishedCopyWith<ExtractionEvent_Published> get copyWith => _$ExtractionEvent_PublishedCopyWithImpl<ExtractionEvent_Published>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtractionEvent_Published&&(identical(other.documentId, documentId) || other.documentId == documentId)&&(identical(other.generation, generation) || other.generation == generation));
}


@override
int get hashCode => Object.hash(runtimeType,documentId,generation);

@override
String toString() {
  return 'ExtractionEvent.published(documentId: $documentId, generation: $generation)';
}


}

/// @nodoc
abstract mixin class $ExtractionEvent_PublishedCopyWith<$Res> implements $ExtractionEventCopyWith<$Res> {
  factory $ExtractionEvent_PublishedCopyWith(ExtractionEvent_Published value, $Res Function(ExtractionEvent_Published) _then) = _$ExtractionEvent_PublishedCopyWithImpl;
@useResult
$Res call({
 String documentId, String generation
});




}
/// @nodoc
class _$ExtractionEvent_PublishedCopyWithImpl<$Res>
    implements $ExtractionEvent_PublishedCopyWith<$Res> {
  _$ExtractionEvent_PublishedCopyWithImpl(this._self, this._then);

  final ExtractionEvent_Published _self;
  final $Res Function(ExtractionEvent_Published) _then;

/// Create a copy of ExtractionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? documentId = null,Object? generation = null,}) {
  return _then(ExtractionEvent_Published(
documentId: null == documentId ? _self.documentId : documentId // ignore: cast_nullable_to_non_nullable
as String,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ExtractionProvider {

 Object get options;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtractionProvider&&const DeepCollectionEquality().equals(other.options, options));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(options));

@override
String toString() {
  return 'ExtractionProvider(options: $options)';
}


}

/// @nodoc
class $ExtractionProviderCopyWith<$Res>  {
$ExtractionProviderCopyWith(ExtractionProvider _, $Res Function(ExtractionProvider) __);
}


/// Adds pattern-matching-related methods to [ExtractionProvider].
extension ExtractionProviderPatterns on ExtractionProvider {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ExtractionProvider_PaddleJob value)?  paddleJob,TResult Function( ExtractionProvider_Paddle value)?  paddle,TResult Function( ExtractionProvider_Mineru value)?  mineru,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ExtractionProvider_PaddleJob() when paddleJob != null:
return paddleJob(_that);case ExtractionProvider_Paddle() when paddle != null:
return paddle(_that);case ExtractionProvider_Mineru() when mineru != null:
return mineru(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ExtractionProvider_PaddleJob value)  paddleJob,required TResult Function( ExtractionProvider_Paddle value)  paddle,required TResult Function( ExtractionProvider_Mineru value)  mineru,}){
final _that = this;
switch (_that) {
case ExtractionProvider_PaddleJob():
return paddleJob(_that);case ExtractionProvider_Paddle():
return paddle(_that);case ExtractionProvider_Mineru():
return mineru(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ExtractionProvider_PaddleJob value)?  paddleJob,TResult? Function( ExtractionProvider_Paddle value)?  paddle,TResult? Function( ExtractionProvider_Mineru value)?  mineru,}){
final _that = this;
switch (_that) {
case ExtractionProvider_PaddleJob() when paddleJob != null:
return paddleJob(_that);case ExtractionProvider_Paddle() when paddle != null:
return paddle(_that);case ExtractionProvider_Mineru() when mineru != null:
return mineru(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String jobUrl,  PaddleOptions options)?  paddleJob,TResult Function( String url,  PaddleOptions options)?  paddle,TResult Function( String baseUrl,  MineruOptions options)?  mineru,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ExtractionProvider_PaddleJob() when paddleJob != null:
return paddleJob(_that.jobUrl,_that.options);case ExtractionProvider_Paddle() when paddle != null:
return paddle(_that.url,_that.options);case ExtractionProvider_Mineru() when mineru != null:
return mineru(_that.baseUrl,_that.options);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String jobUrl,  PaddleOptions options)  paddleJob,required TResult Function( String url,  PaddleOptions options)  paddle,required TResult Function( String baseUrl,  MineruOptions options)  mineru,}) {final _that = this;
switch (_that) {
case ExtractionProvider_PaddleJob():
return paddleJob(_that.jobUrl,_that.options);case ExtractionProvider_Paddle():
return paddle(_that.url,_that.options);case ExtractionProvider_Mineru():
return mineru(_that.baseUrl,_that.options);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String jobUrl,  PaddleOptions options)?  paddleJob,TResult? Function( String url,  PaddleOptions options)?  paddle,TResult? Function( String baseUrl,  MineruOptions options)?  mineru,}) {final _that = this;
switch (_that) {
case ExtractionProvider_PaddleJob() when paddleJob != null:
return paddleJob(_that.jobUrl,_that.options);case ExtractionProvider_Paddle() when paddle != null:
return paddle(_that.url,_that.options);case ExtractionProvider_Mineru() when mineru != null:
return mineru(_that.baseUrl,_that.options);case _:
  return null;

}
}

}

/// @nodoc


class ExtractionProvider_PaddleJob extends ExtractionProvider {
  const ExtractionProvider_PaddleJob({required this.jobUrl, required this.options}): super._();
  

 final  String jobUrl;
@override final  PaddleOptions options;

/// Create a copy of ExtractionProvider
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExtractionProvider_PaddleJobCopyWith<ExtractionProvider_PaddleJob> get copyWith => _$ExtractionProvider_PaddleJobCopyWithImpl<ExtractionProvider_PaddleJob>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtractionProvider_PaddleJob&&(identical(other.jobUrl, jobUrl) || other.jobUrl == jobUrl)&&(identical(other.options, options) || other.options == options));
}


@override
int get hashCode => Object.hash(runtimeType,jobUrl,options);

@override
String toString() {
  return 'ExtractionProvider.paddleJob(jobUrl: $jobUrl, options: $options)';
}


}

/// @nodoc
abstract mixin class $ExtractionProvider_PaddleJobCopyWith<$Res> implements $ExtractionProviderCopyWith<$Res> {
  factory $ExtractionProvider_PaddleJobCopyWith(ExtractionProvider_PaddleJob value, $Res Function(ExtractionProvider_PaddleJob) _then) = _$ExtractionProvider_PaddleJobCopyWithImpl;
@useResult
$Res call({
 String jobUrl, PaddleOptions options
});




}
/// @nodoc
class _$ExtractionProvider_PaddleJobCopyWithImpl<$Res>
    implements $ExtractionProvider_PaddleJobCopyWith<$Res> {
  _$ExtractionProvider_PaddleJobCopyWithImpl(this._self, this._then);

  final ExtractionProvider_PaddleJob _self;
  final $Res Function(ExtractionProvider_PaddleJob) _then;

/// Create a copy of ExtractionProvider
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? jobUrl = null,Object? options = null,}) {
  return _then(ExtractionProvider_PaddleJob(
jobUrl: null == jobUrl ? _self.jobUrl : jobUrl // ignore: cast_nullable_to_non_nullable
as String,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as PaddleOptions,
  ));
}


}

/// @nodoc


class ExtractionProvider_Paddle extends ExtractionProvider {
  const ExtractionProvider_Paddle({required this.url, required this.options}): super._();
  

 final  String url;
@override final  PaddleOptions options;

/// Create a copy of ExtractionProvider
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExtractionProvider_PaddleCopyWith<ExtractionProvider_Paddle> get copyWith => _$ExtractionProvider_PaddleCopyWithImpl<ExtractionProvider_Paddle>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtractionProvider_Paddle&&(identical(other.url, url) || other.url == url)&&(identical(other.options, options) || other.options == options));
}


@override
int get hashCode => Object.hash(runtimeType,url,options);

@override
String toString() {
  return 'ExtractionProvider.paddle(url: $url, options: $options)';
}


}

/// @nodoc
abstract mixin class $ExtractionProvider_PaddleCopyWith<$Res> implements $ExtractionProviderCopyWith<$Res> {
  factory $ExtractionProvider_PaddleCopyWith(ExtractionProvider_Paddle value, $Res Function(ExtractionProvider_Paddle) _then) = _$ExtractionProvider_PaddleCopyWithImpl;
@useResult
$Res call({
 String url, PaddleOptions options
});




}
/// @nodoc
class _$ExtractionProvider_PaddleCopyWithImpl<$Res>
    implements $ExtractionProvider_PaddleCopyWith<$Res> {
  _$ExtractionProvider_PaddleCopyWithImpl(this._self, this._then);

  final ExtractionProvider_Paddle _self;
  final $Res Function(ExtractionProvider_Paddle) _then;

/// Create a copy of ExtractionProvider
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? url = null,Object? options = null,}) {
  return _then(ExtractionProvider_Paddle(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as PaddleOptions,
  ));
}


}

/// @nodoc


class ExtractionProvider_Mineru extends ExtractionProvider {
  const ExtractionProvider_Mineru({required this.baseUrl, required this.options}): super._();
  

 final  String baseUrl;
@override final  MineruOptions options;

/// Create a copy of ExtractionProvider
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExtractionProvider_MineruCopyWith<ExtractionProvider_Mineru> get copyWith => _$ExtractionProvider_MineruCopyWithImpl<ExtractionProvider_Mineru>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtractionProvider_Mineru&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.options, options) || other.options == options));
}


@override
int get hashCode => Object.hash(runtimeType,baseUrl,options);

@override
String toString() {
  return 'ExtractionProvider.mineru(baseUrl: $baseUrl, options: $options)';
}


}

/// @nodoc
abstract mixin class $ExtractionProvider_MineruCopyWith<$Res> implements $ExtractionProviderCopyWith<$Res> {
  factory $ExtractionProvider_MineruCopyWith(ExtractionProvider_Mineru value, $Res Function(ExtractionProvider_Mineru) _then) = _$ExtractionProvider_MineruCopyWithImpl;
@useResult
$Res call({
 String baseUrl, MineruOptions options
});




}
/// @nodoc
class _$ExtractionProvider_MineruCopyWithImpl<$Res>
    implements $ExtractionProvider_MineruCopyWith<$Res> {
  _$ExtractionProvider_MineruCopyWithImpl(this._self, this._then);

  final ExtractionProvider_Mineru _self;
  final $Res Function(ExtractionProvider_Mineru) _then;

/// Create a copy of ExtractionProvider
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? baseUrl = null,Object? options = null,}) {
  return _then(ExtractionProvider_Mineru(
baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as MineruOptions,
  ));
}


}

// dart format on
