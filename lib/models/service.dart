class ServiceDef {
  const ServiceDef(this.name, this.fallbackDisplayName);

  final String name;
  final String fallbackDisplayName;
}

enum ServiceStatus {
  stopped('Остановлена'),
  running('Работает'),
  startPending('Запускается...'),
  stopPending('Останавливается...'),
  unknown('Неизвестно');

  const ServiceStatus(this.label);

  final String label;
}

class ServiceEntry {
  ServiceEntry(this.def)
    : displayName = def.fallbackDisplayName,
      status = ServiceStatus.unknown;

  final ServiceDef def;
  String displayName;
  ServiceStatus status;
  bool busy = false;
}
