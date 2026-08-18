package io.misar.reach;

import org.junit.jupiter.api.Test;

import javax.net.ssl.SSLContext;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Flow;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for {@link MisarReachClient}.
 *
 * <p>The real {@link HttpClient} is replaced with a minimal stub that returns a
 * fixed status code and body without making any network calls.
 */
class MisarReachClientTest {

    // ── Stub HttpClient ─────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static HttpClient stubClient(int status, String body, Map<String, List<String>> headers) {
        return new HttpClient() {
            @Override
            public <T> HttpResponse<T> send(HttpRequest request, HttpResponse.BodyHandler<T> handler)
                    throws IOException, InterruptedException {
                return stubResponse(request, status, body, headers, handler);
            }

            @Override
            public <T> CompletableFuture<HttpResponse<T>> sendAsync(
                    HttpRequest request, HttpResponse.BodyHandler<T> handler) {
                throw new UnsupportedOperationException("not used in tests");
            }

            @Override
            public <T> CompletableFuture<HttpResponse<T>> sendAsync(
                    HttpRequest request, HttpResponse.BodyHandler<T> handler,
                    HttpResponse.PushPromiseHandler<T> pushHandler) {
                throw new UnsupportedOperationException("not used in tests");
            }

            @Override public SSLContext sslContext() {
                try { return SSLContext.getDefault(); } catch (Exception e) { throw new RuntimeException(e); }
            }
            @Override public javax.net.ssl.SSLParameters sslParameters() { return new javax.net.ssl.SSLParameters(); }
            @Override public Optional<java.net.ProxySelector> proxy() { return Optional.empty(); }
            @Override public HttpClient.Redirect followRedirects() { return Redirect.NORMAL; }
            @Override public Optional<java.net.Authenticator> authenticator() { return Optional.empty(); }
            @Override public HttpClient.Version version() { return Version.HTTP_1_1; }
            @Override public Optional<java.util.concurrent.Executor> executor() { return Optional.empty(); }
            @Override public Optional<java.net.CookieHandler> cookieHandler() { return Optional.empty(); }
            @Override public Optional<java.time.Duration> connectTimeout() { return Optional.empty(); }

            private <T> HttpResponse<T> stubResponse(HttpRequest req, int code, String responseBody,
                                                     Map<String, List<String>> responseHeaders,
                                                     HttpResponse.BodyHandler<T> handler) {
                java.net.http.HttpHeaders stubHeaders =
                        java.net.http.HttpHeaders.of(responseHeaders, (a, b) -> true);
                HttpResponse.ResponseInfo info = new HttpResponse.ResponseInfo() {
                    public int statusCode() { return code; }
                    public java.net.http.HttpHeaders headers() { return stubHeaders; }
                    public HttpClient.Version version() { return HttpClient.Version.HTTP_1_1; }
                };

                HttpResponse.BodySubscriber<T> subscriber = handler.apply(info);
                subscriber.onSubscribe(new Flow.Subscription() {
                    public void request(long n) {}
                    public void cancel() {}
                });
                if (responseBody != null && !responseBody.isEmpty()) {
                    byte[] bytes = responseBody.getBytes(java.nio.charset.StandardCharsets.UTF_8);
                    subscriber.onNext(List.of(ByteBuffer.wrap(bytes)));
                }
                subscriber.onComplete();

                T result = subscriber.getBody().toCompletableFuture().join();
                return new HttpResponse<>() {
                    public int statusCode() { return code; }
                    public HttpRequest request() { return req; }
                    public java.net.http.HttpHeaders headers() { return stubHeaders; }
                    public T body() { return result; }
                    public Optional<HttpResponse<T>> previousResponse() { return Optional.empty(); }
                    public URI uri() { return req.uri(); }
                    public HttpClient.Version version() { return HttpClient.Version.HTTP_1_1; }
                    public Optional<javax.net.ssl.SSLSession> sslSession() { return Optional.empty(); }
                };
            }
        };
    }

    private static MisarReachClient clientWith(int status, String body) {
        return clientWith(status, body, Map.of());
    }

    private static MisarReachClient clientWith(
            int status, String body, Map<String, List<String>> headers) {
        return new MisarReachClient.Builder("mrk_test")
                .maxRetries(1)
                .httpClient(stubClient(status, body, headers))
                .build();
    }

    private static Map<String, List<String>> contentType(String value) {
        return Map.of("content-type", List.of(value));
    }

    // ── Tests ───────────────────────────────────────────────────────────────────

    @Test
    void leadsSearch_returns200_parsedResponse() throws Exception {
        MisarReachClient client = clientWith(200, "{\"jobId\":\"job_1\",\"status\":\"queued\"}");
        Map<String, Object> result = client.leads.search(Map.of("query", "SaaS founders"));
        assertEquals("job_1", result.get("jobId"));
        assertEquals("queued", result.get("status"));
    }

    @Test
    void contactsList_returns200_parsedResponse() throws Exception {
        MisarReachClient client = clientWith(200, "{\"data\":[]}");
        Map<String, Object> result = client.contacts.list(Map.of("page", 1));
        assertTrue(result.containsKey("data"));
    }

    @Test
    void channelsStatus_returns200_parsedResponse() throws Exception {
        MisarReachClient client = clientWith(200, "{\"sms\":{\"connected\":true}}");
        Map<String, Object> result = client.channels.status();
        assertNotNull(result.get("sms"));
    }

    @Test
    void dealsCreate_returns201_parsedResponse() throws Exception {
        MisarReachClient client = clientWith(201, "{\"id\":\"deal_1\"}");
        Map<String, Object> result = client.deals.create(Map.of("title", "New deal"));
        assertEquals("deal_1", result.get("id"));
    }

    @Test
    void errorEnvelope_throwsWithStatusAndMessage() {
        MisarReachClient client = clientWith(401,
                "{\"error\":{\"code\":\"unauthorized\",\"message\":\"Invalid API key\"}}");
        MisarReachException ex = assertThrows(MisarReachException.class,
                () -> client.leads.search(Map.of("query", "x")));
        assertEquals(401, ex.getStatus());
        assertTrue(ex.getMessage().contains("Invalid API key"));
    }

    @Test
    void emptyBody_on200_returnsEmptyMap() throws Exception {
        MisarReachClient client = clientWith(200, "");
        Map<String, Object> result = client.contacts.list(Map.of());
        assertTrue(result.isEmpty());
    }

    @Test
    void builderRejectsBlankApiKey() {
        assertThrows(IllegalArgumentException.class,
                () -> new MisarReachClient.Builder("").build());
    }

    @Test
    void leadJobStream_parsesNamedFrames() throws Exception {
        // MisarReach names its events and sends `: keepalive` every 20s. It does
        // not send a [DONE] sentinel — the stream ends when the server closes it.
        String sse = "event: progress\ndata: {\"message\":\"searching\"}\n\n"
                + ": keepalive\n\n"
                + "event: found\ndata: {\"total\":12}\n\n"
                + "event: complete\ndata: {\"total_found\":12}\n\n";

        MisarReachClient client = clientWith(200, sse, contentType("text/event-stream"));
        List<MisarReachClient.SseEvent> events = new ArrayList<>();
        client.leads.stream("job_1", events::add);

        // The keepalive comment must not surface as an event.
        assertEquals(List.of("progress", "found", "complete"),
                events.stream().map(MisarReachClient.SseEvent::event).toList());
        assertEquals(12, events.get(1).data().get("total"));
    }

    @Test
    void leadJobStream_reportsAnAlreadyFinishedJob() throws Exception {
        // A finished job is answered with a JSON snapshot rather than a stream.
        // Parsed as SSE this yields nothing, so the caller could not tell a
        // finished job from a silent one.
        MisarReachClient client = clientWith(
                200,
                "{\"status\":\"done\",\"total_found\":42,\"error\":null}",
                contentType("application/json"));

        List<MisarReachClient.SseEvent> events = new ArrayList<>();
        client.leads.stream("job_done", events::add);

        assertEquals(1, events.size());
        assertEquals("complete", events.get(0).event());
        assertEquals(42, events.get(0).data().get("total_found"));
    }

    @Test
    void leadJobStream_reportsAFailedJobAsError() throws Exception {
        MisarReachClient client = clientWith(
                200,
                "{\"status\":\"failed\",\"error\":\"no sources reachable\"}",
                contentType("application/json"));

        List<MisarReachClient.SseEvent> events = new ArrayList<>();
        client.leads.stream("job_bad", events::add);

        assertEquals("error", events.get(0).event());
    }

    @Test
    void leadJobStream_refusalIsTyped() {
        MisarReachClient client = clientWith(
                402,
                "{\"error\":\"monthly lead searches used up\",\"upgrade\":true,"
                        + "\"feature\":\"lead_searches\",\"limit\":50,\"current\":50,"
                        + "\"upgrade_url\":\"/settings?tab=billing\"}",
                contentType("application/json"));

        // A plan refusal on the stream must raise the same typed error the JSON
        // helper raises, not a generic exception with a fixed message.
        UpgradeRequiredException ex = assertThrows(UpgradeRequiredException.class,
                () -> client.leads.stream("job_1", ev -> {
                    throw new AssertionError("no frame on a refusal");
                }));

        assertEquals(402, ex.getStatus());
        assertEquals("lead_searches", ex.getFeature());
        // getMessage() is formatted as "MisarReachException(402): <message>",
        // so the server's text is carried rather than replaced by a fixed string.
        assertTrue(ex.getMessage().contains("monthly lead searches used up"));
        // The server sends it app-relative; the SDK resolves it.
        assertEquals("https://misarreach.com/settings?tab=billing", ex.getUpgradeUrl());
    }
}
