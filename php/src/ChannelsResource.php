<?php

declare(strict_types=1);

namespace MisarReach;

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
