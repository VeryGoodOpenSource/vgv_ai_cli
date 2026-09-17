// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gemini_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$GeminiContextToJson(GeminiContext instance) =>
    <String, dynamic>{'fileName': instance.fileName};

Map<String, dynamic> _$GeminiSettingsToJson(GeminiSettings instance) =>
    <String, dynamic>{
      'mcpServers': instance.mcpServers.map((k, e) => MapEntry(k, e.toJson())),
      'context': instance.context.toJson(),
    };
