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
mixin _$TranslateEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TranslateEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TranslateEvent()';
}


}

/// @nodoc
class $TranslateEventCopyWith<$Res>  {
$TranslateEventCopyWith(TranslateEvent _, $Res Function(TranslateEvent) __);
}


/// Adds pattern-matching-related methods to [TranslateEvent].
extension TranslateEventPatterns on TranslateEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TranslateEvent_Failed value)?  failed,TResult Function( TranslateEvent_Snapshot value)?  snapshot,TResult Function( TranslateEvent_Paragraph value)?  paragraph,TResult Function( TranslateEvent_Completed value)?  completed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TranslateEvent_Failed() when failed != null:
return failed(_that);case TranslateEvent_Snapshot() when snapshot != null:
return snapshot(_that);case TranslateEvent_Paragraph() when paragraph != null:
return paragraph(_that);case TranslateEvent_Completed() when completed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TranslateEvent_Failed value)  failed,required TResult Function( TranslateEvent_Snapshot value)  snapshot,required TResult Function( TranslateEvent_Paragraph value)  paragraph,required TResult Function( TranslateEvent_Completed value)  completed,}){
final _that = this;
switch (_that) {
case TranslateEvent_Failed():
return failed(_that);case TranslateEvent_Snapshot():
return snapshot(_that);case TranslateEvent_Paragraph():
return paragraph(_that);case TranslateEvent_Completed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TranslateEvent_Failed value)?  failed,TResult? Function( TranslateEvent_Snapshot value)?  snapshot,TResult? Function( TranslateEvent_Paragraph value)?  paragraph,TResult? Function( TranslateEvent_Completed value)?  completed,}){
final _that = this;
switch (_that) {
case TranslateEvent_Failed() when failed != null:
return failed(_that);case TranslateEvent_Snapshot() when snapshot != null:
return snapshot(_that);case TranslateEvent_Paragraph() when paragraph != null:
return paragraph(_that);case TranslateEvent_Completed() when completed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OtterError error)?  failed,TResult Function( String text)?  snapshot,TResult Function( TranslationEvent event)?  paragraph,TResult Function( TranslationReport report)?  completed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TranslateEvent_Failed() when failed != null:
return failed(_that.error);case TranslateEvent_Snapshot() when snapshot != null:
return snapshot(_that.text);case TranslateEvent_Paragraph() when paragraph != null:
return paragraph(_that.event);case TranslateEvent_Completed() when completed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OtterError error)  failed,required TResult Function( String text)  snapshot,required TResult Function( TranslationEvent event)  paragraph,required TResult Function( TranslationReport report)  completed,}) {final _that = this;
switch (_that) {
case TranslateEvent_Failed():
return failed(_that.error);case TranslateEvent_Snapshot():
return snapshot(_that.text);case TranslateEvent_Paragraph():
return paragraph(_that.event);case TranslateEvent_Completed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OtterError error)?  failed,TResult? Function( String text)?  snapshot,TResult? Function( TranslationEvent event)?  paragraph,TResult? Function( TranslationReport report)?  completed,}) {final _that = this;
switch (_that) {
case TranslateEvent_Failed() when failed != null:
return failed(_that.error);case TranslateEvent_Snapshot() when snapshot != null:
return snapshot(_that.text);case TranslateEvent_Paragraph() when paragraph != null:
return paragraph(_that.event);case TranslateEvent_Completed() when completed != null:
return completed(_that.report);case _:
  return null;

}
}

}

/// @nodoc


class TranslateEvent_Failed extends TranslateEvent {
  const TranslateEvent_Failed({required this.error}): super._();
  

 final  OtterError error;

/// Create a copy of TranslateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TranslateEvent_FailedCopyWith<TranslateEvent_Failed> get copyWith => _$TranslateEvent_FailedCopyWithImpl<TranslateEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TranslateEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'TranslateEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $TranslateEvent_FailedCopyWith<$Res> implements $TranslateEventCopyWith<$Res> {
  factory $TranslateEvent_FailedCopyWith(TranslateEvent_Failed value, $Res Function(TranslateEvent_Failed) _then) = _$TranslateEvent_FailedCopyWithImpl;
@useResult
$Res call({
 OtterError error
});




}
/// @nodoc
class _$TranslateEvent_FailedCopyWithImpl<$Res>
    implements $TranslateEvent_FailedCopyWith<$Res> {
  _$TranslateEvent_FailedCopyWithImpl(this._self, this._then);

  final TranslateEvent_Failed _self;
  final $Res Function(TranslateEvent_Failed) _then;

/// Create a copy of TranslateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(TranslateEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as OtterError,
  ));
}


}

/// @nodoc


class TranslateEvent_Snapshot extends TranslateEvent {
  const TranslateEvent_Snapshot({required this.text}): super._();
  

 final  String text;

/// Create a copy of TranslateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TranslateEvent_SnapshotCopyWith<TranslateEvent_Snapshot> get copyWith => _$TranslateEvent_SnapshotCopyWithImpl<TranslateEvent_Snapshot>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TranslateEvent_Snapshot&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,text);

@override
String toString() {
  return 'TranslateEvent.snapshot(text: $text)';
}


}

/// @nodoc
abstract mixin class $TranslateEvent_SnapshotCopyWith<$Res> implements $TranslateEventCopyWith<$Res> {
  factory $TranslateEvent_SnapshotCopyWith(TranslateEvent_Snapshot value, $Res Function(TranslateEvent_Snapshot) _then) = _$TranslateEvent_SnapshotCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$TranslateEvent_SnapshotCopyWithImpl<$Res>
    implements $TranslateEvent_SnapshotCopyWith<$Res> {
  _$TranslateEvent_SnapshotCopyWithImpl(this._self, this._then);

  final TranslateEvent_Snapshot _self;
  final $Res Function(TranslateEvent_Snapshot) _then;

/// Create a copy of TranslateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(TranslateEvent_Snapshot(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TranslateEvent_Paragraph extends TranslateEvent {
  const TranslateEvent_Paragraph({required this.event}): super._();
  

 final  TranslationEvent event;

/// Create a copy of TranslateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TranslateEvent_ParagraphCopyWith<TranslateEvent_Paragraph> get copyWith => _$TranslateEvent_ParagraphCopyWithImpl<TranslateEvent_Paragraph>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TranslateEvent_Paragraph&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode => Object.hash(runtimeType,event);

@override
String toString() {
  return 'TranslateEvent.paragraph(event: $event)';
}


}

/// @nodoc
abstract mixin class $TranslateEvent_ParagraphCopyWith<$Res> implements $TranslateEventCopyWith<$Res> {
  factory $TranslateEvent_ParagraphCopyWith(TranslateEvent_Paragraph value, $Res Function(TranslateEvent_Paragraph) _then) = _$TranslateEvent_ParagraphCopyWithImpl;
@useResult
$Res call({
 TranslationEvent event
});


$TranslationEventCopyWith<$Res> get event;

}
/// @nodoc
class _$TranslateEvent_ParagraphCopyWithImpl<$Res>
    implements $TranslateEvent_ParagraphCopyWith<$Res> {
  _$TranslateEvent_ParagraphCopyWithImpl(this._self, this._then);

  final TranslateEvent_Paragraph _self;
  final $Res Function(TranslateEvent_Paragraph) _then;

/// Create a copy of TranslateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? event = null,}) {
  return _then(TranslateEvent_Paragraph(
event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as TranslationEvent,
  ));
}

/// Create a copy of TranslateEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TranslationEventCopyWith<$Res> get event {
  
  return $TranslationEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class TranslateEvent_Completed extends TranslateEvent {
  const TranslateEvent_Completed({required this.report}): super._();
  

 final  TranslationReport report;

/// Create a copy of TranslateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TranslateEvent_CompletedCopyWith<TranslateEvent_Completed> get copyWith => _$TranslateEvent_CompletedCopyWithImpl<TranslateEvent_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TranslateEvent_Completed&&(identical(other.report, report) || other.report == report));
}


@override
int get hashCode => Object.hash(runtimeType,report);

@override
String toString() {
  return 'TranslateEvent.completed(report: $report)';
}


}

/// @nodoc
abstract mixin class $TranslateEvent_CompletedCopyWith<$Res> implements $TranslateEventCopyWith<$Res> {
  factory $TranslateEvent_CompletedCopyWith(TranslateEvent_Completed value, $Res Function(TranslateEvent_Completed) _then) = _$TranslateEvent_CompletedCopyWithImpl;
@useResult
$Res call({
 TranslationReport report
});




}
/// @nodoc
class _$TranslateEvent_CompletedCopyWithImpl<$Res>
    implements $TranslateEvent_CompletedCopyWith<$Res> {
  _$TranslateEvent_CompletedCopyWithImpl(this._self, this._then);

  final TranslateEvent_Completed _self;
  final $Res Function(TranslateEvent_Completed) _then;

/// Create a copy of TranslateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? report = null,}) {
  return _then(TranslateEvent_Completed(
report: null == report ? _self.report : report // ignore: cast_nullable_to_non_nullable
as TranslationReport,
  ));
}


}

// dart format on
