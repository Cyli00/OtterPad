// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChatEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ChatEvent()';
}


}

/// @nodoc
class $ChatEventCopyWith<$Res>  {
$ChatEventCopyWith(ChatEvent _, $Res Function(ChatEvent) __);
}


/// Adds pattern-matching-related methods to [ChatEvent].
extension ChatEventPatterns on ChatEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ChatEvent_TextDelta value)?  textDelta,TResult Function( ChatEvent_ReasoningDelta value)?  reasoningDelta,TResult Function( ChatEvent_Tool value)?  tool,TResult Function( ChatEvent_Citation value)?  citation,TResult Function( ChatEvent_Usage value)?  usage,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ChatEvent_TextDelta() when textDelta != null:
return textDelta(_that);case ChatEvent_ReasoningDelta() when reasoningDelta != null:
return reasoningDelta(_that);case ChatEvent_Tool() when tool != null:
return tool(_that);case ChatEvent_Citation() when citation != null:
return citation(_that);case ChatEvent_Usage() when usage != null:
return usage(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ChatEvent_TextDelta value)  textDelta,required TResult Function( ChatEvent_ReasoningDelta value)  reasoningDelta,required TResult Function( ChatEvent_Tool value)  tool,required TResult Function( ChatEvent_Citation value)  citation,required TResult Function( ChatEvent_Usage value)  usage,}){
final _that = this;
switch (_that) {
case ChatEvent_TextDelta():
return textDelta(_that);case ChatEvent_ReasoningDelta():
return reasoningDelta(_that);case ChatEvent_Tool():
return tool(_that);case ChatEvent_Citation():
return citation(_that);case ChatEvent_Usage():
return usage(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ChatEvent_TextDelta value)?  textDelta,TResult? Function( ChatEvent_ReasoningDelta value)?  reasoningDelta,TResult? Function( ChatEvent_Tool value)?  tool,TResult? Function( ChatEvent_Citation value)?  citation,TResult? Function( ChatEvent_Usage value)?  usage,}){
final _that = this;
switch (_that) {
case ChatEvent_TextDelta() when textDelta != null:
return textDelta(_that);case ChatEvent_ReasoningDelta() when reasoningDelta != null:
return reasoningDelta(_that);case ChatEvent_Tool() when tool != null:
return tool(_that);case ChatEvent_Citation() when citation != null:
return citation(_that);case ChatEvent_Usage() when usage != null:
return usage(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String text)?  textDelta,TResult Function( String text)?  reasoningDelta,TResult Function( String name)?  tool,TResult Function( Citation source)?  citation,TResult Function( Usage usage)?  usage,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ChatEvent_TextDelta() when textDelta != null:
return textDelta(_that.text);case ChatEvent_ReasoningDelta() when reasoningDelta != null:
return reasoningDelta(_that.text);case ChatEvent_Tool() when tool != null:
return tool(_that.name);case ChatEvent_Citation() when citation != null:
return citation(_that.source);case ChatEvent_Usage() when usage != null:
return usage(_that.usage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String text)  textDelta,required TResult Function( String text)  reasoningDelta,required TResult Function( String name)  tool,required TResult Function( Citation source)  citation,required TResult Function( Usage usage)  usage,}) {final _that = this;
switch (_that) {
case ChatEvent_TextDelta():
return textDelta(_that.text);case ChatEvent_ReasoningDelta():
return reasoningDelta(_that.text);case ChatEvent_Tool():
return tool(_that.name);case ChatEvent_Citation():
return citation(_that.source);case ChatEvent_Usage():
return usage(_that.usage);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String text)?  textDelta,TResult? Function( String text)?  reasoningDelta,TResult? Function( String name)?  tool,TResult? Function( Citation source)?  citation,TResult? Function( Usage usage)?  usage,}) {final _that = this;
switch (_that) {
case ChatEvent_TextDelta() when textDelta != null:
return textDelta(_that.text);case ChatEvent_ReasoningDelta() when reasoningDelta != null:
return reasoningDelta(_that.text);case ChatEvent_Tool() when tool != null:
return tool(_that.name);case ChatEvent_Citation() when citation != null:
return citation(_that.source);case ChatEvent_Usage() when usage != null:
return usage(_that.usage);case _:
  return null;

}
}

}

/// @nodoc


class ChatEvent_TextDelta extends ChatEvent {
  const ChatEvent_TextDelta({required this.text}): super._();
  

 final  String text;

/// Create a copy of ChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatEvent_TextDeltaCopyWith<ChatEvent_TextDelta> get copyWith => _$ChatEvent_TextDeltaCopyWithImpl<ChatEvent_TextDelta>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatEvent_TextDelta&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,text);

@override
String toString() {
  return 'ChatEvent.textDelta(text: $text)';
}


}

/// @nodoc
abstract mixin class $ChatEvent_TextDeltaCopyWith<$Res> implements $ChatEventCopyWith<$Res> {
  factory $ChatEvent_TextDeltaCopyWith(ChatEvent_TextDelta value, $Res Function(ChatEvent_TextDelta) _then) = _$ChatEvent_TextDeltaCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$ChatEvent_TextDeltaCopyWithImpl<$Res>
    implements $ChatEvent_TextDeltaCopyWith<$Res> {
  _$ChatEvent_TextDeltaCopyWithImpl(this._self, this._then);

  final ChatEvent_TextDelta _self;
  final $Res Function(ChatEvent_TextDelta) _then;

/// Create a copy of ChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(ChatEvent_TextDelta(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ChatEvent_ReasoningDelta extends ChatEvent {
  const ChatEvent_ReasoningDelta({required this.text}): super._();
  

 final  String text;

/// Create a copy of ChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatEvent_ReasoningDeltaCopyWith<ChatEvent_ReasoningDelta> get copyWith => _$ChatEvent_ReasoningDeltaCopyWithImpl<ChatEvent_ReasoningDelta>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatEvent_ReasoningDelta&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,text);

@override
String toString() {
  return 'ChatEvent.reasoningDelta(text: $text)';
}


}

/// @nodoc
abstract mixin class $ChatEvent_ReasoningDeltaCopyWith<$Res> implements $ChatEventCopyWith<$Res> {
  factory $ChatEvent_ReasoningDeltaCopyWith(ChatEvent_ReasoningDelta value, $Res Function(ChatEvent_ReasoningDelta) _then) = _$ChatEvent_ReasoningDeltaCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$ChatEvent_ReasoningDeltaCopyWithImpl<$Res>
    implements $ChatEvent_ReasoningDeltaCopyWith<$Res> {
  _$ChatEvent_ReasoningDeltaCopyWithImpl(this._self, this._then);

  final ChatEvent_ReasoningDelta _self;
  final $Res Function(ChatEvent_ReasoningDelta) _then;

/// Create a copy of ChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(ChatEvent_ReasoningDelta(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ChatEvent_Tool extends ChatEvent {
  const ChatEvent_Tool({required this.name}): super._();
  

 final  String name;

/// Create a copy of ChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatEvent_ToolCopyWith<ChatEvent_Tool> get copyWith => _$ChatEvent_ToolCopyWithImpl<ChatEvent_Tool>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatEvent_Tool&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode => Object.hash(runtimeType,name);

@override
String toString() {
  return 'ChatEvent.tool(name: $name)';
}


}

/// @nodoc
abstract mixin class $ChatEvent_ToolCopyWith<$Res> implements $ChatEventCopyWith<$Res> {
  factory $ChatEvent_ToolCopyWith(ChatEvent_Tool value, $Res Function(ChatEvent_Tool) _then) = _$ChatEvent_ToolCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$ChatEvent_ToolCopyWithImpl<$Res>
    implements $ChatEvent_ToolCopyWith<$Res> {
  _$ChatEvent_ToolCopyWithImpl(this._self, this._then);

  final ChatEvent_Tool _self;
  final $Res Function(ChatEvent_Tool) _then;

/// Create a copy of ChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(ChatEvent_Tool(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ChatEvent_Citation extends ChatEvent {
  const ChatEvent_Citation({required this.source}): super._();
  

 final  Citation source;

/// Create a copy of ChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatEvent_CitationCopyWith<ChatEvent_Citation> get copyWith => _$ChatEvent_CitationCopyWithImpl<ChatEvent_Citation>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatEvent_Citation&&(identical(other.source, source) || other.source == source));
}


@override
int get hashCode => Object.hash(runtimeType,source);

@override
String toString() {
  return 'ChatEvent.citation(source: $source)';
}


}

/// @nodoc
abstract mixin class $ChatEvent_CitationCopyWith<$Res> implements $ChatEventCopyWith<$Res> {
  factory $ChatEvent_CitationCopyWith(ChatEvent_Citation value, $Res Function(ChatEvent_Citation) _then) = _$ChatEvent_CitationCopyWithImpl;
@useResult
$Res call({
 Citation source
});




}
/// @nodoc
class _$ChatEvent_CitationCopyWithImpl<$Res>
    implements $ChatEvent_CitationCopyWith<$Res> {
  _$ChatEvent_CitationCopyWithImpl(this._self, this._then);

  final ChatEvent_Citation _self;
  final $Res Function(ChatEvent_Citation) _then;

/// Create a copy of ChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? source = null,}) {
  return _then(ChatEvent_Citation(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as Citation,
  ));
}


}

/// @nodoc


class ChatEvent_Usage extends ChatEvent {
  const ChatEvent_Usage({required this.usage}): super._();
  

 final  Usage usage;

/// Create a copy of ChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatEvent_UsageCopyWith<ChatEvent_Usage> get copyWith => _$ChatEvent_UsageCopyWithImpl<ChatEvent_Usage>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatEvent_Usage&&(identical(other.usage, usage) || other.usage == usage));
}


@override
int get hashCode => Object.hash(runtimeType,usage);

@override
String toString() {
  return 'ChatEvent.usage(usage: $usage)';
}


}

/// @nodoc
abstract mixin class $ChatEvent_UsageCopyWith<$Res> implements $ChatEventCopyWith<$Res> {
  factory $ChatEvent_UsageCopyWith(ChatEvent_Usage value, $Res Function(ChatEvent_Usage) _then) = _$ChatEvent_UsageCopyWithImpl;
@useResult
$Res call({
 Usage usage
});




}
/// @nodoc
class _$ChatEvent_UsageCopyWithImpl<$Res>
    implements $ChatEvent_UsageCopyWith<$Res> {
  _$ChatEvent_UsageCopyWithImpl(this._self, this._then);

  final ChatEvent_Usage _self;
  final $Res Function(ChatEvent_Usage) _then;

/// Create a copy of ChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? usage = null,}) {
  return _then(ChatEvent_Usage(
usage: null == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as Usage,
  ));
}


}

// dart format on
