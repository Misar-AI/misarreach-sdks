<?php

declare(strict_types=1);

namespace MisarReach\Tests;

use MisarReach\ApiError;
use MisarReach\AuthError;
use MisarReach\Client;
use MisarReach\NotFoundError;
use MisarReach\RateLimitError;
use MisarReach\UpgradeRequiredError;
use PHPUnit\Framework\TestCase;

class ClientTest extends TestCase
{
    /**
     * Builds a client whose transport replays the given queue of stub responses.
     * Each stub: ['status' => int, 'body' => string|array].
     *
     * @param array<int, array{status:int, body:string|array}> $responses
     */
    private function makeClient(array $responses, ?array &$captured = null): Client
    {
        $captured = [];
        $i = 0;
        $transport = function (string $method, string $url, array $headers, ?string $body)
            use (&$responses, &$i, &$captured): array {
            $captured[] = ['method' => $method, 'url' => $url, 'headers' => $headers, 'body' => $body];
            $r = $responses[$i] ?? end($responses);
            $i++;
            $payload = is_array($r['body']) ? json_encode($r['body']) : $r['body'];
            return ['status' => $r['status'], 'body' => (string) $payload, 'errno' => 0, 'error' => ''];
        };

        return new Client('mrk_test_key', null, 3, 30, \Closure::fromCallable($transport));
    }

    public function testLeadsSearch(): void
    {
        $client = $this->makeClient([
            ['status' => 200, 'body' => ['jobId' => 'job_123', 'status' => 'running']],
        ], $captured);

        $result = $client->leads->search(['query' => 'saas founders', 'limit' => 25]);

        $this->assertSame('job_123', $result['jobId']);
        $this->assertSame('POST', $captured[0]['method']);
        $this->assertSame('https://api.misar.io/reach/api/lead-finder/search', $captured[0]['url']);
        $this->assertStringContainsString('Bearer mrk_test_key', implode(' ', $captured[0]['headers']));
    }

    public function testLeadsListBuildsQueryString(): void
    {
        $client = $this->makeClient([
            ['status' => 200, 'body' => ['data' => [], 'total' => 0]],
        ], $captured);

        $client->leads->list(['page' => 2, 'limit' => 50]);

        $this->assertStringContainsString('/lead-finder/leads?', $captured[0]['url']);
        $this->assertStringContainsString('page=2', $captured[0]['url']);
        $this->assertStringContainsString('limit=50', $captured[0]['url']);
    }

    public function testDealsCreate(): void
    {
        $client = $this->makeClient([
            ['status' => 201, 'body' => ['id' => 'deal_1', 'title' => 'Acme']],
        ], $captured);

        $result = $client->deals->create(['title' => 'Acme', 'value' => 5000]);

        $this->assertSame('deal_1', $result['id']);
        $this->assertSame('https://api.misar.io/reach/api/deals', $captured[0]['url']);
    }

    public function testChannelsStatus(): void
    {
        $client = $this->makeClient([
            ['status' => 200, 'body' => ['sms' => ['connected' => true]]],
        ], $captured);

        $result = $client->channels->status();

        $this->assertTrue($result['sms']['connected']);
        $this->assertSame('GET', $captured[0]['method']);
    }

    public function testAutopilotStart(): void
    {
        $client = $this->makeClient([
            ['status' => 200, 'body' => ['id' => 'run_1', 'status' => 'started']],
        ], $captured);

        $result = $client->autopilot->start(['campaignId' => 'camp_1']);

        $this->assertSame('run_1', $result['id']);
        $this->assertSame('https://api.misar.io/reach/api/autopilot/start', $captured[0]['url']);
    }

    public function testConversationsGetEncodesEmail(): void
    {
        $client = $this->makeClient([
            ['status' => 200, 'body' => ['messages' => []]],
        ], $captured);

        $client->conversations->get('jane@acme.com');

        $this->assertStringContainsString('/conversations/jane%40acme.com', $captured[0]['url']);
    }

    public function testError401ThrowsAuthError(): void
    {
        $this->expectException(AuthError::class);
        $this->expectExceptionCode(401);

        $client = $this->makeClient([
            ['status' => 401, 'body' => ['error' => 'Unauthorized']],
        ]);
        $client->leads->search(['query' => 'x']);
    }

    public function testError404ThrowsNotFoundError(): void
    {
        $this->expectException(NotFoundError::class);

        $client = $this->makeClient([
            ['status' => 404, 'body' => ['error' => 'not found']],
        ]);
        $client->deals->activity('missing');
    }

    public function testError429ThrowsRateLimitErrorWithFields(): void
    {
        $client = $this->makeClient([
            ['status' => 429, 'body' => ['error' => 'rate limited', 'balance' => 12.5, 'freeRemaining' => 3]],
        ]);

        try {
            $client->leads->enrich(['email' => 'a@b.com']);
            $this->fail('Expected RateLimitError');
        } catch (RateLimitError $e) {
            $this->assertSame(429, $e->status);
            $this->assertSame(12.5, $e->balance);
            $this->assertSame(3, $e->freeRemaining);
            $this->assertFalse($e->upgrade);
        }
    }

    public function testUpgradeRefusalOn429IsTypedAsARefusal(): void
    {
        // A body carrying `upgrade: true` is a plan refusal whatever the status.
        // 402 is what the server sends now; 429 is still accepted so an older
        // deployment is not mistaken for a plain rate limit, which a caller
        // would retry pointlessly.
        $client = $this->makeClient([
            ['status' => 429, 'body' => [
                'error'       => 'monthly lead searches used up',
                'upgrade'     => true,
                'feature'     => 'lead_searches',
                'limit'       => 50,
                'current'     => 50,
                'upgrade_url' => '/settings?tab=billing',
            ]],
        ]);

        try {
            $client->leads->score(['jobId' => 'j1']);
            $this->fail('Expected UpgradeRequiredError');
        } catch (UpgradeRequiredError $e) {
            $this->assertSame(429, $e->status);
            $this->assertSame('upgrade_required', $e->errorCode);
            $this->assertSame('lead_searches', $e->feature);
            $this->assertSame(50, $e->limit);
            $this->assertSame(50, $e->current);
            // The server sends it app-relative; the SDK resolves it.
            $this->assertSame('https://misarreach.com/settings?tab=billing', $e->upgradeUrl);
        }
    }

    public function testRetryOn503ThenSuccess(): void
    {
        $client = $this->makeClient([
            ['status' => 503, 'body' => ''],
            ['status' => 503, 'body' => ''],
            ['status' => 200, 'body' => ['ok' => true]],
        ], $captured);

        $result = $client->pipeline->get();

        $this->assertTrue($result['ok']);
        $this->assertCount(3, $captured);
    }

    public function testGenericErrorThrowsApiError(): void
    {
        $this->expectException(ApiError::class);

        $client = $this->makeClient([
            ['status' => 400, 'body' => ['error' => 'bad request']],
        ]);
        $client->contacts->create([]);
    }
}
