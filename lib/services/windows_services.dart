import 'dart:io';

import 'package:flutter/services.dart';

import '../models/service.dart';

const _channel = MethodChannel('service_manager/windows_services');

Future<List<ServiceDef>> listWindowsServices() async {
  final result = await _channel.invokeMethod<List<dynamic>>('listServices');
  final services = (result ?? const [])
      .whereType<Map>()
      .map(
        (record) => ServiceDef(
          record['name']?.toString() ?? '',
          record['displayName']?.toString() ?? record['name']?.toString() ?? '',
        ),
      )
      .where((service) => service.name.isNotEmpty)
      .toList();
  services.sort(
    (a, b) => a.fallbackDisplayName.toLowerCase().compareTo(
      b.fallbackDisplayName.toLowerCase(),
    ),
  );
  return services;
}

ServiceStatus _statusFromValue(Object? value) {
  return switch (value) {
    'running' => ServiceStatus.running,
    'stopped' => ServiceStatus.stopped,
    'startPending' => ServiceStatus.startPending,
    'stopPending' => ServiceStatus.stopPending,
    _ => ServiceStatus.unknown,
  };
}

ServiceStatus parseServiceStatus(String output) {
  final code =
      RegExp(r'(?:STATE|Состояние)\s*:\s*(\d+)').firstMatch(output)?.group(1) ??
      RegExp(
        r'^\s*[^:\r\n]+:\s*([1-4])\s+',
        multiLine: true,
      ).firstMatch(output)?.group(1);
  return switch (code) {
    '1' => ServiceStatus.stopped,
    '2' => ServiceStatus.startPending,
    '3' => ServiceStatus.stopPending,
    '4' => ServiceStatus.running,
    _ => ServiceStatus.unknown,
  };
}

Future<ServiceStatus> queryServiceStatus(String serviceName) async {
  try {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'queryStatus',
      {'name': serviceName},
    );
    return _statusFromValue(result?['statusName']);
  } on PlatformException {
    return ServiceStatus.unknown;
  }
}

Future<String> queryDisplayName(String serviceName, String fallback) async {
  try {
    final result = await _channel.invokeMethod<String>('queryDisplayName', {
      'name': serviceName,
    });
    return result?.trim().isNotEmpty == true ? result!.trim() : fallback;
  } on PlatformException {
    return fallback;
  }
}

Future<String?> startService(
  String serviceName, {
  bool isEnglish = false,
}) async {
  try {
    await _channel.invokeMethod<void>('startService', {'name': serviceName});
    return null;
  } on PlatformException catch (error) {
    return _describePlatformError(
      error,
      isEnglish ? 'starting' : 'запуске',
      isEnglish,
    );
  }
}

Future<String?> stopService(
  String serviceName, {
  bool isEnglish = false,
}) async {
  try {
    await _channel.invokeMethod<void>('stopService', {'name': serviceName});
    return null;
  } on PlatformException catch (error) {
    return _describePlatformError(
      error,
      isEnglish ? 'stopping' : 'остановке',
      isEnglish,
    );
  }
}

String _describePlatformError(
  PlatformException error,
  String action,
  bool isEnglish,
) {
  final message = error.message?.trim();
  if (message != null && message.isNotEmpty) return message;
  return isEnglish
      ? 'Could not complete operation "$action"'
            '${error.code.isEmpty ? '' : ' (code ${error.code})'}.'
      : 'Не удалось выполнить операцию «$action»'
            '${error.code.isEmpty ? '' : ' (код ${error.code})'}.';
}

Future<bool> isAdministrator() async {
  try {
    return await _channel.invokeMethod<bool>('isAdministrator') ?? false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}

Future<bool> relaunchElevated() async {
  final exe = Platform.resolvedExecutable;
  final script = 'Start-Process -Verb RunAs -FilePath "$exe"';
  try {
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-Command',
      script,
    ]);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}
