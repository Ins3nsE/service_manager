import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:service_manager/main.dart';

void main() {
  testWidgets('Отображает обе отслеживаемые службы', (tester) async {
    await tester.pumpWidget(const ServiceManagerApp());

    expect(find.text('Менеджер служб Windows'), findsOneWidget);

    // Убираем приложение, чтобы остановить периодический таймер.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('parseServiceStatus', () {
    test('английская локаль Windows (ключ STATE)', () {
      const out =
          'SERVICE_NAME: MSSQLSERVER\n'
          '        TYPE               : 10  WIN32_OWN_PROCESS\n'
          '        STATE              : 4  RUNNING\n'
          '                                (STOPPABLE, PAUSABLE, '
          'ACCEPTS_SHUTDOWN)\n'
          '        WIN32_EXIT_CODE    : 0  (0x0)\n';
      expect(parseServiceStatus(out), ServiceStatus.running);
    });

    test('русская локаль Windows (ключ «Состояние»)', () {
      const out =
          'Имя_службы: MSSQLSERVER \n'
          '        Тип                : 10  WIN32_OWN_PROCESS  \n'
          '        Состояние          : 4  RUNNING \n'
          '                                (STOPPABLE, PAUSABLE, '
          'ACCEPTS_SHUTDOWN)\n'
          '        Код_выхода_Win32   : 0  (0x0)\n';
      expect(parseServiceStatus(out), ServiceStatus.running);
    });

    test('STOPPED (код 1)', () {
      const out = 'Состояние          : 1  STOPPED\n';
      expect(parseServiceStatus(out), ServiceStatus.stopped);
    });

    test('START_PENDING (код 2)', () {
      const out = 'Состояние          : 2  START_PENDING\n';
      expect(parseServiceStatus(out), ServiceStatus.startPending);
    });

    test('STOP_PENDING (код 3)', () {
      const out = 'Состояние          : 3  STOP_PENDING\n';
      expect(parseServiceStatus(out), ServiceStatus.stopPending);
    });

    test('неизвестная локаль — запасной вариант по имени состояния', () {
      const out = 'Zustand             : 4  RUNNING\n';
      expect(parseServiceStatus(out), ServiceStatus.running);
    });

    test('пустой или неинформативный вывод — unknown', () {
      expect(parseServiceStatus(''), ServiceStatus.unknown);
      expect(
        parseServiceStatus('[SC] OpenService: Ошибка 1060'),
        ServiceStatus.unknown,
      );
    });
  });
}
