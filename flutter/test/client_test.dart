import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:misar_reach_flutter/misar_reach_flutter.dart';

MisarReachClient _client(http.Client mock, {int maxRetries = 1}) =>
    MisarReachClient(
      apiKey: 'mrk_test',
      maxRetries: maxRetries,
      httpClient: mock,
    );

/// Streams the pieces as one `text/event-stream` body, so a frame boundary can
/// land mid-chunk — where buffering bugs show up.
MockClient _sseMock(List<String> pieces) =>
    MockClient.streaming((req, bodyStream) async => http.StreamedResponse(
          Stream.fromIterable(pieces.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        ));

MockClient _jsonMock(String body, {int status = 200}) => MockClient(
      (req) async => http.Response(body, status,
          headers: {'content-type': 'application/json'}),
    );

void main() {
  group('rest', () {
    test('leads.search() returns the parsed body', () async {
      final result = await _client(_jsonMock('{"jobId":"job_1","status":"queued"}'))
          .leads
          .search({'query': 'SaaS founders'});

      expect(result['jobId'], 'job_1');
    });

    test('pipeline.get() returns the board', () async {
      final result = await _client(_jsonMock('{"stages":[{"id":"interested"}]}'))
          .pipeline
          .get();

      expect(result['stages'][0]['id'], 'interested');
    });

    test('deals.create() posts and returns the deal', () async {
      final result = await _client(_jsonMock('{"id":"deal_1"}'))
          .deals
          .create({'leadEmail': 'cto@acme.com'});

      expect(result['id'], 'deal_1');
    });

    test('channels.status() returns per-channel state', () async {
      final result = await _client(_jsonMock('{"sms":{"connected":true}}'))
          .channels
          .status();

      expect(result['sms']['connected'], isTrue);
    });

    test('a 401 raises with the status', () async {
      expect(
        () => _client(_jsonMock('{"error":"unauthorized"}', status: 401)).pipeline.get(),
        throwsA(isA<MisarReachException>()),
      );
    });
  });

  group('plan', () {
    test('plan.get() reports caps, usage and no upgrade when nothing is spent',
        () async {
      final mock = _jsonMock(
        '{"plan":{"slug":"pro","name":"Pro"},'
        '"usage":{"lead_searches":{"used":12,"limit":100,"remaining":88,"period":"month"}},'
        '"exhausted":[],"upgrade":null}',
      );

      final result = await _client(mock).plan.get();

      expect(result['plan']['slug'], 'pro');
      expect(result['usage']['lead_searches']['remaining'], 88);
      // upgrade is null precisely when nothing is exhausted, so its presence is
      // the signal to show an upgrade path.
      expect(result['upgrade'], isNull);
    });

    test('plan.get() carries the upgrade offer once a cap is spent', () async {
      final mock = _jsonMock(
        '{"plan":{"slug":"free"},'
        '"usage":{"lead_searches":{"used":3,"limit":3,"remaining":0,"period":"month"}},'
        '"exhausted":["lead_searches"],'
        '"upgrade":{"features":["lead_searches"],'
        '"url":"https://misarreach.com/settings?tab=billing"}}',
      );

      final result = await _client(mock).plan.get();

      expect(result['exhausted'], contains('lead_searches'));
      expect(result['upgrade']['url'],
          'https://misarreach.com/settings?tab=billing');
    });

    test('an unlimited cap reports null rather than zero', () async {
      // null means unlimited; 0 would read as exhausted, which is the opposite.
      final mock = _jsonMock(
        '{"plan":{"slug":"scale"},'
        '"usage":{"lead_searches":{"used":9000,"limit":null,"remaining":null,'
        '"period":"month"}},"exhausted":[],"upgrade":null}',
      );

      final result = await _client(mock).plan.get();

      expect(result['usage']['lead_searches']['limit'], isNull);
      expect(result['usage']['lead_searches']['remaining'], isNull);
    });
  });

  group('streaming', () {
    test('streamJob() yields each named frame', () async {
      // The boundary between the first two frames is split across two chunks.
      final mock = _sseMock([
        'event: progress\ndata: {"message":"searching"}\n',
        '\n: keepalive\n\n',
        'event: found\ndata: {"total":12}\n\n',
        'event: complete\ndata: {"total_found":12}\n\n',
      ]);

      final seen = await _client(mock).leads.streamJob('job_1').toList();

      // The keepalive comment must not surface as an event.
      expect(seen.map((e) => e.event), ['progress', 'found', 'complete']);
      expect(seen[1].data['total'], 12);
    });

    test('an already-finished job is reported as a terminal frame', () async {
      // The route answers a finished job with a JSON snapshot rather than a
      // stream; parsed as SSE that yields nothing at all.
      final mock = _jsonMock('{"status":"done","total_found":42}');

      final seen = await _client(mock).leads.streamJob('job_done').toList();

      expect(seen.length, 1);
      expect(seen.first.event, 'complete');
      expect(seen.first.data['total_found'], 42);
    });

    test('a failed job is reported as an error frame', () async {
      final mock = _jsonMock('{"status":"failed","error":"no sources"}');

      final seen = await _client(mock).leads.streamJob('job_bad').toList();

      expect(seen.first.event, 'error');
    });
  });
}
