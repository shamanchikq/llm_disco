import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:llm_disco_test1/providers/connection_provider.dart';
import '../helpers/mocks.dart';

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

    test('rejects invalid ports without touching the network', () async {
      for (final bad in ['abc', '', '0', '-1', '70000']) {
        final ok = await provider.connect(
            ip: '127.0.0.1', port: bad, useHttp: true);
        expect(ok, isFalse, reason: 'port "$bad" must be rejected');
        expect(provider.service, isNull, reason: 'port "$bad"');
      }
      expect(provider.error, contains('Port'));
    });

    test('brackets bare IPv6 hosts in the base URL', () async {
      await provider.connect(ip: '::1', port: '11434', useHttp: true);

      expect(provider.error, contains('http://[::1]:11434'));
    });

    test('auth failures are reported distinctly from dead servers',
        () async {
      final mock = MockOllamaService();
      when(() => mock.testConnectionStatus()).thenAnswer((_) async => 403);
      final p = ConnectionProvider(serviceFactory: (_, {authHeader}) => mock);

      final ok = await p.connect(
        ip: '10.0.0.5',
        port: '11434',
        useHttp: true,
        authToken: 'secret',
      );

      expect(ok, isFalse);
      expect(p.error, contains('Authentication failed'));
      expect(p.service, isNull);
    });

    test('a 200 probe connects and exposes the service', () async {
      final mock = MockOllamaService();
      when(() => mock.testConnectionStatus()).thenAnswer((_) async => 200);
      final p = ConnectionProvider(serviceFactory: (_, {authHeader}) => mock);

      final ok = await p.connect(
          ip: '10.0.0.5', port: '11434', useHttp: true);

      expect(ok, isTrue);
      expect(p.isConnected, isTrue);
      expect(p.service, same(mock));
    });
  });

  group('ConnectionProvider input handling', () {
    late List<String> createdUrls;
    late List<String?> authHeaders;

    // A provider whose factory records what it was asked to build and whose
    // probe always succeeds — so nothing here touches the network, and a
    // non-empty `createdUrls` means the input got past validation.
    ConnectionProvider build() {
      createdUrls = [];
      authHeaders = [];
      return ConnectionProvider(serviceFactory: (url, {authHeader}) {
        createdUrls.add(url);
        authHeaders.add(authHeader);
        final mock = MockOllamaService();
        when(() => mock.testConnectionStatus()).thenAnswer((_) async => 200);
        return mock;
      });
    }

    Future<bool> connect(ConnectionProvider p, String ip,
            {String port = '11434', String? authToken}) =>
        p.connect(ip: ip, port: port, useHttp: true, authToken: authToken);

    test('accepts hostnames and IPv4 addresses', () async {
      final p = build();

      expect(await connect(p, '192.168.1.5'), isTrue);
      expect(p.baseUrl, 'http://192.168.1.5:11434');
      expect(await connect(p, '  my-pc.local '), isTrue);
      expect(p.baseUrl, 'http://my-pc.local:11434');
    });

    test('drops trailing slashes', () async {
      final p = build();

      expect(await connect(p, '192.168.1.5/'), isTrue);
      expect(p.baseUrl, 'http://192.168.1.5:11434');
      expect(await connect(p, 'my-pc.local//'), isTrue);
      expect(p.baseUrl, 'http://my-pc.local:11434');
    });

    test('rejects a scheme or path with a specific message', () async {
      final p = build();

      for (final bad in [
        'http://192.168.1.5',
        'https://192.168.1.5/',
        'http://192.168.1.5:11434',
        'my-pc.local/api',
        'my-pc.local/api/',
      ]) {
        expect(await connect(p, bad), isFalse, reason: bad);
        expect(p.error, contains('no http:// prefix or path'), reason: bad);
        expect(p.service, isNull, reason: bad);
        expect(p.isConnecting, isFalse, reason: bad);
      }
      expect(createdUrls, isEmpty);
    });

    test('rejects host:port and points at the Port field', () async {
      final p = build();

      for (final bad in [
        '192.168.1.5:11434',
        'localhost:11434',
        'my-pc.local:80',
        '[::1]:11434',
        'abc:def',
      ]) {
        expect(await connect(p, bad), isFalse, reason: bad);
        expect(p.error, contains('Port field'), reason: bad);
        expect(p.service, isNull, reason: bad);
      }
      expect(createdUrls, isEmpty);
    });

    test('brackets genuine IPv6 literals, bracketed or not', () async {
      final p = build();

      for (final entry in {
        '::1': 'http://[::1]:11434',
        '[::1]': 'http://[::1]:11434',
        '2001:db8::1': 'http://[2001:db8::1]:11434',
        '[2001:db8::1]': 'http://[2001:db8::1]:11434',
      }.entries) {
        expect(await connect(p, entry.key), isTrue, reason: entry.key);
        expect(p.baseUrl, entry.value, reason: entry.key);
      }
    });

    test('rejects a bracketed value that is not IPv6', () async {
      final p = build();

      expect(await connect(p, '[abc]'), isFalse);
      expect(p.error, contains('IPv6'));
      expect(createdUrls, isEmpty);
    });

    test('rejects auth tokens that cannot go in a header', () async {
      final p = build();

      for (final bad in [
        'abc\ndef',
        'abc\r\ndef',
        'ab\tc',
        'tok\u0000en',
        'tökén',
      ]) {
        expect(await connect(p, '10.0.0.5', authToken: bad), isFalse,
            reason: bad.codeUnits.toString());
        expect(p.error, contains('invalid characters'),
            reason: bad.codeUnits.toString());
        expect(p.service, isNull);
        expect(p.isConnecting, isFalse);
      }
      expect(createdUrls, isEmpty);
    });

    test('a token with stray surrounding whitespace is trimmed, not rejected',
        () async {
      final p = build();

      expect(await connect(p, '10.0.0.5', authToken: ' secret\n'), isTrue);
      expect(authHeaders.single, 'Bearer secret');
    });

    test('a token that names a scheme is used verbatim', () async {
      final p = build();

      expect(await connect(p, '10.0.0.5', authToken: 'Basic dXNlcjpwdw=='),
          isTrue);
      expect(authHeaders.single, 'Basic dXNlcjpwdw==');
    });

    test('a rejected input leaves the previous base URL alone', () async {
      final p = build();
      await connect(p, '10.0.0.5');

      await connect(p, 'http://elsewhere');

      expect(p.baseUrl, 'http://10.0.0.5:11434');
      expect(createdUrls, ['http://10.0.0.5:11434']);
    });
  });
}
