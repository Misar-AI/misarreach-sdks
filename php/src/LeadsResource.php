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
