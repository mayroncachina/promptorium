import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/tray_service.dart';

class _FakeBackend implements TrayBackend {
  _FakeBackend({this.error});

  final Object? error;
  String? iconAsset;
  String? tooltip;
  List<TrayMenuEntry> menu = [];
  Future<void> Function()? onActivate;
  bool disposed = false;

  @override
  Future<void> show({
    required String iconAsset,
    required String tooltip,
    required List<TrayMenuEntry> menu,
    required Future<void> Function() onActivate,
  }) async {
    if (error != null) throw error!;
    this.iconAsset = iconAsset;
    this.tooltip = tooltip;
    this.menu = menu;
    this.onActivate = onActivate;
  }

  @override
  Future<void> dispose() async => disposed = true;

  Future<void> select(String label) =>
      menu.firstWhere((e) => e.label == label).onSelected();
}

class _FakeWindow implements TrayWindow {
  bool visible = true;
  bool minimized = false;
  bool focused = true;
  final List<String> calls = [];

  @override
  Future<bool> isVisible() async => visible;
  @override
  Future<bool> isMinimized() async => minimized;
  @override
  Future<bool> isFocused() async => focused;
  @override
  Future<void> show() async {
    calls.add('show');
    visible = true;
  }

  @override
  Future<void> restore() async {
    calls.add('restore');
    minimized = false;
  }

  @override
  Future<void> focus() async {
    calls.add('focus');
    focused = true;
  }

  @override
  Future<void> hide() async {
    calls.add('hide');
    visible = false;
    focused = false;
  }
}

void main() {
  late _FakeWindow window;
  late List<String> logs;
  late int quits;

  TrayService service({
    bool isLinux = true,
    required TrayBackend Function() backend,
  }) => TrayService(
    isLinux: isLinux,
    backend: backend,
    window: window,
    onQuit: () async => quits++,
    log: logs.add,
  );

  setUp(() {
    window = _FakeWindow();
    logs = [];
    quits = 0;
  });

  group('R1/R4: ícone e menu', () {
    test(
      'no Linux mostra o ícone do app com tooltip e menu Abrir/Sair',
      () async {
        final backend = _FakeBackend();
        final tray = service(backend: () => backend);
        expect(await tray.start(), isTrue);
        expect(tray.isActive, isTrue);
        expect(backend.iconAsset, 'assets/icon/icon-64.png');
        expect(backend.tooltip, 'Promptorium');
        expect(backend.menu.map((e) => e.label), ['Abrir', 'Sair']);
        expect(logs, isEmpty);
      },
    );
  });

  group('R7: bandeja indisponível', () {
    test(
      'falha do backend registra aviso, não lança e segue sem ícone',
      () async {
        final backend = _FakeBackend(error: StateError('sem StatusNotifier'));
        final tray = service(backend: () => backend);
        expect(await tray.start(), isFalse);
        expect(tray.isActive, isFalse);
        expect(logs.single, contains('bandeja indisponível'));
        expect(logs.single, contains('sem StatusNotifier'));
        expect(backend.disposed, isTrue);
      },
    );

    test('falha ao criar o backend também é só um aviso', () async {
      final tray = service(
        backend: () => throw UnsupportedError('biblioteca ausente'),
      );
      expect(await tray.start(), isFalse);
      expect(logs.single, contains('biblioteca ausente'));
    });
  });

  group('R8: fora do Linux', () {
    test('não cria backend nem ícone', () async {
      var created = 0;
      final tray = service(
        isLinux: false,
        backend: () {
          created++;
          return _FakeBackend();
        },
      );
      expect(await tray.start(), isFalse);
      expect(created, 0);
      expect(tray.isActive, isFalse);
      expect(window.calls, isEmpty);
      expect(logs, isEmpty);
    });
  });

  group('R2/R3: clique no ícone', () {
    late _FakeBackend backend;

    setUp(() async {
      backend = _FakeBackend();
      await service(backend: () => backend).start();
    });

    test('janela visível e em foco: esconde', () async {
      await backend.onActivate!();
      expect(window.calls, ['hide']);
      expect(window.visible, isFalse);
    });

    test('janela escondida: mostra e dá foco', () async {
      window
        ..visible = false
        ..focused = false;
      await backend.onActivate!();
      expect(window.calls, ['show', 'focus']);
    });

    test('janela minimizada: mostra, restaura e dá foco', () async {
      window.minimized = true;
      await backend.onActivate!();
      expect(window.calls, ['show', 'restore', 'focus']);
    });

    test('janela visível sem foco: traz para a frente', () async {
      window.focused = false;
      await backend.onActivate!();
      expect(window.calls, ['show', 'focus']);
    });

    test('dois cliques escondem e reabrem a janela', () async {
      await backend.onActivate!();
      await backend.onActivate!();
      expect(window.calls, ['hide', 'show', 'focus']);
      expect(window.visible && window.focused, isTrue);
    });

    test('erro da janela é só registrado', () async {
      final tray = TrayService(
        isLinux: true,
        backend: _FakeBackend.new,
        window: _ThrowingWindow(),
        onQuit: () async {},
        log: logs.add,
      );
      await tray.toggle();
      await tray.open();
      expect(logs, hasLength(2));
    });
  });

  group('R4/R6: menu', () {
    test('"Abrir" traz a janela minimizada de volta', () async {
      final backend = _FakeBackend();
      await service(backend: () => backend).start();
      window.minimized = true;
      await backend.select('Abrir');
      expect(window.calls, ['show', 'restore', 'focus']);
    });

    test('"Abrir" com a janela já em foco não a esconde', () async {
      final backend = _FakeBackend();
      await service(backend: () => backend).start();
      await backend.select('Abrir');
      expect(window.calls, ['show', 'focus']);
    });

    test(
      '"Sair" remove o ícone e usa o caminho de fechamento uma vez',
      () async {
        final backend = _FakeBackend();
        final tray = service(backend: () => backend);
        await tray.start();
        await backend.select('Sair');
        await backend.select('Sair');
        expect(quits, 1);
        expect(backend.disposed, isTrue);
        expect(tray.isActive, isFalse);
        expect(window.calls, isEmpty);
      },
    );
  });
}

class _ThrowingWindow extends _FakeWindow {
  @override
  Future<bool> isVisible() => throw StateError('x');
  @override
  Future<bool> isMinimized() => throw StateError('x');
}
