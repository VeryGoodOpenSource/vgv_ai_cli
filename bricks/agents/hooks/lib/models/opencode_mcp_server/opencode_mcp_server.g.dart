// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'opencode_mcp_server.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$OpenCodeMCPServerToJson(OpenCodeMCPServer instance) =>
    <String, dynamic>{
      'type': _$OpenCodeMCPServerTypeEnumMap[instance.type]!,
      'command': ?instance.command,
      'url': ?instance.url,
      'environment': ?instance.environment,
    };

const _$OpenCodeMCPServerTypeEnumMap = {
  OpenCodeMCPServerType.local: 'local',
  OpenCodeMCPServerType.remote: 'remote',
};
