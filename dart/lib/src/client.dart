import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'errors.dart';

const _defaultBaseUrl = 'https://api.misar.io/reach/api';
const _retryable = {429, 500, 502, 503, 504};

/// A single Server-Sent Event emitted by a lead-finder job stream.
class ReachSseEvent {
  /// The SSE `event:` name, if any.
  final String? event;

  /// The `data:` payload — a decoded JSON object/array, or the raw string.
  final dynamic data;

  const ReachSseEvent(this.event, this.data);

  @override
  String toString() => 'ReachSseEvent($event, $data)';
}

abstract class _Resource {
  final MisarReachClient _client;
  const _Resource(this._client);
}

/// Dart client for the MisarReach developer API (`api.misar.io/reach/api`).
///
/// ```dart
/// final reach = MisarReachClient(apiKey: 'mrk_...');
/// final job = await reach.leads.search({'query': 'SaaS founders'});
/// ```
class MisarReachClient {
  final String _apiKey;
  final String _baseUrl;
  final int _maxRetries;
  final http.Client _httpClient;

  late final LeadsResource leads;
  late final DealsResource deals;
  late final PipelineResource pipeline;
  late final ChannelsResource channels;
  late final AutopilotResource autopilot;
  late final SalesAgentResource salesAgent;
  late final CampaignsResource campaigns;
  late final ContactsResource contacts;
  late final ConversationsResource conversations;
  late final WorkspacesResource workspaces;
  late final SettingsResource settings;
  late final AdsResource ads;
  late final CampaignTemplatesResource campaignTemplates;
  late final DeliverabilityResource deliverability;
  late final NotificationsResource notifications;
  late final WebhooksResource webhooks;

  MisarReachClient({
    required String apiKey,
    String baseUrl = _defaultBaseUrl,
    int maxRetries = 3,
    http.Client? httpClient,
  })  : assert(apiKey != '', 'apiKey is required'),
        _apiKey = apiKey,
        _baseUrl = baseUrl.replaceAll(RegExp(r'/$'), ''),
        _maxRetries = maxRetries,
        _httpClient = httpClient ?? http.Client() {
    leads = LeadsResource(this);
    deals = DealsResource(this);
    pipeline = PipelineResource(this);
    channels = ChannelsResource(this);
    autopilot = AutopilotResource(this);
    salesAgent = SalesAgentResource(this);
    campaigns = CampaignsResource(this);
    contacts = ContactsResource(this);
    conversations = ConversationsResource(this);
    workspaces = WorkspacesResource(this);
    settings = SettingsResource(this);
    ads = AdsResource(this);
    campaignTemplates = CampaignTemplatesResource(this);
    deliverability = DeliverabilityResource(this);
    notifications = NotificationsResource(this);
    webhooks = WebhooksResource(this);
  }

  void close() => _httpClient.close();

  Map<String, String> _headers({String accept = 'application/json'}) => {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
        'Accept': accept,
        'User-Agent': 'misar-reach-dart/1.0.0',
      };

  Uri _uri(String path, [Map<String, dynamic>? queryParams]) {
    var uri = Uri.parse('$_baseUrl$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(
        queryParameters:
            queryParams.map((k, v) => MapEntry(k, v.toString())),
      );
    }
    return uri;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParams,
  }) async {
    final uri = _uri(path, queryParams);
    final headers = _headers();

    int attempt = 0;
    while (true) {
      try {
        http.Response response;
        final encoded = body != null ? jsonEncode(body) : null;
        switch (method.toUpperCase()) {
          case 'GET':
            response = await _httpClient.get(uri, headers: headers);
            break;
          case 'POST':
            response =
                await _httpClient.post(uri, headers: headers, body: encoded);
            break;
          case 'PATCH':
            response =
                await _httpClient.patch(uri, headers: headers, body: encoded);
            break;
          case 'PUT':
            response =
                await _httpClient.put(uri, headers: headers, body: encoded);
            break;
          case 'DELETE':
            response =
                await _httpClient.delete(uri, headers: headers, body: encoded);
            break;
          default:
            throw MisarReachError(0, 'Unsupported HTTP method: $method');
        }

        final status = response.statusCode;

        if (status >= 200 && status < 300) {
          if (response.body.isEmpty) return {};
          final decoded = jsonDecode(response.body);
          return decoded is Map<String, dynamic> ? decoded : {'data': decoded};
        }

        if (_retryable.contains(status) && attempt < _maxRetries - 1) {
          await Future<void>.delayed(_backoff(response, attempt));
          attempt++;
          continue;
        }

        throw _errorFor(status, response.body,
            retryAfterHeader: response.headers['retry-after']);
      } on MisarReachError {
        rethrow;
      } on SocketException catch (e) {
        throw MisarReachNetworkError(e.message);
      } on http.ClientException catch (e) {
        if (attempt < _maxRetries - 1) {
          await Future<void>.delayed(
              Duration(milliseconds: 300 * (1 << attempt)));
          attempt++;
          continue;
        }
        throw MisarReachNetworkError(e.message);
      }
    }
  }

  /// Opens a Server-Sent Events stream and yields each parsed [ReachSseEvent].
  ///
  /// The stream completes when the server closes the connection.
  Stream<ReachSseEvent> _stream(String path) async* {
    final request = http.Request('GET', _uri(path))
      ..headers.addAll(_headers(accept: 'text/event-stream'));

    http.StreamedResponse response;
    try {
      response = await _httpClient.send(request);
    } on SocketException catch (e) {
      throw MisarReachNetworkError(e.message);
    } on http.ClientException catch (e) {
      throw MisarReachNetworkError(e.message);
    }

    if (response.statusCode >= 400) {
      final raw = await response.stream.bytesToString();
      throw _errorFor(response.statusCode, raw);
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    String? eventName;
    final dataLines = <String>[];

    ReachSseEvent? flush() {
      if (dataLines.isEmpty && eventName == null) return null;
      final payload = dataLines.join('\n');
      dynamic data = payload;
      if (payload.isNotEmpty) {
        try {
          data = jsonDecode(payload);
        } catch (_) {/* keep raw string */}
      } else {
        data = null;
      }
      final evt = ReachSseEvent(eventName, data);
      eventName = null;
      dataLines.clear();
      return evt;
    }

    await for (final line in lines) {
      if (line.isEmpty) {
        final evt = flush();
        if (evt != null) yield evt;
        continue;
      }
      if (line.startsWith(':')) continue; // comment / heartbeat
      if (line.startsWith('event:')) {
        eventName = line.substring(6).trimLeft();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
    final tail = flush();
    if (tail != null) yield tail;
  }

  Duration _backoff(http.Response response, int attempt) {
    final ra = response.headers['retry-after'];
    final secs = ra != null ? int.tryParse(ra) : null;
    if (secs != null && secs > 0) return Duration(seconds: secs);
    return Duration(milliseconds: 300 * (1 << attempt));
  }

  MisarReachError _errorFor(int status, String rawBody,
      {String? retryAfterHeader}) {
    Map<String, dynamic> h = {};
    try {
      final d = jsonDecode(rawBody);
      if (d is Map<String, dynamic>) h = d;
    } catch (_) {}

    final err = h['error'];
    final message = err is String
        ? err
        : (h['message'] as String?) ??
            (err != null ? err.toString() : (rawBody.isEmpty ? 'error' : rawBody));
    final retryAfter = (h['retryAfter'] as num?)?.toInt() ??
        (retryAfterHeader != null ? int.tryParse(retryAfterHeader) : null);

    switch (status) {
      case 401:
      case 403:
        return AuthError(status, message, body: h);
      case 404:
        return NotFoundError(message, body: h);
      case 429:
        if (h['upgrade'] == true) {
          return UpgradeRequiredError(message, body: h);
        }
        return RateLimitError(
          message,
          retryAfter: retryAfter,
          balance: h['balance'] as num?,
          freeRemaining: h['freeRemaining'] as num?,
          body: h,
        );
      default:
        return MisarReachError(status, message, code: h['code'] as String?, body: h);
    }
  }
}

// ---------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------

/// Lead Finder — discovery, enrichment, verification, scoring, lists,
/// saved searches, scoring rules, recommendations, and the SSE job stream.
class LeadsResource extends _Resource {
  const LeadsResource(super.client);

  Future<Map<String, dynamic>> account() =>
      _client._request('GET', '/lead-finder/account');
  Future<Map<String, dynamic>> config() =>
      _client._request('GET', '/lead-finder/config');
  Future<Map<String, dynamic>> list({Map<String, dynamic>? params}) =>
      _client._request('GET', '/lead-finder/leads', queryParams: params);

  Future<Map<String, dynamic>> search(Map<String, dynamic> data) =>
      _client._request('POST', '/lead-finder/search', body: data);
  Future<Map<String, dynamic>> discover(Map<String, dynamic> data) =>
      _client._request('POST', '/lead-finder/discover', body: data);
  Future<Map<String, dynamic>> enrich(Map<String, dynamic> data) =>
      _client._request('POST', '/lead-finder/enrich', body: data);
  Future<Map<String, dynamic>> verify(Map<String, dynamic> data) =>
      _client._request('POST', '/lead-finder/verify', body: data);
  Future<Map<String, dynamic>> score(Map<String, dynamic> data) =>
      _client._request('POST', '/lead-finder/score', body: data);

  Future<Map<String, dynamic>> export({Map<String, dynamic>? params}) =>
      _client._request('GET', '/lead-finder/export', queryParams: params);
  Future<Map<String, dynamic>> searchHistory({Map<String, dynamic>? params}) =>
      _client._request('GET', '/lead-finder/search-history', queryParams: params);
  Future<Map<String, dynamic>> recommendations({Map<String, dynamic>? params}) =>
      _client._request('GET', '/lead-finder/recommendations', queryParams: params);

  Future<Map<String, dynamic>> previewMessage(Map<String, dynamic> data) =>
      _client._request('POST', '/lead-finder/preview-message', body: data);
  Future<Map<String, dynamic>> sendToCampaign(Map<String, dynamic> data) =>
      _client._request('POST', '/lead-finder/send-to-campaign', body: data);
  Future<Map<String, dynamic>> addToSegment(Map<String, dynamic> data) =>
      _client._request('POST', '/lead-finder/add-to-segment', body: data);

  Future<Map<String, dynamic>> company(String domain) => _client._request(
      'GET', '/lead-finder/companies/${Uri.encodeComponent(domain)}');
  Future<Map<String, dynamic>> companyPeople(String domain,
          {Map<String, dynamic>? params}) =>
      _client._request(
          'GET', '/lead-finder/companies/${Uri.encodeComponent(domain)}/people',
          queryParams: params);

  // Lists
  Future<Map<String, dynamic>> lists({Map<String, dynamic>? params}) =>
      _client._request('GET', '/lead-finder/lists', queryParams: params);
  Future<Map<String, dynamic>> createList(Map<String, dynamic> data) =>
      _client._request('POST', '/lead-finder/lists', body: data);
  Future<Map<String, dynamic>> syncList(String listId,
          [Map<String, dynamic>? data]) =>
      _client._request('POST', '/lead-finder/lists/$listId/sync', body: data);

  // Saved searches
  Future<Map<String, dynamic>> savedSearches({Map<String, dynamic>? params}) =>
      _client._request('GET', '/lead-finder/saved-searches', queryParams: params);
  Future<Map<String, dynamic>> createSavedSearch(Map<String, dynamic> data) =>
      _client._request('POST', '/lead-finder/saved-searches', body: data);
  Future<Map<String, dynamic>> deleteSavedSearch(String id) =>
      _client._request('DELETE', '/lead-finder/saved-searches/$id');

  // Scoring rules
  Future<Map<String, dynamic>> scoringRules({Map<String, dynamic>? params}) =>
      _client._request('GET', '/lead-finder/scoring-rules', queryParams: params);
  Future<Map<String, dynamic>> createScoringRule(Map<String, dynamic> data) =>
      _client._request('POST', '/lead-finder/scoring-rules', body: data);
  Future<Map<String, dynamic>> updateScoringRule(
          String id, Map<String, dynamic> data) =>
      _client._request('PATCH', '/lead-finder/scoring-rules/$id', body: data);
  Future<Map<String, dynamic>> deleteScoringRule(String id) =>
      _client._request('DELETE', '/lead-finder/scoring-rules/$id');

  // Jobs
  Future<Map<String, dynamic>> job(String jobId) =>
      _client._request('GET', '/lead-finder/jobs/$jobId');
  Future<Map<String, dynamic>> jobFeedback(
          String jobId, Map<String, dynamic> data) =>
      _client._request('POST', '/lead-finder/jobs/$jobId/feedback', body: data);

  /// Live progress for a running lead-finder job via Server-Sent Events.
  Stream<ReachSseEvent> streamJob(String jobId) =>
      _client._stream('/lead-finder/jobs/$jobId/stream');
}

/// CRM deals.
class DealsResource extends _Resource {
  const DealsResource(super.client);
  Future<Map<String, dynamic>> list({Map<String, dynamic>? params}) =>
      _client._request('GET', '/deals', queryParams: params);
  Future<Map<String, dynamic>> create(Map<String, dynamic> data) =>
      _client._request('POST', '/deals', body: data);
  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> data) =>
      _client._request('PATCH', '/deals/$id', body: data);
  Future<Map<String, dynamic>> delete(String id) =>
      _client._request('DELETE', '/deals/$id');
  Future<Map<String, dynamic>> activity(String id,
          {Map<String, dynamic>? params}) =>
      _client._request('GET', '/deals/$id/activity', queryParams: params);
  Future<Map<String, dynamic>> suggestions(String id,
          {Map<String, dynamic>? params}) =>
      _client._request('GET', '/deals/$id/suggestions', queryParams: params);

  /// Apply one operation to many deals at once —
  /// `{'ids': [...], 'op': 'tag'|'untag'|'stage'|'delete', ...}`. Tag writes are
  /// applied atomically server-side, so concurrent callers cannot lose a tag.
  Future<Map<String, dynamic>> bulk(Map<String, dynamic> data) =>
      _client._request('POST', '/deals/bulk', body: data);
}

/// Pipeline board.
class PipelineResource extends _Resource {
  const PipelineResource(super.client);
  Future<Map<String, dynamic>> get({Map<String, dynamic>? params}) =>
      _client._request('GET', '/pipeline', queryParams: params);
  Future<Map<String, dynamic>> update(Map<String, dynamic> data) =>
      _client._request('POST', '/pipeline', body: data);
}

/// Multi-channel outreach connections.
class ChannelsResource extends _Resource {
  const ChannelsResource(super.client);
  Future<Map<String, dynamic>> status() =>
      _client._request('GET', '/channels/status');
  Future<Map<String, dynamic>> updateStatus(Map<String, dynamic> data) =>
      _client._request('PATCH', '/channels/status', body: data);
  Future<Map<String, dynamic>> optInLinks({Map<String, dynamic>? params}) =>
      _client._request('GET', '/channels/opt-in-links', queryParams: params);
  Future<Map<String, dynamic>> connectSms(Map<String, dynamic> data) =>
      _client._request('POST', '/channels/sms/connect', body: data);
  Future<Map<String, dynamic>> connectWhatsapp(Map<String, dynamic> data) =>
      _client._request('POST', '/channels/whatsapp/connect', body: data);
  Future<Map<String, dynamic>> connectTelegram(Map<String, dynamic> data) =>
      _client._request('POST', '/channels/telegram/connect', body: data);
  Future<Map<String, dynamic>> connectTwitter(Map<String, dynamic> data) =>
      _client._request('POST', '/channels/twitter/connect', body: data);
  Future<Map<String, dynamic>> connectInstagram(Map<String, dynamic> data) =>
      _client._request('POST', '/channels/instagram/connect', body: data);
  Future<Map<String, dynamic>> connectFacebook(Map<String, dynamic> data) =>
      _client._request('POST', '/channels/facebook/connect', body: data);
  Future<Map<String, dynamic>> connectDiscord(Map<String, dynamic> data) =>
      _client._request('POST', '/channels/discord/connect', body: data);
  Future<Map<String, dynamic>> subscribePush(Map<String, dynamic> data) =>
      _client._request('POST', '/channels/push/subscribe', body: data);
  Future<Map<String, dynamic>> unsubscribePush() =>
      _client._request('DELETE', '/channels/push/subscribe');
}

/// Autopilot runs.
class AutopilotResource extends _Resource {
  const AutopilotResource(super.client);
  Future<Map<String, dynamic>> start(Map<String, dynamic> data) =>
      _client._request('POST', '/autopilot/start', body: data);
  Future<Map<String, dynamic>> runs({Map<String, dynamic>? params}) =>
      _client._request('GET', '/autopilot/runs', queryParams: params);
  Future<Map<String, dynamic>> get(String id) =>
      _client._request('GET', '/autopilot/$id');
  Future<Map<String, dynamic>> status(String id) =>
      _client._request('GET', '/autopilot/$id/status');
  Future<Map<String, dynamic>> setStatus(String id, Map<String, dynamic> data) =>
      _client._request('POST', '/autopilot/$id/status', body: data);
}

/// AI sales agent.
class SalesAgentResource extends _Resource {
  const SalesAgentResource(super.client);
  Future<Map<String, dynamic>> config() =>
      _client._request('GET', '/sales-agent/config');
  Future<Map<String, dynamic>> updateConfig(Map<String, dynamic> data) =>
      _client._request('PATCH', '/sales-agent/config', body: data);
  Future<Map<String, dynamic>> actions({Map<String, dynamic>? params}) =>
      _client._request('GET', '/sales-agent/actions', queryParams: params);
  Future<Map<String, dynamic>> conversations({Map<String, dynamic>? params}) =>
      _client._request('GET', '/sales-agent/conversations', queryParams: params);
  Future<Map<String, dynamic>> process(Map<String, dynamic> data) =>
      _client._request('POST', '/sales-agent/process', body: data);
}

/// Outreach campaigns.
class CampaignsResource extends _Resource {
  const CampaignsResource(super.client);
  Future<Map<String, dynamic>> list({Map<String, dynamic>? params}) =>
      _client._request('GET', '/campaigns', queryParams: params);
  Future<Map<String, dynamic>> create(Map<String, dynamic> data) =>
      _client._request('POST', '/campaigns', body: data);
  Future<Map<String, dynamic>> get(String id) =>
      _client._request('GET', '/campaigns/$id');
  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> data) =>
      _client._request('PATCH', '/campaigns/$id', body: data);
  Future<Map<String, dynamic>> delete(String id) =>
      _client._request('DELETE', '/campaigns/$id');
  Future<Map<String, dynamic>> enqueue(String id,
          [Map<String, dynamic>? data]) =>
      _client._request('POST', '/campaigns/$id/enqueue', body: data);
}

/// Contacts and segments.
class ContactsResource extends _Resource {
  const ContactsResource(super.client);
  Future<Map<String, dynamic>> list({Map<String, dynamic>? params}) =>
      _client._request('GET', '/contacts', queryParams: params);
  Future<Map<String, dynamic>> create(Map<String, dynamic> data) =>
      _client._request('POST', '/contacts', body: data);
  Future<Map<String, dynamic>> get(String id) =>
      _client._request('GET', '/contacts/$id');
  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> data) =>
      _client._request('PATCH', '/contacts/$id', body: data);
  Future<Map<String, dynamic>> delete(String id) =>
      _client._request('DELETE', '/contacts/$id');
  Future<Map<String, dynamic>> bulk(Map<String, dynamic> data) =>
      _client._request('POST', '/contacts/bulk', body: data);
  Future<Map<String, dynamic>> importContacts(Map<String, dynamic> data) =>
      _client._request('POST', '/contacts/import', body: data);
  Future<Map<String, dynamic>> segments({Map<String, dynamic>? params}) =>
      _client._request('GET', '/contacts/segments', queryParams: params);
  Future<Map<String, dynamic>> stats({Map<String, dynamic>? params}) =>
      _client._request('GET', '/contacts/stats', queryParams: params);
}

/// Unified conversation timeline.
class ConversationsResource extends _Resource {
  const ConversationsResource(super.client);
  Future<Map<String, dynamic>> list({Map<String, dynamic>? params}) =>
      _client._request('GET', '/conversations', queryParams: params);
  Future<Map<String, dynamic>> get(String email) => _client._request(
      'GET', '/conversations/${Uri.encodeComponent(email)}');
  Future<Map<String, dynamic>> reply(String email, Map<String, dynamic> data) =>
      _client._request(
          'POST', '/conversations/${Uri.encodeComponent(email)}/reply',
          body: data);
}

/// Reusable campaign templates.
class CampaignTemplatesResource extends _Resource {
  const CampaignTemplatesResource(super.client);
  Future<Map<String, dynamic>> list({Map<String, dynamic>? params}) =>
      _client._request('GET', '/campaign-templates', queryParams: params);
  Future<Map<String, dynamic>> create(Map<String, dynamic> data) =>
      _client._request('POST', '/campaign-templates', body: data);
}

/// Sender health — bounce and complaint rates over a rolling window.
class DeliverabilityResource extends _Resource {
  const DeliverabilityResource(super.client);

  /// `bounceRate` and `complaintRate` are null when there is not enough volume
  /// to judge — which is not the same as zero.
  Future<Map<String, dynamic>> get({Map<String, dynamic>? params}) =>
      _client._request('GET', '/deliverability', queryParams: params);
}

/// In-app notifications.
class NotificationsResource extends _Resource {
  const NotificationsResource(super.client);
  Future<Map<String, dynamic>> list({Map<String, dynamic>? params}) =>
      _client._request('GET', '/notifications', queryParams: params);

  /// Mark notifications read. Pass `{'ids': [...]}` or `{'all': true}`.
  Future<Map<String, dynamic>> markRead(Map<String, dynamic> data) =>
      _client._request('PATCH', '/notifications', body: data);
}

/// Outbound webhook endpoints.
class WebhooksResource extends _Resource {
  const WebhooksResource(super.client);
  Future<Map<String, dynamic>> list() =>
      _client._request('GET', '/webhooks/endpoints');

  /// Register an endpoint. The response carries the signing secret exactly
  /// once — store it then; it is not retrievable afterwards.
  Future<Map<String, dynamic>> create(Map<String, dynamic> data) =>
      _client._request('POST', '/webhooks/endpoints', body: data);
}

/// Workspaces and membership.
class WorkspacesResource extends _Resource {
  const WorkspacesResource(super.client);
  Future<Map<String, dynamic>> list({Map<String, dynamic>? params}) =>
      _client._request('GET', '/workspaces', queryParams: params);
  Future<Map<String, dynamic>> create(Map<String, dynamic> data) =>
      _client._request('POST', '/workspaces', body: data);
  Future<Map<String, dynamic>> members(String id) =>
      _client._request('GET', '/workspaces/$id/members');
  Future<Map<String, dynamic>> addMember(String id, Map<String, dynamic> data) =>
      _client._request('POST', '/workspaces/$id/members', body: data);
  Future<Map<String, dynamic>> removeMember(String id) =>
      _client._request('DELETE', '/workspaces/$id/members');
}

/// Account settings.
class SettingsResource extends _Resource {
  const SettingsResource(super.client);
  Future<Map<String, dynamic>> senderAddress() =>
      _client._request('GET', '/settings/sender-address');
  Future<Map<String, dynamic>> setSenderAddress(Map<String, dynamic> data) =>
      _client._request('PUT', '/settings/sender-address', body: data);
}

/// Paid-ads audience sync.
class AdsResource extends _Resource {
  const AdsResource(super.client);
  Future<Map<String, dynamic>> linkedinCompanyAudience(
          Map<String, dynamic> data) =>
      _client._request('POST', '/ads/linkedin/company-audience', body: data);
}
