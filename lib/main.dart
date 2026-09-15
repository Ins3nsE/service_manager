import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'models/service.dart';
import 'localization.dart';
import 'services/startup_service.dart';
import 'services/windows_services.dart';
import 'widgets/service_widgets.dart';

export 'models/service.dart';
export 'services/windows_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Управление окном должно быть инициализировано до запуска приложения.
  await windowManager.ensureInitialized();
  // Закрытие окна не завершает приложение, а скрывает его в системный трей.
  WindowOptions windowOptions = const WindowOptions(
    size: Size(960, 600), // Начальный размер окна
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    // Устанавливаем минимальный размер окна
    await windowManager.setMinimumSize(const Size(960, 600));
    // Опционально: максимальный размер
    // await windowManager.setMaximumSize(const Size(1200, 900));

    await windowManager.show();
    await windowManager.focus();
  });
  await windowManager.setPreventClose(true);
  runApp(const ServiceManagerApp());
}

// ============================================================================
// Приложение
// ============================================================================

class ServiceManagerApp extends StatefulWidget {
  const ServiceManagerApp({super.key});

  @override
  State<ServiceManagerApp> createState() => _ServiceManagerAppState();
}

class _ServiceManagerAppState extends State<ServiceManagerApp> {
  static const _darkThemePreference = 'dark_theme';
  static const _languagePreference = 'language';

  ThemeMode _themeMode = ThemeMode.light;
  bool _isEnglish = false;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _themeMode = preferences.getBool(_darkThemePreference) == true
          ? ThemeMode.dark
          : ThemeMode.light;
      _isEnglish = preferences.getString(_languagePreference) == 'en';
    });
  }

  Future<void> _toggleTheme() async {
    final isDark = _themeMode != ThemeMode.dark;
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_darkThemePreference, isDark);
  }

  Future<void> _setLanguage(bool isEnglish) async {
    setState(() => _isEnglish = isEnglish);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_languagePreference, isEnglish ? 'en' : 'ru');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations(_isEnglish);
    return MaterialApp(
      title: l10n.appTitle,
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomePage(
        isDarkTheme: _themeMode == ThemeMode.dark,
        onToggleTheme: _toggleTheme,
        isEnglish: _isEnglish,
        onSetLanguage: _setLanguage,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.isDarkTheme,
    required this.onToggleTheme,
    required this.isEnglish,
    required this.onSetLanguage,
  });

  final bool isDarkTheme;
  final VoidCallback onToggleTheme;
  final bool isEnglish;
  final ValueChanged<bool> onSetLanguage;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TrayListener, WindowListener {
  static const _selectedServicesPreference = 'selected_services';
  static const _refreshIntervalPreference = 'refresh_interval_seconds';

  List<ServiceDef> _availableServices = const [];
  List<ServiceEntry> _entries = [];

  bool _isAdmin = false;
  bool _adminChecked = false;
  bool _servicesLoaded = false;
  bool _launchAtStartup = false;
  bool _startupUpdating = false;
  bool _refreshing = false;
  int _refreshIntervalSeconds = 5;
  Timer? _timer;
  AppLocalizations get l10n => AppLocalizations(widget.isEnglish);

  /// Инициализирована ли иконка в трее (для безопасного вызова setContextMenu).
  bool _trayReady = false;
  String? _lastTrayMenuSignature;

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    _initTray();
    _checkAdmin();
    _loadStartupSetting();
    _startRefreshTimer();
    _loadRefreshInterval();
    _loadServices();
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkAdmin() async {
    final admin = await isAdministrator();
    if (!mounted) return;
    setState(() {
      _isAdmin = admin;
      _adminChecked = true;
    });
    await _updateTrayMenu();
  }

  Future<void> _loadServices() async {
    final available = await listWindowsServices();
    final preferences = await SharedPreferences.getInstance();
    final savedNames = preferences.getStringList(_selectedServicesPreference);
    final selectedNames = savedNames?.map((name) => name.trim()).toSet() ?? {};
    final availableByName = {
      for (final service in available) service.name.trim(): service,
    };
    final selected = selectedNames
        .map((name) => availableByName[name] ?? ServiceDef(name, name))
        .toList();

    if (!mounted) return;
    setState(() {
      _availableServices = available;
      _entries = selected.map(ServiceEntry.new).toList();
      _servicesLoaded = true;
    });
    await _refreshAll();
    await _updateTrayMenu();
  }

  Future<void> _loadStartupSetting() async {
    final enabled = await isLaunchAtStartupEnabled();
    if (!mounted) return;
    setState(() {
      _launchAtStartup = enabled;
    });
  }

  void _startRefreshTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: _refreshIntervalSeconds),
      (_) => _refreshAll(),
    );
  }

  Future<void> _loadRefreshInterval() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getInt(_refreshIntervalPreference) ?? 5;
    final interval = value.clamp(1, 60);
    if (!mounted) return;
    setState(() => _refreshIntervalSeconds = interval);
    _startRefreshTimer();
  }

  Future<void> _setRefreshInterval(int seconds) async {
    final interval = seconds.clamp(1, 60);
    setState(() => _refreshIntervalSeconds = interval);
    _startRefreshTimer();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_refreshIntervalPreference, interval);
  }

  Future<void> _setLaunchAtStartup(bool enabled) async {
    if (_startupUpdating) return;
    setState(() => _startupUpdating = true);
    final error = await setLaunchAtStartup(
      enabled,
      isEnglish: widget.isEnglish,
    );
    if (!mounted) return;
    setState(() {
      _startupUpdating = false;
      if (error == null) _launchAtStartup = enabled;
    });
    if (error != null) _showMessage(error);
  }

  Future<void> _showSettings() async {
    var isDarkTheme = widget.isDarkTheme;
    var isEnglish = widget.isEnglish;
    var launchAtStartup = _launchAtStartup;
    var refreshIntervalSeconds = _refreshIntervalSeconds;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final dialogL10n = AppLocalizations(isEnglish);
          return AlertDialog(
            title: Text(dialogL10n.settings),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(dialogL10n.darkTheme)),
                      Switch(
                        value: isDarkTheme,
                        onChanged: (enabled) {
                          widget.onToggleTheme();
                          setDialogState(() => isDarkTheme = enabled);
                        },
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: Text(dialogL10n.launchAtStartup)),
                      Switch(
                        value: launchAtStartup,
                        onChanged: _startupUpdating
                            ? null
                            : (enabled) async {
                                await _setLaunchAtStartup(enabled);
                                if (mounted) {
                                  setDialogState(
                                    () => launchAtStartup = _launchAtStartup,
                                  );
                                }
                              },
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: Text(dialogL10n.refreshInterval)),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 100,
                        child: DropdownButtonFormField<int>(
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 8),
                          ),
                          initialValue: refreshIntervalSeconds,
                          items: [
                            for (var seconds = 1; seconds <= 60; seconds++)
                              DropdownMenuItem(
                                value: seconds,
                                child: Text('$seconds'),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            _setRefreshInterval(value);
                            setDialogState(
                              () => refreshIntervalSeconds = value,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: Text(dialogL10n.language)),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<bool>(
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 8),
                          ),
                          initialValue: isEnglish,
                          items: const [
                            DropdownMenuItem(
                              value: false,
                              child: Text('Русский'),
                            ),
                            DropdownMenuItem(
                              value: true,
                              child: Text('English'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            widget.onSetLanguage(value);
                            setDialogState(() => isEnglish = value);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(dialogL10n.close),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _chooseServices() async {
    if (!_servicesLoaded) return;
    final selected = await showServiceSelectionDialog(
      context,
      available: _availableServices,
      selectedNames: _entries.map((entry) => entry.def.name).toSet(),
      l10n: l10n,
    );
    if (selected == null || !mounted) return;

    setState(() {
      _entries = selected.map(ServiceEntry.new).toList();
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _selectedServicesPreference,
      selected.map((service) => service.name.trim()).toList(),
    );
    await _refreshAll();
    await _updateTrayMenu(force: true);
  }

  Future<void> _removeService(ServiceEntry entry) async {
    if (!mounted || entry.busy) return;
    setState(() {
      _entries.remove(entry);
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _selectedServicesPreference,
      _entries.map((item) => item.def.name.trim()).toList(),
    );
    await _updateTrayMenu(force: true);
  }

  Future<void> _refreshAll() async {
    if (_refreshing || !_servicesLoaded) return;
    _refreshing = true;
    for (final entry in _entries) {
      if (entry.busy) continue;
      final status = await queryServiceStatus(entry.def.name);
      if (status != ServiceStatus.unknown) entry.status = status;
      if (entry.displayName == entry.def.fallbackDisplayName) {
        final displayName = await queryDisplayName(
          entry.def.name,
          entry.def.fallbackDisplayName,
        );
        entry.displayName = displayName;
      }
      if (!mounted) return;
    }
    _refreshing = false;
    if (mounted) setState(() {});
    await _updateTrayMenu();
  }

  /// Выполняет действие над службой. [fromTray] — вызов из контекстного меню
  /// трея: при успехе не показывает SnackBar, при ошибке открывает окно.
  Future<void> _runAction(
    ServiceEntry entry, {
    required bool start,
    bool fromTray = false,
  }) async {
    if (!_isAdmin) {
      if (fromTray) await _showWindow();
      if (mounted) _showAdminRequiredDialog();
      return;
    }
    setState(() => entry.busy = true);
    await _updateTrayMenu();
    final error = start
        ? await startService(entry.def.name, isEnglish: widget.isEnglish)
        : await stopService(entry.def.name, isEnglish: widget.isEnglish);

    if (!mounted) return;
    setState(() => entry.busy = false);

    if (error != null) {
      if (fromTray) await _showWindow();
      if (mounted) {
        _showMessage(
          '${l10n.operationFailed} ${start ? l10n.start.toLowerCase() : l10n.stop.toLowerCase()} '
          '${l10n.serviceObject} «${entry.def.name}».\n$error',
        );
      }
    } else if (!fromTray) {
      _showMessage(
        '${l10n.service} «${entry.def.name}» '
        '${start ? l10n.serviceStarted : l10n.serviceStopped}.',
      );
      // Дожидаемся фактического перехода службы в целевое состояние,
      // чтобы статус и кнопки обновились сразу.
      await _waitForStatus(
        entry,
        start ? ServiceStatus.running : ServiceStatus.stopped,
        start ? ServiceStatus.startPending : ServiceStatus.stopPending,
      );
    } else {
      // Действие из трея: дожидаемся целевого состояния без SnackBar.
      await _waitForStatus(
        entry,
        start ? ServiceStatus.running : ServiceStatus.stopped,
        start ? ServiceStatus.startPending : ServiceStatus.stopPending,
      );
    }

    // При ошибке просто перечитаем фактический статус службы.
    final status = await queryServiceStatus(entry.def.name);
    if (!mounted) return;
    if (status != ServiceStatus.unknown) {
      setState(() => entry.status = status);
    }
    await _updateTrayMenu();
  }

  Future<void> _restartService(ServiceEntry entry) async {
    await _runAction(entry, start: false);
    if (!mounted || entry.status != ServiceStatus.stopped) return;
    await _runAction(entry, start: true);
  }

  /// Ожидает перехода службы в целевое состояние [target] (до 30 секунд),
  /// на каждом шаге обновляя статус в интерфейсе и меню трея.
  Future<void> _waitForStatus(
    ServiceEntry entry,
    ServiceStatus target,
    ServiceStatus pending, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await queryServiceStatus(entry.def.name);
      if (!mounted) return;
      if (status != ServiceStatus.unknown) {
        setState(() => entry.status = status);
        await _updateTrayMenu();
      }
      if (status == target) return;
      final settled =
          status == ServiceStatus.running || status == ServiceStatus.stopped;
      // Служба перешла в стабильное состояние, отличное от целевого —
      // дальнейшее ожидание бессмысленно.
      if (settled && status != pending) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> _startAll({bool fromTray = false}) async {
    // Сначала MSSQL, затем 1С (у 1С есть зависимость от SQL).
    for (final entry in _entries) {
      await _runAction(entry, start: true, fromTray: fromTray);
    }
  }

  Future<void> _stopAll({bool fromTray = false}) async {
    // Сначала 1С, затем MSSQL.
    for (final entry in _entries.reversed) {
      await _runAction(entry, start: false, fromTray: fromTray);
    }
  }

  // ==========================================================================
  // Системный трей и окно
  // ==========================================================================

  /// Создаёт иконку в системном трее.
  ///
  /// Путь к иконке указывается относительно `data/flutter_assets`
  /// (именно так формирует полный путь сам плагин tray_manager).
  Future<void> _initTray() async {
    try {
      await trayManager.setIcon('assets/tray_icon.ico');
      await trayManager.setToolTip(l10n.appTitle);
      _trayReady = true;
      await _updateTrayMenu(force: true);
    } catch (_) {
      // Если иконку создать не удалось — приложение продолжит работать
      // без трея (например, в окружении без области уведомлений).
      _trayReady = false;
    }
  }

  bool _canStartEntry(ServiceEntry entry) =>
      _isAdmin &&
      !entry.busy &&
      entry.status != ServiceStatus.running &&
      entry.status != ServiceStatus.startPending;

  bool _canStopEntry(ServiceEntry entry) =>
      _isAdmin && !entry.busy && entry.status == ServiceStatus.running;

  bool _canToggleEntry(ServiceEntry entry) =>
      _isAdmin &&
      !entry.busy &&
      (entry.status == ServiceStatus.running ||
          entry.status == ServiceStatus.stopped);

  String _trayStatusIcon(ServiceStatus status) {
    return switch (status) {
      ServiceStatus.running => '■',
      ServiceStatus.stopped => '▶',
      ServiceStatus.startPending || ServiceStatus.stopPending => '⏳',
      ServiceStatus.unknown => '⚠',
    };
  }

  /// Строка-сигнатура текущего состояния служб; по её изменению решаем,
  /// нужно ли пересоздавать меню трея.
  String _trayMenuSignature() {
    final statuses = _entries
        .map((e) => '${e.status.name}:${e.busy}')
        .join('|');
    return '$statuses|admin=$_isAdmin';
  }

  Menu _buildTrayMenu() {
    final items = <MenuItem>[];

    // Управление отдельными службами.
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      items.add(
        MenuItem(
          key: 'toggle_service_$i',
          label: entry.status == ServiceStatus.running
              ? '■ ${l10n.stop}: ${entry.def.name}'
              : entry.status == ServiceStatus.stopped
              ? '▶ ${l10n.start}: ${entry.def.name}'
              : '${_trayStatusIcon(entry.status)} ${entry.def.name}',
          disabled: !_canToggleEntry(entry),
        ),
      );
    }
    items.add(MenuItem.separator());

    items.add(
      MenuItem(
        key: 'start_all',
        label: l10n.startAll,
        disabled: !_entries.any(_canStartEntry),
      ),
    );
    items.add(
      MenuItem(
        key: 'stop_all',
        label: l10n.stopAll,
        disabled: !_entries.any(_canStopEntry),
      ),
    );
    items.add(MenuItem.separator());

    items.add(
      MenuItem(
        key: 'show_window',
        label: l10n.isEnglish ? 'Open window' : 'Открыть окно',
      ),
    );
    items.add(MenuItem(key: 'quit', label: l10n.isEnglish ? 'Exit' : 'Выход'));

    return Menu(items: items);
  }

  /// Обновляет контекстное меню трея, если изменились статусы служб.
  Future<void> _updateTrayMenu({bool force = false}) async {
    if (!_trayReady) return;
    final signature = _trayMenuSignature();
    if (!force && signature == _lastTrayMenuSignature) return;
    _lastTrayMenuSignature = signature;
    try {
      await trayManager.setContextMenu(_buildTrayMenu());
    } catch (_) {
      // Игнорируем ошибки обновления меню — трей может быть недоступен.
    }
  }

  /// Показывает главное окно (восстанавливая его из свёрнутого состояния).
  Future<void> _showWindow() async {
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  /// Скрывает главное окно в трей.
  Future<void> _hideToTray() async {
    await windowManager.hide();
  }

  /// Полностью завершает приложение: убирает иконку из трея и закрывает окно.
  Future<void> _quitApp() async {
    try {
      await trayManager.destroy();
    } catch (_) {
      // Не критично, если иконка уже недоступна.
    }
    await windowManager.destroy();
    exit(0);
  }

  void _handleTrayMenuAction(MenuItem menuItem) {
    final key = menuItem.key ?? '';
    if (key == 'show_window') {
      _showWindow();
      return;
    }
    if (key == 'quit') {
      _quitApp();
      return;
    }
    if (key == 'start_all') {
      _startAll(fromTray: true);
      return;
    }
    if (key == 'stop_all') {
      _stopAll(fromTray: true);
      return;
    }
    if (key.startsWith('toggle_service_')) {
      final index = int.tryParse(key.substring('toggle_service_'.length));
      if (index != null && index >= 0 && index < _entries.length) {
        final entry = _entries[index];
        if (entry.status == ServiceStatus.running ||
            entry.status == ServiceStatus.stopped) {
          _runAction(
            entry,
            start: entry.status == ServiceStatus.stopped,
            fromTray: true,
          );
        }
      }
    }
  }

  // --- TrayListener ---------------------------------------------------------

  @override
  void onTrayIconMouseDown() {
    // Левый клик по иконке трея — показать окно.
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    // Правый клик: обновляем меню и показываем его. На Windows tray_manager
    // не открывает контекстное меню автоматически (плагин лишь шлёт это
    // событие), поэтому меню показывается явным вызовом popUpContextMenu().
    _showTrayMenu();
  }

  /// Показывает контекстное меню трея с актуальным состоянием служб.
  Future<void> _showTrayMenu() async {
    await _updateTrayMenu(force: true);
    // bringAppToFront гарантирует корректный показ меню, даже если главное
    // окно свёрнуто в трей (скрыто).
    // ignore: deprecated_member_use
    await trayManager.popUpContextMenu(bringAppToFront: true);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    _handleTrayMenuAction(menuItem);
  }

  // --- WindowListener -------------------------------------------------------

  @override
  void onWindowClose() {
    // Закрытие окна (крестик, Alt+F4) скрывает приложение в трей.
    _hideToTray();
  }

  void _showAdminRequiredDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.adminDialogTitle),
        content: Text(l10n.adminDialogText),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _relaunchElevated();
            },
            child: Text(l10n.restart),
          ),
        ],
      ),
    );
  }

  Future<void> _relaunchElevated() async {
    final ok = await relaunchElevated();
    if (!mounted) return;
    if (ok) {
      _showMessage(l10n.elevatedRelaunchSuccess);
      await Future<void>.delayed(const Duration(seconds: 2));
      exit(0);
    } else {
      _showMessage(l10n.elevatedRelaunchFailure);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: ColoredBox(
          color: theme.colorScheme.surface,
          child: Column(
            children: [
              SizedBox(
                height: kWindowCaptionHeight,
                child: WindowCaption(
                  brightness: theme.brightness,
                  backgroundColor: theme.colorScheme.surface,
                  title: Text(l10n.appTitle),
                ),
              ),
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 280,
                      child: FilledButton.icon(
                        onPressed: _isAdmin ? _startAll : null,
                        icon: const Icon(Icons.play_circle_outline),
                        label: Text(l10n.startAll),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 280,
                      child: FilledButton.tonalIcon(
                        onPressed: _isAdmin ? _stopAll : null,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: Text(l10n.stopAll),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: l10n.settings,
                      icon: const Icon(Icons.settings),
                      onPressed: _showSettings,
                    ),
                    IconButton(
                      tooltip: l10n.chooseServices,
                      icon: const Icon(Icons.checklist),
                      onPressed: _servicesLoaded ? _chooseServices : null,
                    ),
                    IconButton(
                      tooltip: l10n.showInTray,
                      icon: const Icon(Icons.picture_in_picture_alt_outlined),
                      onPressed: _hideToTray,
                    ),
                    IconButton(
                      tooltip: l10n.exit,
                      icon: const Icon(Icons.logout),
                      onPressed: _quitApp,
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_adminChecked)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (!_isAdmin)
            AdminBanner(onRelaunch: _relaunchElevated, l10n: l10n),
          if (!_servicesLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_entries.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(l10n.emptyServices, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _chooseServices,
                      icon: const Icon(Icons.checklist),
                      label: Text(l10n.chooseServices),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          ..._entries.map(
            (entry) => ServiceCard(
              entry: entry,
              l10n: l10n,
              onStart: () => _runAction(entry, start: true),
              onStop: () => _runAction(entry, start: false),
              onRestart: () => _restartService(entry),
              onRemove: () => _removeService(entry),
            ),
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 16),
          Text(
            l10n.trayHint,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _AdminBanner extends StatelessWidget {
  const _AdminBanner({required this.onRelaunch});

  final VoidCallback onRelaunch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.shield_outlined, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Приложение запущено без прав администратора.\n'
                'Для запуска и остановки служб перезапустите его '
                'от имени администратора.',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.onErrorContainer,
                foregroundColor: scheme.errorContainer,
              ),
              onPressed: onRelaunch,
              child: const Text('Перезапустить'),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.entry,
    required this.onStart,
    required this.onStop,
  });

  final ServiceEntry entry;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = switch (entry.status) {
      ServiceStatus.running => Colors.green,
      ServiceStatus.stopped => theme.colorScheme.error,
      ServiceStatus.startPending || ServiceStatus.stopPending => Colors.orange,
      ServiceStatus.unknown => Colors.grey,
    };
    final statusIcon = switch (entry.status) {
      ServiceStatus.running => Icons.check_circle,
      ServiceStatus.stopped => Icons.cancel,
      ServiceStatus.startPending ||
      ServiceStatus.stopPending => Icons.hourglass_top,
      ServiceStatus.unknown => Icons.help_outline,
    };

    final canStart = !entry.busy && entry.status != ServiceStatus.running;
    final canStop = !entry.busy && entry.status != ServiceStatus.stopped;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(statusIcon, color: statusColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.def.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(entry.displayName, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusPill(status: entry.status),
              ],
            ),
            if (entry.busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: canStart ? onStart : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Запустить'),
                ),
                OutlinedButton.icon(
                  onPressed: canStop ? onStop : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Остановить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final ServiceStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ServiceStatus.running => Colors.green,
      ServiceStatus.stopped => Theme.of(context).colorScheme.error,
      ServiceStatus.startPending || ServiceStatus.stopPending => Colors.orange,
      ServiceStatus.unknown => Colors.grey,
    };
    final icon = switch (status) {
      ServiceStatus.running => Icons.check_circle,
      ServiceStatus.stopped => Icons.cancel,
      ServiceStatus.startPending ||
      ServiceStatus.stopPending => Icons.hourglass_top,
      ServiceStatus.unknown => Icons.help_outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
