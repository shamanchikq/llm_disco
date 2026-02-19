import 'package:flutter_test/flutter_test.dart';
import 'package:llm_disco_test1/providers/connection_provider.dart';

void main() {
  group('ConnectionProvider', () {
    late ConnectionProvider provider;

    setUp(() {
      provider = ConnectionProvider();
    });

    test('initial state', () {
      expect(provider.isConnected, isFalse);
      expect(provider.isConnecting, isFalse);
      expect(provider.service, isNull);
      expect(provider.error, isNull);
      expect(provider.baseUrl, isEmpty);
    });

    test('connect fails on unreachable server', () async {
      // shouldn't crash on bad input
      final result = await provider.connect(
        ip: '127.0.0.1',
        port: '1',
        useHttp: true,
      );

      expect(result, isFalse);
      expect(provider.isConnected, isFalse);
      expect(provider.error, isNotNull);
    });

    test('connect builds URL and disconnect resets state', () async {
      // verify http url format
      await provider.connect(
        ip: '192.168.1.100',
        port: '11434',
        useHttp: true,
      );
      expect(provider.error, contains('http://192.168.1.100:11434'));

      // verify https url format
      await provider.connect(
        ip: '192.168.1.100',
        port: '11434',
        useHttp: false,
      );
      expect(provider.error, contains('https://192.168.1.100:11434'));

      // disconnect should reset everything
      provider.disconnect();
      expect(provider.isConnected, isFalse);
      expect(provider.service, isNull);
      expect(provider.baseUrl, isEmpty);
      expect(provider.error, isNull);
    });
  });
}
