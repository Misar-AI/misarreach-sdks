import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:misar_reach_flutter/misar_reach_flutter.dart';

import 'client_test.mocks.dart';

@GenerateMocks([http.Client, SecureKeyStore])
void main() {
  late MockClient mockHttp;
  late MisarReachClient client;

  setUp(() {
    mockHttp = MockClient();
    client = MisarReachClient(apiKey: 'mrk_test', httpClient: mockHttp);
  });

  http.Response ok(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200);
  http.Response err(int status, Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), status);

  test('leads.search POSTs /lead-finder/search', () async {
    when(mockHttp.post(any, headers: anyNamed('headers'), body: anyNamed('body')))
        .thenAnswer((_) async => ok({'jobId': 'job_1'}));
    final res = await client.leads.search({'query': 'SaaS'});
    expect(res['jobId'], 'job_1');
  });

  test('deals.create POSTs /deals', () async {
    when(mockHttp.post(any, headers: anyNamed('headers'), body: anyNamed('body')))
        .thenAnswer((_) async => ok({'id': 'deal_1'}));
    final res = await client.deals.create({'title': 'Acme'});
    expect(res['id'], 'deal_1');
  });

  test('pipeline.get GETs /pipeline', () async {
    when(mockHttp.get(any, headers: anyNamed('headers')))
        .thenAnswer((_) async => ok({'stages': []}));
    final res = await client.pipeline.get();
    expect(res.containsKey('stages'), isTrue);
  });

  test('channels.status GETs /channels/status', () async {
    when(mockHttp.get(any, headers: anyNamed('headers')))
        .thenAnswer((_) async => ok({'sms': {'connected': false}}));
    final res = await client.channels.status();
    expect((res['sms'] as Map)['connected'], false);
  });

  test('sends Bearer mrk_ Authorization header', () async {
    when(mockHttp.get(any, headers: anyNamed('headers')))
        .thenAnswer((_) async => ok({}));
    await client.channels.status();
    final captured =
        verify(mockHttp.get(any, headers: captureAnyNamed('headers'))).captured;
    final headers = captured.first as Map<String, String>;
    expect(headers['Authorization'], 'Bearer mrk_test');
  });

  test('throws MisarReachAuthException on 401', () async {
    when(mockHttp.post(any, headers: anyNamed('headers'), body: anyNamed('body')))
        .thenAnswer((_) async => err(401, {'error': 'Unauthorized'}));
    expect(
      () => client.leads.search({}),
      throwsA(isA<MisarReachAuthException>()
          .having((e) => e.statusCode, 'statusCode', 401)),
    );
  });

  test('throws MisarReachRateLimitException with retryAfter on 429', () async {
    when(mockHttp.post(any, headers: anyNamed('headers'), body: anyNamed('body')))
        .thenAnswer((_) async => err(429, {'error': 'slow', 'retryAfter': 7}));
    expect(
      () => client.leads.search({}),
      throwsA(isA<MisarReachRateLimitException>()
          .having((e) => e.retryAfter, 'retryAfter', 7)),
    );
  });

  test('throws MisarReachUpgradeRequiredException on 429 upgrade', () async {
    when(mockHttp.post(any, headers: anyNamed('headers'), body: anyNamed('body')))
        .thenAnswer((_) async => err(429, {'error': 'upgrade', 'upgrade': true}));
    expect(
      () => client.leads.enrich({}),
      throwsA(isA<MisarReachUpgradeRequiredException>()),
    );
  });

  test('retries on 503 then succeeds', () async {
    var calls = 0;
    when(mockHttp.get(any, headers: anyNamed('headers'))).thenAnswer((_) async {
      calls++;
      if (calls == 1) return err(503, {'error': 'down'});
      return ok({'stages': []});
    });
    final res = await client.pipeline.get();
    expect(res.containsKey('stages'), isTrue);
    expect(calls, 2);
  });

  test('streamJob yields parsed SSE events', () async {
    final sse = 'event: progress\ndata: {"pct":50}\n\n'
        'event: done\ndata: {"leads":3}\n\n';
    when(mockHttp.send(any)).thenAnswer((_) async => http.StreamedResponse(
          Stream.value(utf8.encode(sse)),
          200,
          headers: {'content-type': 'text/event-stream'},
        ));
    final events = await client.leads.streamJob('job_1').toList();
    expect(events.length, 2);
    expect(events.first.event, 'progress');
    expect((events.first.data as Map)['pct'], 50);
    expect((events.last.data as Map)['leads'], 3);
  });

  test('withSecureStorage throws when no key stored', () async {
    final store = MockSecureKeyStore();
    when(store.loadApiKey()).thenAnswer((_) async => null);
    await expectLater(
      MisarReachClient.withSecureStorage(keyStore: store),
      throwsA(isA<StateError>()),
    );
  });

  test('withSecureStorage creates client with stored key', () async {
    final store = MockSecureKeyStore();
    when(store.loadApiKey()).thenAnswer((_) async => 'mrk_stored');
    when(mockHttp.get(any, headers: anyNamed('headers')))
        .thenAnswer((_) async => ok({}));

    final secure = await MisarReachClient.withSecureStorage(
      keyStore: store,
      httpClient: mockHttp,
    );
    await secure.channels.status();

    final captured =
        verify(mockHttp.get(any, headers: captureAnyNamed('headers'))).captured;
    final headers = captured.first as Map<String, String>;
    expect(headers['Authorization'], 'Bearer mrk_stored');
  });
}
