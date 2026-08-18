# MisarReach Go SDK

Official Go SDK for the [MisarReach](https://misarreach.com) Developer API —
lead finder (23 sources), multi-channel outreach, deals/pipeline CRM, autopilot,
and the AI sales agent.

Full reference: [`docs.misar.io/reach`](https://docs.misar.io/reach) · OpenAPI: `openapi/reach.openapi.json`.

## Install

```bash
go get github.com/Misar-AI/misarreach-sdks/go/misarreach
```

## Auth

Use a reach developer key (`mrk_…`). It is validated only against the
reach-owned key table, so a key from any other Misar product is rejected. Sent
as `Authorization: Bearer mrk_…`.

## Quick start

```go
package main

import (
	"context"
	"fmt"

	"github.com/Misar-AI/misarreach-sdks/go/misarreach"
)

func main() {
	c := misarreach.New("mrk_your_key")
	ctx := context.Background()

	// Start an async lead search
	res, err := c.Leads.Search(ctx, &misarreach.SearchLeadsRequest{
		Query: "SaaS founders in Berlin", UseAI: true,
	})
	if err != nil {
		panic(err)
	}
	jobID, _ := res["jobId"].(string)

	// Stream job progress via SSE
	stream, err := c.Leads.StreamJob(ctx, jobID)
	if err != nil {
		panic(err)
	}
	defer stream.Close()
	for e := range stream.Events() {
		fmt.Println(e.Event, e.Data) // progress … then complete / error
	}

	// CRM
	deal, _ := c.Deals.Create(ctx, &misarreach.CreateDealRequest{LeadEmail: "cto@acme.com", Value: 5000})
	c.Pipeline.Move(ctx, map[string]any{"dealId": deal["id"], "newStage": "interested"})

	// Channels
	c.Channels.Status(ctx)
	c.Channels.Connect(ctx, "whatsapp", map[string]any{"phoneNumberId": "…", "accessToken": "…"})
}
```

## Resources

`c.Leads` · `c.Deals` · `c.Pipeline` · `c.Channels` · `c.Autopilot` ·
`c.SalesAgent` · `c.Campaigns` · `c.Contacts` · `c.Conversations` ·
`c.Settings` · `c.Workspaces` · `c.Ads` — covering all 84 developer-API
operations across the 63 reach paths.

- GET/list methods take a `misarreach.Params` (`map[string]string`) query bag.
- POST/PATCH/PUT methods take a `body interface{}` — a typed request struct
  (`SearchLeadsRequest`, `CreateDealRequest`, `CreateCampaignRequest`,
  `ContactsBulkRequest`, `ContactsImportRequest`, …) or a plain `map[string]any`.
- Every method returns `misarreach.Response` (`map[string]interface{}`), matching
  the open-shape reach contract.
- `c.Leads.StreamJob(ctx, jobID)` returns an `*SSEStream`; range over
  `stream.Events()`, then check `stream.Err()`, and `stream.Close()`.

## Errors

Non-2xx responses return an `*APIError` (`Status`, `Message`, `Code`,
`RetryAfter`) with helpers `IsAuth()`, `IsNotFound()`, `IsRateLimit()`.
Transport failures return a `*NetworkError`. 429/5xx are retried with
exponential backoff (configurable via `WithMaxRetries`).

## License

MIT
