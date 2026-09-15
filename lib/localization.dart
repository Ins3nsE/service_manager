import 'models/service.dart';

class AppLocalizations {
  const AppLocalizations(this.isEnglish);

  final bool isEnglish;

  String get languageName => isEnglish ? 'English' : 'Русский';
  String get appTitle =>
      isEnglish ? 'Windows Service Manager' : 'Менеджер служб Windows';
  String get settings => isEnglish ? 'Settings' : 'Настройки';
  String get darkTheme => isEnglish ? 'Dark theme' : 'Тёмная тема';
  String get launchAtStartup =>
      isEnglish ? 'Launch at Windows startup' : 'Запускать при старте Windows';
  String get close => isEnglish ? 'Close' : 'Закрыть';
  String get language => isEnglish ? 'Language' : 'Язык';
  String get refreshInterval => isEnglish
      ? 'Refresh interval (seconds)'
      : 'Интервал обновления (секунды)';
  String get showInTray => isEnglish ? 'Minimize to tray' : 'Свернуть в трей';
  String get chooseServices => isEnglish ? 'Choose services' : 'Выбрать службы';
  String get exit => isEnglish ? 'Exit application' : 'Выйти из приложения';
  String get startAll =>
      isEnglish ? 'Start all services' : 'Запустить все службы';
  String get stopAll =>
      isEnglish ? 'Stop all services' : 'Остановить все службы';
  String get emptyServices => isEnglish
      ? 'The service list is empty. Choose services from the list.'
      : 'Список служб пуст. Выберите службы из списка.';
  String get trayHint => isEnglish
      ? 'Closing the window hides the application in the tray — manage services from its context menu.'
      : 'Закрытие окна скрывает приложение в трей — управлять службами можно из его контекстного меню.';
  String get adminRequired => isEnglish
      ? 'The application is running without administrator privileges.\n'
            'Restart it as administrator to start and stop services.'
      : 'Приложение запущено без прав администратора.\n'
            'Для запуска и остановки служб перезапустите его от имени администратора.';
  String get restart => isEnglish ? 'Restart' : 'Перезапустить';
  String get adminDialogTitle => isEnglish
      ? 'Administrator privileges required'
      : 'Требуются права администратора';
  String get adminDialogText => isEnglish
      ? 'The application must run as administrator to start and stop services. Restart it now?'
      : 'Для запуска и остановки служб приложение должно работать от имени администратора. Перезапустить приложение сейчас?';
  String get cancel => isEnglish ? 'Cancel' : 'Отмена';
  String get serviceStarted => isEnglish ? 'started' : 'запущена';
  String get serviceStopped => isEnglish ? 'stopped' : 'остановлена';
  String get service => isEnglish ? 'Service' : 'Служба';
  String get serviceObject => isEnglish ? 'service' : 'службу';
  String get elevatedRelaunchSuccess => isEnglish
      ? 'A new copy with administrator privileges was started. The current window will close.'
      : 'Запущена новая копия с правами администратора. Текущее окно будет закрыто.';
  String get elevatedRelaunchFailure => isEnglish
      ? 'Could not restart the application with administrator privileges.'
      : 'Не удалось перезапустить приложение с правами администратора.';
  String get operationFailed => isEnglish ? 'Could not' : 'Не удалось';
  String get start => isEnglish ? 'Start' : 'Запустить';
  String get stop => isEnglish ? 'Stop' : 'Остановить';
  String get restartService => isEnglish ? 'Restart' : 'Перезапустить';
  String get removeService =>
      isEnglish ? 'Remove from list' : 'Удалить из списка';
  String get serviceSelection =>
      isEnglish ? 'Service selection' : 'Выбор служб';
  String get search => isEnglish ? 'Search' : 'Поиск';
  String get selectAll => isEnglish ? 'Select all' : 'Выбрать все';
  String get deselectAll => isEnglish ? 'Clear selection' : 'Снять выбор';
  String get notFound => isEnglish ? 'No services found' : 'Службы не найдены';
  String get apply => isEnglish ? 'Apply' : 'Применить';

  String status(ServiceStatus status) => switch (status) {
    ServiceStatus.running => isEnglish ? 'Running' : 'Работает',
    ServiceStatus.stopped => isEnglish ? 'Stopped' : 'Остановлена',
    ServiceStatus.startPending => isEnglish ? 'Starting...' : 'Запускается...',
    ServiceStatus.stopPending =>
      isEnglish ? 'Stopping...' : 'Останавливается...',
    ServiceStatus.unknown => isEnglish ? 'Unknown' : 'Неизвестно',
  };
}
