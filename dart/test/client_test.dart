import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:misar_reach/misar_reach.dart';
import 'package:test/test.dart';

MisarReachClient _client(http.Client mock, {int maxRetries = 1}) =>
    MisarReachClient(
      apiKey: 'mrk_test',
      maxRetries: maxRetries,
      httpClient: mock,
    );

http.Response _json(int status, Map<String, dynamic> body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('MisarReachClient', () {
    test('leads.search POSTs /lead-finder/search', () async {
      late Uri seen;
      final mock = MockClient((req) async {
        seen = req.url;
        return _json(201, {'jobId': 'job_1'});
      });
      final res = await _client(mock).leads.search({'query': 'SaaS'});
      expect(res['jobId'], 'job_1');
      expect(seen.path, '/reach/api/lead-finder/search');
    });

    test('leads.list forwards query params', () async {
      late Uri seen;
      final mock = MockClient((req) async {
        seen = req.url;
        return _json(200, {'leads': [], 'total': 0});
      });
      final res = await _client(mock).leads.list(params: {'limit': 5});
      expect(res['total'], 0);
      expect(seen.queryParameters['limit'], '5');
    });

    test('deals.create POSTs /deals', () async {
      final mock =
          MockClient((_) async => _json(201, {'id': 'deal_1'}));
      final res = await _client(mock).deals.create({'title': 'Acme'});
      expect(res['id'], 'deal_1');
    });

    test('pipeline.get GETs /pipeline', () async {
      final mock = MockClient((_) async => _json(200, {'stages': []}));
      final res = await _client(mock).pipeline.get();
      expect(res.containsKey('stages'), isTrue);
    });

    test('channels.status GETs /channels/status', () async {
      final mock = MockClient(
          (_) async => _json(200, {'sms': {'connected': false}}));
      final res = await _client(mock).channels.status();
      expect((res['sms'] as Map)['connected'], false);
    });

    test('settings.setSenderAddress PUTs /settings/sender-address', () async {
      late String method;
      final mock = MockClient((req) async {
        method = req.method;
        return _json(200, {'ok': true});
      });
      final res = await _client(mock)
          .settings
          .setSenderAddress({'email': 'a@b.com'});
      expect(res['ok'], true);
      expect(method, 'PUT');
    });

    test('sends Bearer mrk_ Authorization header', () async {
      late Map<String, String> headers;
      final mock = MockClient((req) async {
        headers = req.headers;
        return _json(200, {});
      });
      await _client(mock).channels.status();
      expect(headers['Authorization'], 'Bearer mrk_test');
    });

    test('throws AuthError on 401', () async {
      final mock =
          MockClient((_) async => _json(401, {'error': 'Unauthorized'}));
      expect(
        () => _client(mock).leads.search({}),
        throwsA(isA<AuthError>().having((e) => e.status, 'status', 401)),
      );
    });

    test('throws NotFoundError on 404', () async {
      final mock = MockClient((_) async => _json(404, {'error': 'nope'}));
      expect(
        () => _client(mock).campaigns.get('x'),
        throwsA(isA<NotFoundError>()),
      );
    });

    test('throws RateLimitError with retryAfter on 429', () async {
      final mock = MockClient(
          (_) async => _json(429, {'error': 'slow', 'retryAfter': 9}));
      expect(
        () => _client(mock).leads.search({}),
        throwsA(isA<RateLimitError>()
            .having((e) => e.retryAfter, 'retryAfter', 9)),
      );
    });

    test('throws UpgradeRequiredError on 429 upgrade', () async {
      final mock = MockClient(
          (_) async => _json(429, {'error': 'upgrade', 'upgrade': true}));
      expect(
        () => _client(mock).leads.enrich({}),
        throwsA(isA<UpgradeRequiredError>()),
      );
    });

    test('retries on 503 then succeeds', () async {
      var calls = 0;
      final mock = MockClient((_) async {
        calls++;
        if (calls == 1) return _json(503, {'error': 'down'});
        return _json(200, {'stages': []});
      });
      final res = await _client(mock, maxRetries: 2).pipeline.get();
      expect(res.containsKey('stages'), isTrue);
      expect(calls, 2);
    });

    test('streamJob yields parsed SSE events', () async {
      final sse = 'event: progress\ndata: {"pct":50}\n\n'
          'event: done\ndata: {"leads":3}\n\n';
      final mock = MockClient.streaming((req, bodyStream) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode(sse)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final events =
          await _client(mock).leads.streamJob('job_1').toList();
      expect(events.length, 2);
      expect(events.first.event, 'progress');
      expect((events.first.data as Map)['pct'], 50);
      expect((events.last.data as Map)['leads'], 3);
    });
  });
}
