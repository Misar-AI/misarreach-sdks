# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [5.0.2] — 2026-08-19

Republished so that every SDK, including the tag-versioned ones, ships through the same automated release pipeline. No API changes.

## [5.0.1] — 2026-08-19

Republished so that every SDK, including the tag-versioned ones, ships through the same automated release pipeline. No API changes.

## [5.0.0] — 2026-08-19

One version across every SDK in every Misar product, replacing the drift between separately-numbered clients.

### Documentation

- A campaign step is flat — `{channel, delay_hours, subject, body}`, ordered by its position in the array — and `conversations.reply` takes `message`. Earlier examples showed shapes the API rejects.
- Rewritten README: every resource and method is listed with the endpoint it calls, the examples are verified against the API contract, and package links are consistent across all SDKs.
- Manifest metadata filled in — homepage, repository, issue tracker, documentation and author.

### Fixed

- An error response with an empty body was reported as success. A bare 401, or any response stripped by a proxy, came back as an empty result instead of raising, so callers could not tell "no results" from "not authorised".

## [1.0.0] — 2026-08-17

First release.

### Added

- Full coverage of the MisarReach REST API, authenticated with a `mrk_` developer
  key sent as `Authorization: Bearer mrk_…`.
- Server-Sent Events for `GET /lead-finder/jobs/{id}/stream`, carrying the
  server's event name (`progress`, `found`, `complete`, `error`, `timeout`).
  A job that has already finished is answered with a JSON snapshot rather than
  a stream; that is reported as a single `complete` — or `error` when the job
  failed — so callers need no special case for it.
- `GET /plan` for reading the subscription's allowances and per-feature usage,
  so an expensive call can be checked before it is attempted rather than after
  it is refused.
- Retries with exponential back-off on genuinely transient statuses
  (429 rate limits, 500, 502, 503, 504).

### Notes

- Plan limits are enforced server-side against the subscription attached to the
  API key. A counted cap answers 402 with `upgrade: true` and names the
  exhausted counter. Surfaced as a distinct error type and never retried.
  Deliberately separate from the 503 `retry: true` the server sends when it
  could not *check* the quota — that one is retried, so "we don't know" is
  never mistaken for "you're over your limit".
- Streams are never retried: replaying one that failed mid-flight would
  duplicate whatever the caller had already consumed.

[1.0.0]: https://misarreach.com/docs
