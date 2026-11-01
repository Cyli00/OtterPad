// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'remote.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RemoteConfig {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoteConfig);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RemoteConfig()';
}


}

/// @nodoc
class $RemoteConfigCopyWith<$Res>  {
$RemoteConfigCopyWith(RemoteConfig _, $Res Function(RemoteConfig) __);
}


/// Adds pattern-matching-related methods to [RemoteConfig].
extension RemoteConfigPatterns on RemoteConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RemoteConfig_Webdav value)?  webdav,TResult Function( RemoteConfig_S3 value)?  s3,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RemoteConfig_Webdav() when webdav != null:
return webdav(_that);case RemoteConfig_S3() when s3 != null:
return s3(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RemoteConfig_Webdav value)  webdav,required TResult Function( RemoteConfig_S3 value)  s3,}){
final _that = this;
switch (_that) {
case RemoteConfig_Webdav():
return webdav(_that);case RemoteConfig_S3():
return s3(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RemoteConfig_Webdav value)?  webdav,TResult? Function( RemoteConfig_S3 value)?  s3,}){
final _that = this;
switch (_that) {
case RemoteConfig_Webdav() when webdav != null:
return webdav(_that);case RemoteConfig_S3() when s3 != null:
return s3(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String serverUrl,  String username,  String remoteDir,  String fileName)?  webdav,TResult Function( String endpoint,  String region,  String bucket,  String objectKey,  bool pathStyle,  String accessKey)?  s3,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RemoteConfig_Webdav() when webdav != null:
return webdav(_that.serverUrl,_that.username,_that.remoteDir,_that.fileName);case RemoteConfig_S3() when s3 != null:
return s3(_that.endpoint,_that.region,_that.bucket,_that.objectKey,_that.pathStyle,_that.accessKey);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String serverUrl,  String username,  String remoteDir,  String fileName)  webdav,required TResult Function( String endpoint,  String region,  String bucket,  String objectKey,  bool pathStyle,  String accessKey)  s3,}) {final _that = this;
switch (_that) {
case RemoteConfig_Webdav():
return webdav(_that.serverUrl,_that.username,_that.remoteDir,_that.fileName);case RemoteConfig_S3():
return s3(_that.endpoint,_that.region,_that.bucket,_that.objectKey,_that.pathStyle,_that.accessKey);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String serverUrl,  String username,  String remoteDir,  String fileName)?  webdav,TResult? Function( String endpoint,  String region,  String bucket,  String objectKey,  bool pathStyle,  String accessKey)?  s3,}) {final _that = this;
switch (_that) {
case RemoteConfig_Webdav() when webdav != null:
return webdav(_that.serverUrl,_that.username,_that.remoteDir,_that.fileName);case RemoteConfig_S3() when s3 != null:
return s3(_that.endpoint,_that.region,_that.bucket,_that.objectKey,_that.pathStyle,_that.accessKey);case _:
  return null;

}
}

}

/// @nodoc


class RemoteConfig_Webdav extends RemoteConfig {
  const RemoteConfig_Webdav({required this.serverUrl, required this.username, required this.remoteDir, required this.fileName}): super._();
  

 final  String serverUrl;
 final  String username;
 final  String remoteDir;
 final  String fileName;

/// Create a copy of RemoteConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoteConfig_WebdavCopyWith<RemoteConfig_Webdav> get copyWith => _$RemoteConfig_WebdavCopyWithImpl<RemoteConfig_Webdav>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoteConfig_Webdav&&(identical(other.serverUrl, serverUrl) || other.serverUrl == serverUrl)&&(identical(other.username, username) || other.username == username)&&(identical(other.remoteDir, remoteDir) || other.remoteDir == remoteDir)&&(identical(other.fileName, fileName) || other.fileName == fileName));
}


@override
int get hashCode => Object.hash(runtimeType,serverUrl,username,remoteDir,fileName);

@override
String toString() {
  return 'RemoteConfig.webdav(serverUrl: $serverUrl, username: $username, remoteDir: $remoteDir, fileName: $fileName)';
}


}

/// @nodoc
abstract mixin class $RemoteConfig_WebdavCopyWith<$Res> implements $RemoteConfigCopyWith<$Res> {
  factory $RemoteConfig_WebdavCopyWith(RemoteConfig_Webdav value, $Res Function(RemoteConfig_Webdav) _then) = _$RemoteConfig_WebdavCopyWithImpl;
@useResult
$Res call({
 String serverUrl, String username, String remoteDir, String fileName
});




}
/// @nodoc
class _$RemoteConfig_WebdavCopyWithImpl<$Res>
    implements $RemoteConfig_WebdavCopyWith<$Res> {
  _$RemoteConfig_WebdavCopyWithImpl(this._self, this._then);

  final RemoteConfig_Webdav _self;
  final $Res Function(RemoteConfig_Webdav) _then;

/// Create a copy of RemoteConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? serverUrl = null,Object? username = null,Object? remoteDir = null,Object? fileName = null,}) {
  return _then(RemoteConfig_Webdav(
serverUrl: null == serverUrl ? _self.serverUrl : serverUrl // ignore: cast_nullable_to_non_nullable
as String,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,remoteDir: null == remoteDir ? _self.remoteDir : remoteDir // ignore: cast_nullable_to_non_nullable
as String,fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RemoteConfig_S3 extends RemoteConfig {
  const RemoteConfig_S3({required this.endpoint, required this.region, required this.bucket, required this.objectKey, required this.pathStyle, required this.accessKey}): super._();
  

 final  String endpoint;
 final  String region;
 final  String bucket;
 final  String objectKey;
 final  bool pathStyle;
 final  String accessKey;

/// Create a copy of RemoteConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoteConfig_S3CopyWith<RemoteConfig_S3> get copyWith => _$RemoteConfig_S3CopyWithImpl<RemoteConfig_S3>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoteConfig_S3&&(identical(other.endpoint, endpoint) || other.endpoint == endpoint)&&(identical(other.region, region) || other.region == region)&&(identical(other.bucket, bucket) || other.bucket == bucket)&&(identical(other.objectKey, objectKey) || other.objectKey == objectKey)&&(identical(other.pathStyle, pathStyle) || other.pathStyle == pathStyle)&&(identical(other.accessKey, accessKey) || other.accessKey == accessKey));
}


@override
int get hashCode => Object.hash(runtimeType,endpoint,region,bucket,objectKey,pathStyle,accessKey);

@override
String toString() {
  return 'RemoteConfig.s3(endpoint: $endpoint, region: $region, bucket: $bucket, objectKey: $objectKey, pathStyle: $pathStyle, accessKey: $accessKey)';
}


}

/// @nodoc
abstract mixin class $RemoteConfig_S3CopyWith<$Res> implements $RemoteConfigCopyWith<$Res> {
  factory $RemoteConfig_S3CopyWith(RemoteConfig_S3 value, $Res Function(RemoteConfig_S3) _then) = _$RemoteConfig_S3CopyWithImpl;
@useResult
$Res call({
 String endpoint, String region, String bucket, String objectKey, bool pathStyle, String accessKey
});




}
/// @nodoc
class _$RemoteConfig_S3CopyWithImpl<$Res>
    implements $RemoteConfig_S3CopyWith<$Res> {
  _$RemoteConfig_S3CopyWithImpl(this._self, this._then);

  final RemoteConfig_S3 _self;
  final $Res Function(RemoteConfig_S3) _then;

/// Create a copy of RemoteConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? endpoint = null,Object? region = null,Object? bucket = null,Object? objectKey = null,Object? pathStyle = null,Object? accessKey = null,}) {
  return _then(RemoteConfig_S3(
endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as String,region: null == region ? _self.region : region // ignore: cast_nullable_to_non_nullable
as String,bucket: null == bucket ? _self.bucket : bucket // ignore: cast_nullable_to_non_nullable
as String,objectKey: null == objectKey ? _self.objectKey : objectKey // ignore: cast_nullable_to_non_nullable
as String,pathStyle: null == pathStyle ? _self.pathStyle : pathStyle // ignore: cast_nullable_to_non_nullable
as bool,accessKey: null == accessKey ? _self.accessKey : accessKey // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
