<?php

declare(strict_types=1);

namespace MisarReach;

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
    public readonly PlanResource          $plan;
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
        $this->plan = new PlanResource($this);
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
    /**
     * The server returns upgrade_url app-relative (/settings?tab=billing);
     * resolve it against the app origin so callers can link to it.
     */
    private static function absoluteUpgradeUrl(?string $path): ?string
    {
        if ($path === null || $path === '') {
            return null;
        }
        if (str_starts_with($path, 'http://') || str_starts_with($path, 'https://')) {
            return $path;
        }

        return 'https://misarreach.com' . (str_starts_with($path, '/') ? $path : '/' . $path);
    }

    private function mapError(int $status, array $decoded, string $rawBody): ApiError
    {
        $message = $decoded['error'] ?? $decoded['message'] ?? ($rawBody !== '' ? $rawBody : "HTTP {$status}");

        // A counted cap answers 402 with `upgrade: true`. Only 429 was
        // inspected before, so every real refusal became a generic ApiError.
        if (($decoded['upgrade'] ?? false) === true && ($status === 402 || $status === 429)) {
            return new UpgradeRequiredError(
                $message,
                $status,
                isset($decoded['feature']) ? (string) $decoded['feature'] : null,
                isset($decoded['limit']) ? (int) $decoded['limit'] : null,
                isset($decoded['current']) ? (int) $decoded['current'] : null,
                self::absoluteUpgradeUrl($decoded['upgrade_url'] ?? null),
            );
        }

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
     * (job already finished), a single synthetic `complete` event is delivered —
     * or `error` when the job failed.
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
            CURLOPT_WRITEFUNCTION  => function ($handle, string $chunk) use (
                &$buffer, &$eventName, &$dataLines, &$isStream, $dispatch, $onEvent
            ): int {
                if ($isStream === null) {
                    $ct = curl_getinfo($handle, CURLINFO_CONTENT_TYPE) ?: '';
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
            // Report the terminal event the SSE path would have sent, rather
            // than a name the server never uses, so a caller's switch works the
            // same whether the job finished before or during the call.
            $snapshot = is_array($decoded) ? $decoded : [];
            $onEvent(
                ($snapshot['status'] ?? null) === 'failed' ? 'error' : 'complete',
                $snapshot,
                $buffer,
            );
            return;
        }

        // Flush any trailing event not terminated by a blank line.
        $dispatch();
    }
}
