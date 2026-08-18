<?php

declare(strict_types=1);

namespace MisarReach;

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
