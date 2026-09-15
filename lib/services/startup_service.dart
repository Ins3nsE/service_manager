import 'dart:io';

const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
const _runValueName = 'ServiceManager';

Future<bool> isLaunchAtStartupEnabled() async {
  try {
    final result = await Process.run('reg.exe', [
      'QUERY',
      _runKey,
      '/v',
      _runValueName,
    ]);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Future<String?> setLaunchAtStartup(
  bool enabled, {
  bool isEnglish = false,
}) async {
  try {
    if (enabled) {
      final executable = Platform.resolvedExecutable;
      final result = await Process.run('reg.exe', [
        'ADD',
        _runKey,
        '/v',
        _runValueName,
        '/t',
        'REG_SZ',
        '/d',
        '"$executable"',
        '/f',
      ]);
      if (result.exitCode == 0) return null;
      return _describeRegistryError(result, isEnglish);
    }

    final result = await Process.run('reg.exe', [
      'DELETE',
      _runKey,
      '/v',
      _runValueName,
      '/f',
    ]);
    if (result.exitCode == 0 || result.exitCode == 1) return null;
    return _describeRegistryError(result, isEnglish);
  } on ProcessException catch (error) {
    return isEnglish
        ? 'Could not change startup setting: ${error.message}'
        : 'Не удалось изменить автозапуск: ${error.message}';
  }
}

String _describeRegistryError(ProcessResult result, bool isEnglish) {
  final detail =
      (result.stderr.toString().isNotEmpty ? result.stderr : result.stdout)
          .toString()
          .trim();
  return isEnglish
      ? 'Could not change startup setting '
            '(code ${result.exitCode}).${detail.isEmpty ? '' : '\n$detail'}'
      : 'Не удалось изменить автозапуск '
            '(код ${result.exitCode}).${detail.isEmpty ? '' : '\n$detail'}';
}
