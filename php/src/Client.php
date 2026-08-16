<?php

declare(strict_types=1);

namespace MisarReach;

// ── Resource: Lead Finder ─────────────────────────────────────────────────────

class LeadsResource
{
    public function __construct(private readonly Client $client) {}

    public function account(): array
    {
        return $this->client->request('GET', '/lead-finder/account');
    }

    public function config(): array
    {
        return $this->client->request('GET', '/lead-finder/config');
    }

    public function list(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/lead-finder/leads{$qs}");
    }

    public function export(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/lead-finder/export{$qs}");
    }

    public function search(array $data): array
    {
        return $this->client->request('POST', '/lead-finder/search', $data);
    }

    public function discoverCompanies(array $data): array
    {
        return $this->client->request('POST', '/lead-finder/discover', $data);
    }

    public function enrich(array $data): array
    {
        return $this->client->request('POST', '/lead-finder/enrich', $data);
    }

    public function verifyEmails(array $data): array
    {
        return $this->client->request('POST', '/lead-finder/verify', $data);
    }

    public function score(array $data): array
    {
        return $this->client->request('POST', '/lead-finder/score', $data);
    }

    public function jobStatus(string $jobId): array
    {
        return $this->client->request('GET', "/lead-finder/jobs/{$jobId}");
    }

    public function submitFeedback(string $jobId, array $data): array
    {
        return $this->client->request('POST', "/lead-finder/jobs/{$jobId}/feedback", $data);
    }

    /**
     * GET /lead-finder/jobs/{jobId}/stream — Server-Sent Events live progress.
     * Invokes $onEvent(string $event, array $data, string $raw) for each event.
     */
    public function streamJob(string $jobId, callable $onEvent): void
    {
        $this->client->stream("/lead-finder/jobs/{$jobId}/stream", $onEvent);
    }

    public function listLeadLists(): array
    {
        return $this->client->request('GET', '/lead-finder/lists');
    }

    public function createLeadList(array $data): array
    {
        return $this->client->request('POST', '/lead-finder/lists', $data);
    }

    public function syncLeadList(string $listId, array $data = []): array
    {
        return $this->client->request('POST', "/lead-finder/lists/{$listId}/sync", $data);
    }

    public function savedSearches(): array
    {
        return $this->client->request('GET', '/lead-finder/saved-searches');
    }

    public function createSavedSearch(array $data): array
    {
        return $this->client->request('POST', '/lead-finder/saved-searches', $data);
    }

    public function deleteSavedSearch(string $id): array
    {
        return $this->client->request('DELETE', "/lead-finder/saved-searches/{$id}");
    }

    public function scoringRules(): array
    {
        return $this->client->request('GET', '/lead-finder/scoring-rules');
    }

    public function createScoringRule(array $data): array
    {
        return $this->client->request('POST', '/lead-finder/scoring-rules', $data);
    }

    public function updateScoringRule(string $id, array $data): array
    {
        return $this->client->request('PATCH', "/lead-finder/scoring-rules/{$id}", $data);
    }

    public function deleteScoringRule(string $id): array
    {
        return $this->client->request('DELETE', "/lead-finder/scoring-rules/{$id}");
    }

    public function recommendations(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/lead-finder/recommendations{$qs}");
    }

    public function searchHistory(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/lead-finder/search-history{$qs}");
    }

    public function previewMessage(array $data): array
    {
        return $this->client->request('POST', '/lead-finder/preview-message', $data);
    }

    public function sendToCampaign(array $data): array
    {
        return $this->client->request('POST', '/lead-finder/send-to-campaign', $data);
    }

    public function addToSegment(array $data): array
    {
        return $this->client->request('POST', '/lead-finder/add-to-segment', $data);
    }

    public function company(string $domain): array
    {
        return $this->client->request('GET', '/lead-finder/companies/' . rawurlencode($domain));
    }

    public function companyPeople(string $domain, array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', '/lead-finder/companies/' . rawurlencode($domain) . "/people{$qs}");
    }
}

// ── Resource: Ads ─────────────────────────────────────────────────────────────

class AdsResource
{
    public function __construct(private readonly Client $client) {}

    public function linkedinCompanyAudience(array $data): array
    {
        return $this->client->request('POST', '/ads/linkedin/company-audience', $data);
    }
}

// ── Resource: Autopilot ───────────────────────────────────────────────────────

class AutopilotResource
{
    public function __construct(private readonly Client $client) {}

    public function runs(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/autopilot/runs{$qs}");
    }

    public function start(array $data): array
    {
        return $this->client->request('POST', '/autopilot/start', $data);
    }

    public function get(string $id): array
    {
        return $this->client->request('GET', "/autopilot/{$id}");
    }

    public function status(string $id): array
    {
        return $this->client->request('GET', "/autopilot/{$id}/status");
    }

    public function setStatus(string $id, array $data): array
    {
        return $this->client->request('POST', "/autopilot/{$id}/status", $data);
    }
}

// ── Resource: Campaigns ───────────────────────────────────────────────────────

class CampaignsResource
{
    public function __construct(private readonly Client $client) {}

    public function list(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/campaigns{$qs}");
    }

    public function create(array $data): array
    {
        return $this->client->request('POST', '/campaigns', $data);
    }

    public function get(string $id): array
    {
        return $this->client->request('GET', "/campaigns/{$id}");
    }

    public function update(string $id, array $data): array
    {
        return $this->client->request('PATCH', "/campaigns/{$id}", $data);
    }

    public function delete(string $id): array
    {
        return $this->client->request('DELETE', "/campaigns/{$id}");
    }

    public function enqueue(string $id, array $data = []): array
    {
        return $this->client->request('POST', "/campaigns/{$id}/enqueue", $data);
    }
}

// ── Resource: Channels ────────────────────────────────────────────────────────

class ChannelsResource
{
    public function __construct(private readonly Client $client) {}

    public function status(): array
    {
        return $this->client->request('GET', '/channels/status');
    }

    public function updateStatus(array $data): array
    {
        return $this->client->request('PATCH', '/channels/status', $data);
    }

    public function optInLinks(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/channels/opt-in-links{$qs}");
    }

    public function connectSms(array $data): array
    {
        return $this->client->request('POST', '/channels/sms/connect', $data);
    }

    public function connectWhatsapp(array $data): array
    {
        return $this->client->request('POST', '/channels/whatsapp/connect', $data);
    }

    public function connectTelegram(array $data): array
    {
        return $this->client->request('POST', '/channels/telegram/connect', $data);
    }

    public function connectTwitter(array $data): array
    {
        return $this->client->request('POST', '/channels/twitter/connect', $data);
    }

    public function connectInstagram(array $data): array
    {
        return $this->client->request('POST', '/channels/instagram/connect', $data);
    }

    public function connectFacebook(array $data): array
    {
        return $this->client->request('POST', '/channels/facebook/connect', $data);
    }

    public function connectDiscord(array $data): array
    {
        return $this->client->request('POST', '/channels/discord/connect', $data);
    }

    public function subscribePush(array $data): array
    {
        return $this->client->request('POST', '/channels/push/subscribe', $data);
    }

    public function unsubscribePush(): array
    {
        return $this->client->request('DELETE', '/channels/push/subscribe');
    }
}

// ── Resource: Contacts ────────────────────────────────────────────────────────

class ContactsResource
{
    public function __construct(private readonly Client $client) {}

    public function list(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/contacts{$qs}");
    }

    public function create(array $data): array
    {
        return $this->client->request('POST', '/contacts', $data);
    }

    public function get(string $id): array
    {
        return $this->client->request('GET', "/contacts/{$id}");
    }

    public function update(string $id, array $data): array
    {
        return $this->client->request('PATCH', "/contacts/{$id}", $data);
    }

    public function delete(string $id): array
    {
        return $this->client->request('DELETE', "/contacts/{$id}");
    }

    public function bulk(array $data): array
    {
        return $this->client->request('POST', '/contacts/bulk', $data);
    }

    public function import(array $data): array
    {
        return $this->client->request('POST', '/contacts/import', $data);
    }

    public function segments(): array
    {
        return $this->client->request('GET', '/contacts/segments');
    }

    public function stats(): array
    {
        return $this->client->request('GET', '/contacts/stats');
    }
}

// ── Resource: Conversations ───────────────────────────────────────────────────

class ConversationsResource
{
    public function __construct(private readonly Client $client) {}

    public function list(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/conversations{$qs}");
    }

    public function get(string $email): array
    {
        return $this->client->request('GET', '/conversations/' . rawurlencode($email));
    }

    public function reply(string $email, array $data): array
    {
        return $this->client->request('POST', '/conversations/' . rawurlencode($email) . '/reply', $data);
    }
}

class CampaignTemplatesResource
{
    public function __construct(private readonly Client $client) {}

    public function list(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/campaign-templates{$qs}");
    }

    public function create(array $data): array
    {
        return $this->client->request('POST', '/campaign-templates', $data);
    }
}

class DeliverabilityResource
{
    public function __construct(private readonly Client $client) {}

    /**
     * Sender health. `bounceRate` and `complaintRate` are null when there is not
     * enough volume to judge — which is not the same as zero.
     */
    public function get(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/deliverability{$qs}");
    }
}

class NotificationsResource
{
    public function __construct(private readonly Client $client) {}

    public function list(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/notifications{$qs}");
    }

    /** Mark notifications read. Pass `['ids' => [...]]` or `['all' => true]`. */
    public function markRead(array $data): array
    {
        return $this->client->request('PATCH', '/notifications', $data);
    }
}

class WebhooksResource
{
    public function __construct(private readonly Client $client) {}

    public function list(): array
    {
        return $this->client->request('GET', '/webhooks/endpoints');
    }

    /**
     * Register an endpoint. The response carries the signing secret exactly
     * once — store it then; it is not retrievable afterwards.
     */
    public function create(array $data): array
    {
        return $this->client->request('POST', '/webhooks/endpoints', $data);
    }
}

// ── Resource: Deals ───────────────────────────────────────────────────────────

class DealsResource
{
    public function __construct(private readonly Client $client) {}

    public function list(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/deals{$qs}");
    }

    public function create(array $data): array
    {
        return $this->client->request('POST', '/deals', $data);
    }

    public function update(string $id, array $data): array
    {
        return $this->client->request('PATCH', "/deals/{$id}", $data);
    }

    public function delete(string $id): array
    {
        return $this->client->request('DELETE', "/deals/{$id}");
    }

    public function activity(string $id): array
    {
        return $this->client->request('GET', "/deals/{$id}/activity");
    }

    public function suggestions(string $id): array
    {
        return $this->client->request('GET', "/deals/{$id}/suggestions");
    }

    /**
     * Apply one operation to many deals at once —
     * `['ids' => [...], 'op' => 'tag'|'untag'|'stage'|'delete', ...]`. Tag writes
     * are applied atomically server-side, so concurrent callers cannot lose a tag.
     */
    public function bulk(array $data): array
    {
        return $this->client->request('POST', '/deals/bulk', $data);
    }
}

// ── Resource: Pipeline ────────────────────────────────────────────────────────

class PipelineResource
{
    public function __construct(private readonly Client $client) {}

    public function get(): array
    {
        return $this->client->request('GET', '/pipeline');
    }

    public function create(array $data): array
    {
        return $this->client->request('POST', '/pipeline', $data);
    }
}

// ── Resource: Sales Agent ─────────────────────────────────────────────────────

class SalesAgentResource
{
    public function __construct(private readonly Client $client) {}

    public function actions(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/sales-agent/actions{$qs}");
    }

    public function config(): array
    {
        return $this->client->request('GET', '/sales-agent/config');
    }

    public function updateConfig(array $data): array
    {
        return $this->client->request('PATCH', '/sales-agent/config', $data);
    }

    public function conversations(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/sales-agent/conversations{$qs}");
    }

    public function process(array $data): array
    {
        return $this->client->request('POST', '/sales-agent/process', $data);
    }
}

// ── Resource: Settings ────────────────────────────────────────────────────────

class SettingsResource
{
    public function __construct(private readonly Client $client) {}

    public function senderAddress(): array
    {
        return $this->client->request('GET', '/settings/sender-address');
    }

    public function setSenderAddress(array $data): array
    {
        return $this->client->request('PUT', '/settings/sender-address', $data);
    }
}

// ── Resource: Workspaces ──────────────────────────────────────────────────────

class WorkspacesResource
{
    public function __construct(private readonly Client $client) {}

    public function list(): array
    {
        return $this->client->request('GET', '/workspaces');
    }

    public function create(array $data): array
    {
        return $this->client->request('POST', '/workspaces', $data);
    }

    public function listMembers(string $id): array
    {
        return $this->client->request('GET', "/workspaces/{$id}/members");
    }

    public function addMember(string $id, array $data): array
    {
        return $this->client->request('POST', "/workspaces/{$id}/members", $data);
    }

    public function removeMember(string $id, array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('DELETE', "/workspaces/{$id}/members{$qs}");
    }
}

// ── Main Client ───────────────────────────────────────────────────────────────

/**
 * MisarReach API client — lead finder (23 sources), multi-channel outreach,
 * and CRM (deals, pipeline, sales agents).
 *
 * Authenticates with a `mrk_` API key (Bearer) against
 * https://api.misar.io/reach/api. Requests are retried up to MAX_RETRIES times with
 * exponential back-off on retryable statuses (429, 500, 502, 503, 504); the
 * final failure is surfaced as a typed {@see ApiError} subclass.
 */
class Client
{
    public readonly LeadsResource         $leads;
    public readonly AdsResource           $ads;
    public readonly AutopilotResource     $autopilot;
    public readonly CampaignsResource     $campaigns;
    public readonly ChannelsResource      $channels;
    public readonly ContactsResource      $contacts;
    public readonly ConversationsResource $conversations;
    public readonly DealsResource         $deals;
    public readonly PipelineResource      $pipeline;
    public readonly SalesAgentResource    $salesAgent;
    public readonly SettingsResource      $settings;
    public readonly WorkspacesResource    $workspaces;
    public readonly CampaignTemplatesResource $campaignTemplates;
    public readonly DeliverabilityResource    $deliverability;
    public readonly NotificationsResource     $notifications;
    public readonly WebhooksResource          $webhooks;

    private const DEFAULT_BASE_URL = 'https://api.misar.io/reach/api';
    private const RETRYABLE        = [429, 500, 502, 503, 504];
    private const RETRY_BASE_MS    = 500;

    private readonly string $baseUrl;

    /**
     * @param string        $apiKey    `mrk_` API key.
     * @param string|null   $baseUrl   Override the default base URL.
     * @param int           $maxRetries Retry attempts on transient failures.
     * @param int           $timeout   Per-request timeout in seconds.
     * @param \Closure|null $transport Optional transport override for testing.
     *        Signature: fn(string $method, string $url, array $headers, ?string $body): array
     *        returning ['status' => int, 'body' => string, 'errno' => int, 'error' => string].
     */
    public function __construct(
        private readonly string $apiKey,
        ?string $baseUrl = null,
        private readonly int $maxRetries = 3,
        private readonly int $timeout = 30,
        private readonly ?\Closure $transport = null,
    ) {
        $this->baseUrl       = rtrim($baseUrl ?? self::DEFAULT_BASE_URL, '/');
        $this->leads         = new LeadsResource($this);
        $this->ads           = new AdsResource($this);
        $this->autopilot     = new AutopilotResource($this);
        $this->campaigns     = new CampaignsResource($this);
        $this->channels      = new ChannelsResource($this);
        $this->contacts      = new ContactsResource($this);
        $this->conversations = new ConversationsResource($this);
        $this->deals         = new DealsResource($this);
        $this->pipeline      = new PipelineResource($this);
        $this->salesAgent    = new SalesAgentResource($this);
        $this->settings      = new SettingsResource($this);
        $this->workspaces    = new WorkspacesResource($this);
        $this->campaignTemplates = new CampaignTemplatesResource($this);
        $this->deliverability    = new DeliverabilityResource($this);
        $this->notifications     = new NotificationsResource($this);
        $this->webhooks          = new WebhooksResource($this);
    }

    /**
     * @throws ApiError
     * @throws NetworkError
     */
    public function request(string $method, string $path, array $data = []): array
    {
        $url      = $this->baseUrl . '/' . ltrim($path, '/');
        $hasBody  = !empty($data) && in_array($method, ['POST', 'PUT', 'PATCH'], true);
        $jsonBody = $hasBody ? json_encode($data, JSON_THROW_ON_ERROR) : null;

        $headers = [
            'Authorization: Bearer ' . $this->apiKey,
            'Content-Type: application/json',
            'Accept: application/json',
        ];

        $lastStatus = 0;

        for ($attempt = 0; $attempt < $this->maxRetries; $attempt++) {
            if ($attempt > 0) {
                usleep(self::RETRY_BASE_MS * (1 << ($attempt - 1)) * 1000);
            }

            $result = $this->send($method, $url, $headers, $jsonBody);

            if ($result['errno'] !== 0) {
                if ($attempt < $this->maxRetries - 1) {
                    continue;
                }
                throw new NetworkError("cURL error ({$result['errno']}): {$result['error']}");
            }

            $status     = $result['status'];
            $body       = $result['body'];
            $lastStatus = $status;

            if (in_array($status, self::RETRYABLE, true) && $attempt < $this->maxRetries - 1) {
                continue;
            }

            if ($status === 204 || $body === '' || $body === false) {
                return [];
            }

            $decoded = json_decode((string) $body, true);

            if ($status >= 400) {
                throw $this->mapError($status, is_array($decoded) ? $decoded : [], (string) $body);
            }

            return is_array($decoded) ? $decoded : [];
        }

        throw new ApiError('Max retries exceeded', $lastStatus);
    }

    /**
     * Executes a single HTTP request via the injected transport or cURL.
     *
     * @return array{status:int, body:string, errno:int, error:string}
     */
    private function send(string $method, string $url, array $headers, ?string $jsonBody): array
    {
        if ($this->transport !== null) {
            return ($this->transport)($method, $url, $headers, $jsonBody);
        }

        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL            => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER     => $headers,
            CURLOPT_CUSTOMREQUEST  => $method,
            CURLOPT_TIMEOUT        => $this->timeout,
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_FOLLOWLOCATION => false,
        ]);

        if ($jsonBody !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, $jsonBody);
        }

        $body  = curl_exec($ch);
        $errno = curl_errno($ch);
        $error = curl_error($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        return [
            'status' => $status,
            'body'   => $body === false ? '' : (string) $body,
            'errno'  => $errno,
            'error'  => $error,
        ];
    }

    /**
     * Maps a non-2xx response body into the appropriate {@see ApiError} subclass.
     */
    private function mapError(int $status, array $decoded, string $rawBody): ApiError
    {
        $message = $decoded['error'] ?? $decoded['message'] ?? ($rawBody !== '' ? $rawBody : "HTTP {$status}");

        return match (true) {
            $status === 401 || $status === 403 => new AuthError($message, $status),
            $status === 404                    => new NotFoundError($message),
            $status === 429                    => new RateLimitError(
                $message,
                isset($decoded['balance']) ? (float) $decoded['balance'] : null,
                isset($decoded['freeRemaining']) ? (int) $decoded['freeRemaining'] : null,
                (bool) ($decoded['upgrade'] ?? false),
            ),
            default => new ApiError($message, $status, $decoded['code'] ?? null),
        };
    }

    /**
     * Opens a Server-Sent Events stream and invokes $onEvent for each event
     * until the stream terminates. If the endpoint returns a plain JSON snapshot
     * (job already finished), a single synthetic `snapshot` event is delivered.
     *
     * @param callable(string $event, array $data, string $raw): void $onEvent
     * @throws NetworkError
     */
    public function stream(string $path, callable $onEvent): void
    {
        $url = $this->baseUrl . '/' . ltrim($path, '/');
        $headers = [
            'Authorization: Bearer ' . $this->apiKey,
            'Accept: text/event-stream',
        ];

        $eventName = 'message';
        $dataLines = [];
        $buffer    = '';
        $isStream  = null;

        $dispatch = function () use (&$eventName, &$dataLines, $onEvent): void {
            if ($dataLines === []) {
                $eventName = 'message';
                return;
            }
            $raw     = implode("\n", $dataLines);
            $decoded = json_decode($raw, true);
            $onEvent($eventName, is_array($decoded) ? $decoded : [], $raw);
            $eventName = 'message';
            $dataLines = [];
        };

        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL            => $url,
            CURLOPT_HTTPHEADER     => $headers,
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_TIMEOUT        => 0,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_WRITEFUNCTION  => function ($ch, string $chunk) use (
                &$buffer, &$eventName, &$dataLines, &$isStream, $ch, $dispatch, $onEvent
            ): int {
                if ($isStream === null) {
                    $ct = curl_getinfo($ch, CURLINFO_CONTENT_TYPE) ?: '';
                    $isStream = str_contains(strtolower($ct), 'text/event-stream');
                }
                $buffer .= $chunk;

                if ($isStream === false) {
                    return strlen($chunk); // accumulate; parsed as JSON snapshot at end
                }

                while (($nl = strpos($buffer, "\n")) !== false) {
                    $line   = rtrim(substr($buffer, 0, $nl), "\r");
                    $buffer = substr($buffer, $nl + 1);

                    if ($line === '') {
                        $dispatch();
                    } elseif ($line[0] === ':') {
                        continue;
                    } elseif (str_starts_with($line, 'event:')) {
                        $eventName = trim(substr($line, 6));
                    } elseif (str_starts_with($line, 'data:')) {
                        $dataLines[] = trim(substr($line, 5));
                    }
                }
                return strlen($chunk);
            },
        ]);

        $ok    = curl_exec($ch);
        $errno = curl_errno($ch);
        $error = curl_error($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($ok === false && $errno !== 0) {
            throw new NetworkError("cURL error ({$errno}): {$error}");
        }

        if ($status >= 400) {
            $decoded = json_decode($buffer, true);
            throw $this->mapError($status, is_array($decoded) ? $decoded : [], $buffer);
        }

        if ($isStream === false) {
            $decoded = json_decode($buffer, true);
            $onEvent('snapshot', is_array($decoded) ? $decoded : [], $buffer);
            return;
        }

        // Flush any trailing event not terminated by a blank line.
        $dispatch();
    }
}
