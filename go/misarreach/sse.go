package misarreach

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
)

// SSEEvent is a single Server-Sent Event from the lead-finder job stream.
// Data holds the decoded JSON payload (a map, or a string if not JSON).
type SSEEvent struct {
	Event string
	Data  interface{}
}

// SSEStream is an open Server-Sent Events connection. Range over Events() and
// then check Err(); always Close() when done.
type SSEStream struct {
	resp   *http.Response
	events chan SSEEvent
	err    error
}

// Events returns the channel of parsed events. It is closed when the stream ends.
func (s *SSEStream) Events() <-chan SSEEvent { return s.events }

// Err returns the first error encountered while reading the stream, if any.
func (s *SSEStream) Err() error { return s.err }

// Close terminates the underlying HTTP response body.
func (s *SSEStream) Close() error {
	if s.resp != nil && s.resp.Body != nil {
		return s.resp.Body.Close()
	}
	return nil
}

// streamJob opens the lead-finder job SSE stream. If the job is already
// finished the server returns a plain JSON snapshot, which is surfaced as a
// single "complete" event.
func (c *Client) streamJob(ctx context.Context, path string) (*SSEStream, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+path, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Accept", "text/event-stream")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, &NetworkError{Message: err.Error(), Cause: err}
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		raw, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		return nil, parseError(resp.StatusCode, raw)
	}

	s := &SSEStream{resp: resp, events: make(chan SSEEvent)}

	// A job that has already finished is answered with a JSON snapshot rather
	// than a stream. Report the terminal event the SSE path would have sent, so
	// a caller's switch works the same whether the job finished before or during
	// the call.
	if !strings.Contains(resp.Header.Get("Content-Type"), "text/event-stream") {
		raw, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		s.resp = nil
		go func() {
			defer close(s.events)
			var data interface{}
			if json.Unmarshal(raw, &data) != nil {
				data = string(raw)
			}
			event := "complete"
			if m, ok := data.(map[string]interface{}); ok && m["status"] == "failed" {
				event = "error"
			}
			s.events <- SSEEvent{Event: event, Data: data}
		}()
		return s, nil
	}

	go s.read()
	return s, nil
}

func (s *SSEStream) read() {
	defer close(s.events)
	defer s.resp.Body.Close()
	scanner := bufio.NewScanner(s.resp.Body)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	var event string
	var dataLines []string
	flush := func() {
		if len(dataLines) == 0 {
			event = ""
			return
		}
		raw := strings.Join(dataLines, "\n")
		var data interface{}
		if json.Unmarshal([]byte(raw), &data) != nil {
			data = raw
		}
		name := event
		if name == "" {
			name = "message"
		}
		s.events <- SSEEvent{Event: name, Data: data}
		event = ""
		dataLines = dataLines[:0]
	}
	for scanner.Scan() {
		line := scanner.Text()
		switch {
		case line == "":
			flush()
		case strings.HasPrefix(line, "event:"):
			event = strings.TrimSpace(line[len("event:"):])
		case strings.HasPrefix(line, "data:"):
			dataLines = append(dataLines, strings.TrimSpace(line[len("data:"):]))
		}
	}
	flush()
	if err := scanner.Err(); err != nil {
		s.err = err
	}
}
