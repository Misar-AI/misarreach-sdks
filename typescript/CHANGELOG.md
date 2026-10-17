# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `leadFinder.suggest(q)` — `GET /lead-finder/suggest`: completions for a search box while the user types. Type: `SearchSuggestions`.
- `CompanyBriefResponse.recent` — up to five recent public facts about the company (funding, launches, news, hiring), each with the pages it was read from; `[]` when none are available. Type: `CompanyRecentFact`.

### Changed

- Package metadata and README name the publisher exactly as "Misar.AI".

## [5.1.0] — 2026-10-05

### Added

- `leadFinder.revealCompanySite(domain)` — `GET /lead-finder/companies/:domain/site`: the contact emails, phone, social profiles and tech stack a company's own website publishes.
- `leadFinder.companyBrief(domain, person?)` — `POST /lead-finder/companies/:domain/brief`: an account brief from the company's homepage, plus an outreach message for a named person.
- `leadFinder.emailFormat(domain)` — `GET /public/email-formats/:domain`: the company's address format, learned only from verified-deliverable addresses.
- Types: `CompanySiteReveal`, `CompanyBriefParams`, `CompanyBrief`, `CompanyBriefResponse`, `EmailFormatSummary`, `EmailPatternShare`, `EmailVerifyStatus`.

### Fixed

- `VerifyEmailsResponse` now matches what the API returns: `status` (including `accept_all` for catch-all domains), `score`, `catch_all`, `pending` and `verified`. The `deliverable` field was never returned; it is kept as an optional, deprecated field so existing code still compiles.

## [5.0.3] — 2026-08-19

Republished so that every SDK, including the tag-versioned ones, ships through the same automated release pipeline. No API changes.

## [5.0.2] — 2026-08-19

Republished so that every SDK, including the tag-versioned ones, ships through the same automated release pipeline. No API changes.

## [5.0.1] — 2026-08-19

Republished so that every SDK, including the tag-versioned ones, ships through the same automated release pipeline. No API changes.

## [5.0.0] — 2026-08-19

One version across every SDK in every Misar product, replacing the drift between separately-numbered clients.

### Changed

- `conversations.reply()` now takes `message`, not `body`. The old signature could only ever produce a 422 — the route has always parsed `{message, conversationId?}` — so no working call is affected.

### Documentation

- Rewritten README: every resource and method is listed with the endpoint it calls, the examples are verified against the API contract, and package links are consistent across all SDKs.
- Manifest metadata filled in — homepage, repository, issue tracker, documentation and author.

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
