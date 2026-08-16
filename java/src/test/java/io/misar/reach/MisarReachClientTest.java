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
    private static HttpClient stubClient(int status, String body) {
        return new HttpClient() {
            @Override
            public <T> HttpResponse<T> send(HttpRequest request, HttpResponse.BodyHandler<T> handler)
                    throws IOException, InterruptedException {
                return stubResponse(request, status, body, handler);
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
                                                     HttpResponse.BodyHandler<T> handler) {
                HttpResponse.ResponseInfo info = new HttpResponse.ResponseInfo() {
                    public int statusCode() { return code; }
                    public java.net.http.HttpHeaders headers() {
                        return java.net.http.HttpHeaders.of(java.util.Map.of(), (a, b) -> true);
                    }
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
                    public java.net.http.HttpHeaders headers() {
                        return java.net.http.HttpHeaders.of(java.util.Map.of(), (a, b) -> true);
                    }
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
        return new MisarReachClient.Builder("mrk_test")
                .maxRetries(1)
                .httpClient(stubClient(status, body))
                .build();
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
    void leadJobStream_parsesSseFrames() throws Exception {
        String sse = "data: {\"status\":\"running\",\"progress\":10}\n"
                + "\n"
                + "data: {\"status\":\"running\",\"progress\":100}\n"
                + "\n"
                + "data: [DONE]\n";
        MisarReachClient client = clientWith(200, sse);
        List<Map<String, Object>> events = new ArrayList<>();
        client.leads.stream("job_1", events::add);
        assertEquals(2, events.size());
        assertEquals(10, events.get(0).get("progress"));
        assertEquals(100, events.get(1).get("progress"));
    }
}
