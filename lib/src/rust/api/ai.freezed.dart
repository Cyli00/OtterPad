// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ai.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ConversationEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ConversationEvent()';
}


}

/// @nodoc
class $ConversationEventCopyWith<$Res>  {
$ConversationEventCopyWith(ConversationEvent _, $Res Function(ConversationEvent) __);
}


/// Adds pattern-matching-related methods to [ConversationEvent].
extension ConversationEventPatterns on ConversationEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ConversationEvent_Failed value)?  failed,TResult Function( ConversationEvent_Delta value)?  delta,TResult Function( ConversationEvent_Saved value)?  saved,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ConversationEvent_Failed() when failed != null:
return failed(_that);case ConversationEvent_Delta() when delta != null:
return delta(_that);case ConversationEvent_Saved() when saved != null:
return saved(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ConversationEvent_Failed value)  failed,required TResult Function( ConversationEvent_Delta value)  delta,required TResult Function( ConversationEvent_Saved value)  saved,}){
final _that = this;
switch (_that) {
case ConversationEvent_Failed():
return failed(_that);case ConversationEvent_Delta():
return delta(_that);case ConversationEvent_Saved():
return saved(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ConversationEvent_Failed value)?  failed,TResult? Function( ConversationEvent_Delta value)?  delta,TResult? Function( ConversationEvent_Saved value)?  saved,}){
final _that = this;
switch (_that) {
case ConversationEvent_Failed() when failed != null:
return failed(_that);case ConversationEvent_Delta() when delta != null:
return delta(_that);case ConversationEvent_Saved() when saved != null:
return saved(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OtterError error)?  failed,TResult Function( ChatEvent event)?  delta,TResult Function( Conversation conversation)?  saved,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ConversationEvent_Failed() when failed != null:
return failed(_that.error);case ConversationEvent_Delta() when delta != null:
return delta(_that.event);case ConversationEvent_Saved() when saved != null:
return saved(_that.conversation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OtterError error)  failed,required TResult Function( ChatEvent event)  delta,required TResult Function( Conversation conversation)  saved,}) {final _that = this;
switch (_that) {
case ConversationEvent_Failed():
return failed(_that.error);case ConversationEvent_Delta():
return delta(_that.event);case ConversationEvent_Saved():
return saved(_that.conversation);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OtterError error)?  failed,TResult? Function( ChatEvent event)?  delta,TResult? Function( Conversation conversation)?  saved,}) {final _that = this;
switch (_that) {
case ConversationEvent_Failed() when failed != null:
return failed(_that.error);case ConversationEvent_Delta() when delta != null:
return delta(_that.event);case ConversationEvent_Saved() when saved != null:
return saved(_that.conversation);case _:
  return null;

}
}

}

/// @nodoc


class ConversationEvent_Failed extends ConversationEvent {
  const ConversationEvent_Failed({required this.error}): super._();
  

 final  OtterError error;

/// Create a copy of ConversationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationEvent_FailedCopyWith<ConversationEvent_Failed> get copyWith => _$ConversationEvent_FailedCopyWithImpl<ConversationEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'ConversationEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $ConversationEvent_FailedCopyWith<$Res> implements $ConversationEventCopyWith<$Res> {
  factory $ConversationEvent_FailedCopyWith(ConversationEvent_Failed value, $Res Function(ConversationEvent_Failed) _then) = _$ConversationEvent_FailedCopyWithImpl;
@useResult
$Res call({
 OtterError error
});




}
/// @nodoc
class _$ConversationEvent_FailedCopyWithImpl<$Res>
    implements $ConversationEvent_FailedCopyWith<$Res> {
  _$ConversationEvent_FailedCopyWithImpl(this._self, this._then);

  final ConversationEvent_Failed _self;
  final $Res Function(ConversationEvent_Failed) _then;

/// Create a copy of ConversationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(ConversationEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as OtterError,
  ));
}


}

/// @nodoc


class ConversationEvent_Delta extends ConversationEvent {
  const ConversationEvent_Delta({required this.event}): super._();
  

 final  ChatEvent event;

/// Create a copy of ConversationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationEvent_DeltaCopyWith<ConversationEvent_Delta> get copyWith => _$ConversationEvent_DeltaCopyWithImpl<ConversationEvent_Delta>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationEvent_Delta&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode => Object.hash(runtimeType,event);

@override
String toString() {
  return 'ConversationEvent.delta(event: $event)';
}


}

/// @nodoc
abstract mixin class $ConversationEvent_DeltaCopyWith<$Res> implements $ConversationEventCopyWith<$Res> {
  factory $ConversationEvent_DeltaCopyWith(ConversationEvent_Delta value, $Res Function(ConversationEvent_Delta) _then) = _$ConversationEvent_DeltaCopyWithImpl;
@useResult
$Res call({
 ChatEvent event
});


$ChatEventCopyWith<$Res> get event;

}
/// @nodoc
class _$ConversationEvent_DeltaCopyWithImpl<$Res>
    implements $ConversationEvent_DeltaCopyWith<$Res> {
  _$ConversationEvent_DeltaCopyWithImpl(this._self, this._then);

  final ConversationEvent_Delta _self;
  final $Res Function(ConversationEvent_Delta) _then;

/// Create a copy of ConversationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? event = null,}) {
  return _then(ConversationEvent_Delta(
event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as ChatEvent,
  ));
}

/// Create a copy of ConversationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ChatEventCopyWith<$Res> get event {
  
  return $ChatEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class ConversationEvent_Saved extends ConversationEvent {
  const ConversationEvent_Saved({required this.conversation}): super._();
  

 final  Conversation conversation;

/// Create a copy of ConversationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationEvent_SavedCopyWith<ConversationEvent_Saved> get copyWith => _$ConversationEvent_SavedCopyWithImpl<ConversationEvent_Saved>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationEvent_Saved&&(identical(other.conversation, conversation) || other.conversation == conversation));
}


@override
int get hashCode => Object.hash(runtimeType,conversation);

@override
String toString() {
  return 'ConversationEvent.saved(conversation: $conversation)';
}


}

/// @nodoc
abstract mixin class $ConversationEvent_SavedCopyWith<$Res> implements $ConversationEventCopyWith<$Res> {
  factory $ConversationEvent_SavedCopyWith(ConversationEvent_Saved value, $Res Function(ConversationEvent_Saved) _then) = _$ConversationEvent_SavedCopyWithImpl;
@useResult
$Res call({
 Conversation conversation
});




}
/// @nodoc
class _$ConversationEvent_SavedCopyWithImpl<$Res>
    implements $ConversationEvent_SavedCopyWith<$Res> {
  _$ConversationEvent_SavedCopyWithImpl(this._self, this._then);

  final ConversationEvent_Saved _self;
  final $Res Function(ConversationEvent_Saved) _then;

/// Create a copy of ConversationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? conversation = null,}) {
  return _then(ConversationEvent_Saved(
conversation: null == conversation ? _self.conversation : conversation // ignore: cast_nullable_to_non_nullable
as Conversation,
  ));
}


}

/// @nodoc
mixin _$GenerationEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GenerationEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GenerationEvent()';
}


}

/// @nodoc
class $GenerationEventCopyWith<$Res>  {
$GenerationEventCopyWith(GenerationEvent _, $Res Function(GenerationEvent) __);
}


/// Adds pattern-matching-related methods to [GenerationEvent].
extension GenerationEventPatterns on GenerationEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( GenerationEvent_Failed value)?  failed,TResult Function( GenerationEvent_Delta value)?  delta,TResult Function( GenerationEvent_Completed value)?  completed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case GenerationEvent_Failed() when failed != null:
return failed(_that);case GenerationEvent_Delta() when delta != null:
return delta(_that);case GenerationEvent_Completed() when completed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( GenerationEvent_Failed value)  failed,required TResult Function( GenerationEvent_Delta value)  delta,required TResult Function( GenerationEvent_Completed value)  completed,}){
final _that = this;
switch (_that) {
case GenerationEvent_Failed():
return failed(_that);case GenerationEvent_Delta():
return delta(_that);case GenerationEvent_Completed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( GenerationEvent_Failed value)?  failed,TResult? Function( GenerationEvent_Delta value)?  delta,TResult? Function( GenerationEvent_Completed value)?  completed,}){
final _that = this;
switch (_that) {
case GenerationEvent_Failed() when failed != null:
return failed(_that);case GenerationEvent_Delta() when delta != null:
return delta(_that);case GenerationEvent_Completed() when completed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OtterError error)?  failed,TResult Function( ChatEvent event)?  delta,TResult Function( ChatResponse response)?  completed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case GenerationEvent_Failed() when failed != null:
return failed(_that.error);case GenerationEvent_Delta() when delta != null:
return delta(_that.event);case GenerationEvent_Completed() when completed != null:
return completed(_that.response);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OtterError error)  failed,required TResult Function( ChatEvent event)  delta,required TResult Function( ChatResponse response)  completed,}) {final _that = this;
switch (_that) {
case GenerationEvent_Failed():
return failed(_that.error);case GenerationEvent_Delta():
return delta(_that.event);case GenerationEvent_Completed():
return completed(_that.response);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OtterError error)?  failed,TResult? Function( ChatEvent event)?  delta,TResult? Function( ChatResponse response)?  completed,}) {final _that = this;
switch (_that) {
case GenerationEvent_Failed() when failed != null:
return failed(_that.error);case GenerationEvent_Delta() when delta != null:
return delta(_that.event);case GenerationEvent_Completed() when completed != null:
return completed(_that.response);case _:
  return null;

}
}

}

/// @nodoc


class GenerationEvent_Failed extends GenerationEvent {
  const GenerationEvent_Failed({required this.error}): super._();
  

 final  OtterError error;

/// Create a copy of GenerationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GenerationEvent_FailedCopyWith<GenerationEvent_Failed> get copyWith => _$GenerationEvent_FailedCopyWithImpl<GenerationEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GenerationEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'GenerationEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $GenerationEvent_FailedCopyWith<$Res> implements $GenerationEventCopyWith<$Res> {
  factory $GenerationEvent_FailedCopyWith(GenerationEvent_Failed value, $Res Function(GenerationEvent_Failed) _then) = _$GenerationEvent_FailedCopyWithImpl;
@useResult
$Res call({
 OtterError error
});




}
/// @nodoc
class _$GenerationEvent_FailedCopyWithImpl<$Res>
    implements $GenerationEvent_FailedCopyWith<$Res> {
  _$GenerationEvent_FailedCopyWithImpl(this._self, this._then);

  final GenerationEvent_Failed _self;
  final $Res Function(GenerationEvent_Failed) _then;

/// Create a copy of GenerationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(GenerationEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as OtterError,
  ));
}


}

/// @nodoc


class GenerationEvent_Delta extends GenerationEvent {
  const GenerationEvent_Delta({required this.event}): super._();
  

 final  ChatEvent event;

/// Create a copy of GenerationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GenerationEvent_DeltaCopyWith<GenerationEvent_Delta> get copyWith => _$GenerationEvent_DeltaCopyWithImpl<GenerationEvent_Delta>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GenerationEvent_Delta&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode => Object.hash(runtimeType,event);

@override
String toString() {
  return 'GenerationEvent.delta(event: $event)';
}


}

/// @nodoc
abstract mixin class $GenerationEvent_DeltaCopyWith<$Res> implements $GenerationEventCopyWith<$Res> {
  factory $GenerationEvent_DeltaCopyWith(GenerationEvent_Delta value, $Res Function(GenerationEvent_Delta) _then) = _$GenerationEvent_DeltaCopyWithImpl;
@useResult
$Res call({
 ChatEvent event
});


$ChatEventCopyWith<$Res> get event;

}
/// @nodoc
class _$GenerationEvent_DeltaCopyWithImpl<$Res>
    implements $GenerationEvent_DeltaCopyWith<$Res> {
  _$GenerationEvent_DeltaCopyWithImpl(this._self, this._then);

  final GenerationEvent_Delta _self;
  final $Res Function(GenerationEvent_Delta) _then;

/// Create a copy of GenerationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? event = null,}) {
  return _then(GenerationEvent_Delta(
event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as ChatEvent,
  ));
}

/// Create a copy of GenerationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ChatEventCopyWith<$Res> get event {
  
  return $ChatEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class GenerationEvent_Completed extends GenerationEvent {
  const GenerationEvent_Completed({required this.response}): super._();
  

 final  ChatResponse response;

/// Create a copy of GenerationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GenerationEvent_CompletedCopyWith<GenerationEvent_Completed> get copyWith => _$GenerationEvent_CompletedCopyWithImpl<GenerationEvent_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GenerationEvent_Completed&&(identical(other.response, response) || other.response == response));
}


@override
int get hashCode => Object.hash(runtimeType,response);

@override
String toString() {
  return 'GenerationEvent.completed(response: $response)';
}


}

/// @nodoc
abstract mixin class $GenerationEvent_CompletedCopyWith<$Res> implements $GenerationEventCopyWith<$Res> {
  factory $GenerationEvent_CompletedCopyWith(GenerationEvent_Completed value, $Res Function(GenerationEvent_Completed) _then) = _$GenerationEvent_CompletedCopyWithImpl;
@useResult
$Res call({
 ChatResponse response
});




}
/// @nodoc
class _$GenerationEvent_CompletedCopyWithImpl<$Res>
    implements $GenerationEvent_CompletedCopyWith<$Res> {
  _$GenerationEvent_CompletedCopyWithImpl(this._self, this._then);

  final GenerationEvent_Completed _self;
  final $Res Function(GenerationEvent_Completed) _then;

/// Create a copy of GenerationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? response = null,}) {
  return _then(GenerationEvent_Completed(
response: null == response ? _self.response : response // ignore: cast_nullable_to_non_nullable
as ChatResponse,
  ));
}


}

// dart format on
