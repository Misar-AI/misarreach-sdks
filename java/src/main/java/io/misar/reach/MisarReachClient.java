package io.misar.reach;

import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.function.Consumer;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * MisarReach developer API client ({@code https://api.misar.io/reach/api}).
 *
 * <p>Authenticate with an {@code mrk_} API key. Every request performs up to
 * {@code maxRetries} attempts with exponential back-off (starting at 500 ms) on
 * retryable HTTP statuses (429, 500, 502, 503, 504). Each method has a
 * synchronous and an {@code *Async} ({@link CompletableFuture}) variant.
 *
 * <pre>{@code
 * MisarReachClient client = new MisarReachClient.Builder("mrk_...").build();
 * Map<String, Object> job = client.leads.search(Map.of("query", "SaaS founders"));
 * }</pre>
 */
public final class MisarReachClient {

    private static final Set<Integer> RETRYABLE = Set.of(429, 500, 502, 503, 504);
    private static final Duration CONNECT_TIMEOUT = Duration.ofSeconds(10);
    private static final Duration REQUEST_TIMEOUT = Duration.ofSeconds(30);

    private final String apiKey;
    private final String baseUrl;
    private final int maxRetries;
    private final HttpClient http;
    private final ObjectMapper mapper = new ObjectMapper();

    // ── resource accessors ────────────────────────────────────────────────────
    public final LeadsResource leads;
    public final DealsResource deals;
    public final PipelineResource pipeline;
    public final ChannelsResource channels;
    public final AutopilotResource autopilot;
    public final SalesAgentResource salesAgent;
    public final CampaignsResource campaigns;
    public final ContactsResource contacts;
    public final ConversationsResource conversations;
    public final WorkspacesResource workspaces;
    public final SettingsResource settings;
    public final AdsResource ads;
    public final CampaignTemplatesResource campaignTemplates;
    public final DeliverabilityResource deliverability;
    public final NotificationsResource notifications;
    public final WebhooksResource webhooks;

    private MisarReachClient(Builder b) {
        this.apiKey = b.apiKey;
        this.baseUrl = b.baseUrl.endsWith("/") ? b.baseUrl.substring(0, b.baseUrl.length() - 1) : b.baseUrl;
        this.maxRetries = b.maxRetries;
        this.http = b.httpClient != null ? b.httpClient
                : HttpClient.newBuilder().connectTimeout(CONNECT_TIMEOUT).build();

        this.leads = new LeadsResource();
        this.deals = new DealsResource();
        this.pipeline = new PipelineResource();
        this.channels = new ChannelsResource();
        this.autopilot = new AutopilotResource();
        this.salesAgent = new SalesAgentResource();
        this.campaigns = new CampaignsResource();
        this.contacts = new ContactsResource();
        this.conversations = new ConversationsResource();
        this.workspaces = new WorkspacesResource();
        this.settings = new SettingsResource();
        this.ads = new AdsResource();
        this.campaignTemplates = new CampaignTemplatesResource();
        this.deliverability = new DeliverabilityResource();
        this.notifications = new NotificationsResource();
        this.webhooks = new WebhooksResource();
    }

    // ── Builder ───────────────────────────────────────────────────────────────

    public static final class Builder {
        private final String apiKey;
        private String baseUrl = "https://api.misar.io/reach/api";
        private int maxRetries = 3;
        private HttpClient httpClient;

        public Builder(String apiKey) {
            if (apiKey == null || apiKey.isBlank()) throw new IllegalArgumentException("apiKey must not be blank");
            this.apiKey = apiKey;
        }

        public Builder baseUrl(String baseUrl) { this.baseUrl = baseUrl; return this; }
        public Builder maxRetries(int maxRetries) { this.maxRetries = maxRetries; return this; }
        public Builder httpClient(HttpClient httpClient) { this.httpClient = httpClient; return this; }
        public MisarReachClient build() { return new MisarReachClient(this); }
    }

    // ── Core HTTP ─────────────────────────────────────────────────────────────

    private String qs(Map<String, Object> params) {
        if (params == null || params.isEmpty()) return "";
        return "?" + params.entrySet().stream()
                .map(e -> enc(e.getKey()) + "=" + enc(String.valueOf(e.getValue())))
                .collect(Collectors.joining("&"));
    }

    private static String enc(String s) {
        return URLEncoder.encode(s, StandardCharsets.UTF_8);
    }

    @SuppressWarnings("unchecked")
    private String extractMessage(String responseBody) {
        if (responseBody == null || responseBody.isBlank()) return "error";
        try {
            Map<String, Object> parsed = mapper.readValue(responseBody, Map.class);
            Object error = parsed.get("error");
            if (error instanceof Map<?, ?> envelope) {
                Object msg = ((Map<String, Object>) envelope).get("message");
                if (msg != null) return String.valueOf(msg);
            }
            if (error instanceof String s) return s;
            Object message = parsed.get("message");
            if (message != null) return String.valueOf(message);
        } catch (Exception ignored) {
            // fall through
        }
        return responseBody;
    }

    @SuppressWarnings("unchecked")
    Map<String, Object> requestUrl(String method, String url, Object body) throws MisarReachException {
        String bodyStr;
        try {
            bodyStr = body != null ? mapper.writeValueAsString(body) : "{}";
        } catch (Exception e) {
            throw new MisarReachException(0, "Failed to serialize request body: " + e.getMessage(), e);
        }

        Exception last = null;
        for (int attempt = 0; attempt < maxRetries; attempt++) {
            if (attempt > 0) {
                try { Thread.sleep(500L * (1L << (attempt - 1))); }
                catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    throw new MisarReachException(0, "Interrupted during retry back-off", ie);
                }
            }

            HttpRequest.Builder rb = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .timeout(REQUEST_TIMEOUT)
                    .header("Authorization", "Bearer " + apiKey)
                    .header("Content-Type", "application/json")
                    .header("Accept", "application/json");

            HttpRequest.BodyPublisher bp = HttpRequest.BodyPublishers.ofString(bodyStr);
            switch (method) {
                case "GET"    -> rb.GET();
                case "POST"   -> rb.POST(bp);
                case "PATCH"  -> rb.method("PATCH", bp);
                case "PUT"    -> rb.PUT(bp);
                case "DELETE" -> { if (body != null) rb.method("DELETE", bp); else rb.DELETE(); }
                default -> throw new IllegalArgumentException("Unsupported HTTP method: " + method);
            }

            HttpResponse<String> resp;
            try {
                resp = http.send(rb.build(), HttpResponse.BodyHandlers.ofString());
            } catch (IOException | InterruptedException e) {
                if (e instanceof InterruptedException) Thread.currentThread().interrupt();
                last = e;
                continue;
            }

            int status = resp.statusCode();
            if (RETRYABLE.contains(status) && attempt < maxRetries - 1) {
                last = new MisarReachException(status, resp.body());
                continue;
            }
            if (status >= 200 && status < 300) {
                String rb2 = resp.body();
                if (rb2 == null || rb2.isBlank()) return new HashMap<>();
                try { return mapper.readValue(rb2, Map.class); }
                catch (Exception e) { throw new MisarReachException(0, "Failed to parse response: " + e.getMessage(), e); }
            }
            throw new MisarReachException(status, extractMessage(resp.body()));
        }
        String cause = last != null ? last.getMessage() : "unknown";
        throw new MisarReachException(0, "Max retries exceeded: " + cause, last);
    }

    Map<String, Object> req(String method, String path, Object body) throws MisarReachException {
        return requestUrl(method, baseUrl + path, body);
    }

    private CompletableFuture<Map<String, Object>> async(String method, String path, Object body) {
        return CompletableFuture.supplyAsync(() -> {
            try { return req(method, path, body); }
            catch (MisarReachException e) { throw new CompletionException(e); }
        });
    }

    /**
     * Open a Server-Sent Events stream and invoke {@code onEvent} for every JSON
     * {@code data:} frame until the stream closes or a {@code [DONE]} sentinel
     * arrives. Blocks the calling thread for the lifetime of the stream.
     */
    void stream(String path, Consumer<Map<String, Object>> onEvent) throws MisarReachException {
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(baseUrl + path))
                .header("Authorization", "Bearer " + apiKey)
                .header("Accept", "text/event-stream")
                .GET()
                .build();
        try {
            HttpResponse<Stream<String>> resp = http.send(request, HttpResponse.BodyHandlers.ofLines());
            int status = resp.statusCode();
            if (status < 200 || status >= 300) {
                throw new MisarReachException(status, "stream request failed");
            }
            try (Stream<String> lines = resp.body()) {
                lines.forEach(line -> {
                    if (line == null) return;
                    String trimmed = line.strip();
                    if (!trimmed.startsWith("data:")) return;
                    String data = trimmed.substring("data:".length()).strip();
                    if (data.isEmpty() || data.equals("[DONE]")) return;
                    try {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> event = mapper.readValue(data, Map.class);
                        onEvent.accept(event);
                    } catch (Exception ignored) {
                        // skip malformed frame
                    }
                });
            }
        } catch (IOException | InterruptedException e) {
            if (e instanceof InterruptedException) Thread.currentThread().interrupt();
            throw new MisarReachException(0, "stream failed: " + e.getMessage(), e);
        }
    }

    // ── Resource: Lead Finder ──────────────────────────────────────────────────

    /** Lead Finder — search, discover, enrich, verify, score, lists, saved searches, scoring rules, jobs. */
    public final class LeadsResource {
        public Map<String, Object> account() throws MisarReachException { return req("GET", "/lead-finder/account", null); }
        public Map<String, Object> config() throws MisarReachException { return req("GET", "/lead-finder/config", null); }
        public Map<String, Object> search(Map<String, Object> data) throws MisarReachException { return req("POST", "/lead-finder/search", data); }
        public Map<String, Object> discover(Map<String, Object> data) throws MisarReachException { return req("POST", "/lead-finder/discover", data); }
        public Map<String, Object> enrich(Map<String, Object> data) throws MisarReachException { return req("POST", "/lead-finder/enrich", data); }
        public Map<String, Object> verify(Map<String, Object> data) throws MisarReachException { return req("POST", "/lead-finder/verify", data); }
        public Map<String, Object> score(Map<String, Object> data) throws MisarReachException { return req("POST", "/lead-finder/score", data); }
        public Map<String, Object> leads(Map<String, Object> params) throws MisarReachException { return req("GET", "/lead-finder/leads" + qs(params), null); }
        public Map<String, Object> export(Map<String, Object> params) throws MisarReachException { return req("GET", "/lead-finder/export" + qs(params), null); }
        public Map<String, Object> recommendations(Map<String, Object> params) throws MisarReachException { return req("GET", "/lead-finder/recommendations" + qs(params), null); }
        public Map<String, Object> searchHistory(Map<String, Object> params) throws MisarReachException { return req("GET", "/lead-finder/search-history" + qs(params), null); }
        public Map<String, Object> previewMessage(Map<String, Object> data) throws MisarReachException { return req("POST", "/lead-finder/preview-message", data); }
        public Map<String, Object> sendToCampaign(Map<String, Object> data) throws MisarReachException { return req("POST", "/lead-finder/send-to-campaign", data); }
        public Map<String, Object> addToSegment(Map<String, Object> data) throws MisarReachException { return req("POST", "/lead-finder/add-to-segment", data); }

        public Map<String, Object> company(String domain) throws MisarReachException { return req("GET", "/lead-finder/companies/" + domain, null); }
        public Map<String, Object> companyPeople(String domain, Map<String, Object> params) throws MisarReachException { return req("GET", "/lead-finder/companies/" + domain + "/people" + qs(params), null); }

        public Map<String, Object> job(String jobId) throws MisarReachException { return req("GET", "/lead-finder/jobs/" + jobId, null); }
        public Map<String, Object> jobFeedback(String jobId, Map<String, Object> data) throws MisarReachException { return req("POST", "/lead-finder/jobs/" + jobId + "/feedback", data); }

        /** GET /lead-finder/jobs/{jobId}/stream — Server-Sent Events (blocking). */
        public void stream(String jobId, Consumer<Map<String, Object>> onEvent) throws MisarReachException {
            MisarReachClient.this.stream("/lead-finder/jobs/" + jobId + "/stream", onEvent);
        }

        public Map<String, Object> lists() throws MisarReachException { return req("GET", "/lead-finder/lists", null); }
        public Map<String, Object> createList(Map<String, Object> data) throws MisarReachException { return req("POST", "/lead-finder/lists", data); }
        public Map<String, Object> syncList(String listId, Map<String, Object> data) throws MisarReachException { return req("POST", "/lead-finder/lists/" + listId + "/sync", data); }

        public Map<String, Object> savedSearches() throws MisarReachException { return req("GET", "/lead-finder/saved-searches", null); }
        public Map<String, Object> createSavedSearch(Map<String, Object> data) throws MisarReachException { return req("POST", "/lead-finder/saved-searches", data); }
        public Map<String, Object> deleteSavedSearch(String id) throws MisarReachException { return req("DELETE", "/lead-finder/saved-searches/" + id, null); }

        public Map<String, Object> scoringRules() throws MisarReachException { return req("GET", "/lead-finder/scoring-rules", null); }
        public Map<String, Object> createScoringRule(Map<String, Object> data) throws MisarReachException { return req("POST", "/lead-finder/scoring-rules", data); }
        public Map<String, Object> updateScoringRule(String id, Map<String, Object> data) throws MisarReachException { return req("PATCH", "/lead-finder/scoring-rules/" + id, data); }
        public Map<String, Object> deleteScoringRule(String id) throws MisarReachException { return req("DELETE", "/lead-finder/scoring-rules/" + id, null); }

        // async variants (common)
        public CompletableFuture<Map<String, Object>> searchAsync(Map<String, Object> data) { return async("POST", "/lead-finder/search", data); }
        public CompletableFuture<Map<String, Object>> discoverAsync(Map<String, Object> data) { return async("POST", "/lead-finder/discover", data); }
        public CompletableFuture<Map<String, Object>> enrichAsync(Map<String, Object> data) { return async("POST", "/lead-finder/enrich", data); }
        public CompletableFuture<Map<String, Object>> verifyAsync(Map<String, Object> data) { return async("POST", "/lead-finder/verify", data); }
        public CompletableFuture<Map<String, Object>> scoreAsync(Map<String, Object> data) { return async("POST", "/lead-finder/score", data); }
        public CompletableFuture<Map<String, Object>> leadsAsync(Map<String, Object> params) { return async("GET", "/lead-finder/leads" + qs(params), null); }
    }

    // ── Resource: Deals ────────────────────────────────────────────────────────

    public final class DealsResource {
        public Map<String, Object> list(Map<String, Object> params) throws MisarReachException { return req("GET", "/deals" + qs(params), null); }
        public Map<String, Object> create(Map<String, Object> data) throws MisarReachException { return req("POST", "/deals", data); }
        public Map<String, Object> update(String id, Map<String, Object> data) throws MisarReachException { return req("PATCH", "/deals/" + id, data); }
        public Map<String, Object> delete(String id) throws MisarReachException { return req("DELETE", "/deals/" + id, null); }
        public Map<String, Object> activity(String id) throws MisarReachException { return req("GET", "/deals/" + id + "/activity", null); }
        public Map<String, Object> suggestions(String id) throws MisarReachException { return req("GET", "/deals/" + id + "/suggestions", null); }
        /**
         * Apply one operation to many deals at once —
         * {@code {"ids": [...], "op": "tag"|"untag"|"stage"|"delete", ...}}. Tag
         * writes are applied atomically server-side, so concurrent callers cannot
         * lose a tag.
         */
        public Map<String, Object> bulk(Map<String, Object> data) throws MisarReachException { return req("POST", "/deals/bulk", data); }

        public CompletableFuture<Map<String, Object>> listAsync(Map<String, Object> params) { return async("GET", "/deals" + qs(params), null); }
        public CompletableFuture<Map<String, Object>> createAsync(Map<String, Object> data) { return async("POST", "/deals", data); }
        public CompletableFuture<Map<String, Object>> updateAsync(String id, Map<String, Object> data) { return async("PATCH", "/deals/" + id, data); }
        public CompletableFuture<Map<String, Object>> deleteAsync(String id) { return async("DELETE", "/deals/" + id, null); }
    }

    // ── Resource: Pipeline ─────────────────────────────────────────────────────

    public final class PipelineResource {
        public Map<String, Object> get(Map<String, Object> params) throws MisarReachException { return req("GET", "/pipeline" + qs(params), null); }
        public Map<String, Object> create(Map<String, Object> data) throws MisarReachException { return req("POST", "/pipeline", data); }
        public CompletableFuture<Map<String, Object>> getAsync(Map<String, Object> params) { return async("GET", "/pipeline" + qs(params), null); }
        public CompletableFuture<Map<String, Object>> createAsync(Map<String, Object> data) { return async("POST", "/pipeline", data); }
    }

    // ── Resource: Channels ─────────────────────────────────────────────────────

    /** Multi-channel outreach connections + status + opt-in links. */
    public final class ChannelsResource {
        public Map<String, Object> status() throws MisarReachException { return req("GET", "/channels/status", null); }
        public Map<String, Object> updateStatus(Map<String, Object> data) throws MisarReachException { return req("PATCH", "/channels/status", data); }
        public Map<String, Object> optInLinks(Map<String, Object> params) throws MisarReachException { return req("GET", "/channels/opt-in-links" + qs(params), null); }
        public Map<String, Object> connectSms(Map<String, Object> data) throws MisarReachException { return req("POST", "/channels/sms/connect", data); }
        public Map<String, Object> connectWhatsapp(Map<String, Object> data) throws MisarReachException { return req("POST", "/channels/whatsapp/connect", data); }
        public Map<String, Object> connectTelegram(Map<String, Object> data) throws MisarReachException { return req("POST", "/channels/telegram/connect", data); }
        public Map<String, Object> connectTwitter(Map<String, Object> data) throws MisarReachException { return req("POST", "/channels/twitter/connect", data); }
        public Map<String, Object> connectInstagram(Map<String, Object> data) throws MisarReachException { return req("POST", "/channels/instagram/connect", data); }
        public Map<String, Object> connectFacebook(Map<String, Object> data) throws MisarReachException { return req("POST", "/channels/facebook/connect", data); }
        public Map<String, Object> connectDiscord(Map<String, Object> data) throws MisarReachException { return req("POST", "/channels/discord/connect", data); }
        public Map<String, Object> subscribePush(Map<String, Object> data) throws MisarReachException { return req("POST", "/channels/push/subscribe", data); }
        public Map<String, Object> unsubscribePush(Map<String, Object> data) throws MisarReachException { return req("DELETE", "/channels/push/subscribe", data); }
    }

    // ── Resource: Autopilot ────────────────────────────────────────────────────

    public final class AutopilotResource {
        public Map<String, Object> start(Map<String, Object> data) throws MisarReachException { return req("POST", "/autopilot/start", data); }
        public Map<String, Object> runs(Map<String, Object> params) throws MisarReachException { return req("GET", "/autopilot/runs" + qs(params), null); }
        public Map<String, Object> get(String id) throws MisarReachException { return req("GET", "/autopilot/" + id, null); }
        public Map<String, Object> status(String id) throws MisarReachException { return req("GET", "/autopilot/" + id + "/status", null); }
        public Map<String, Object> updateStatus(String id, Map<String, Object> data) throws MisarReachException { return req("POST", "/autopilot/" + id + "/status", data); }

        public CompletableFuture<Map<String, Object>> startAsync(Map<String, Object> data) { return async("POST", "/autopilot/start", data); }
        public CompletableFuture<Map<String, Object>> runsAsync(Map<String, Object> params) { return async("GET", "/autopilot/runs" + qs(params), null); }
    }

    // ── Resource: Sales Agent ──────────────────────────────────────────────────

    public final class SalesAgentResource {
        public Map<String, Object> config() throws MisarReachException { return req("GET", "/sales-agent/config", null); }
        public Map<String, Object> updateConfig(Map<String, Object> data) throws MisarReachException { return req("PATCH", "/sales-agent/config", data); }
        public Map<String, Object> actions(Map<String, Object> params) throws MisarReachException { return req("GET", "/sales-agent/actions" + qs(params), null); }
        public Map<String, Object> conversations(Map<String, Object> params) throws MisarReachException { return req("GET", "/sales-agent/conversations" + qs(params), null); }
        public Map<String, Object> process(Map<String, Object> data) throws MisarReachException { return req("POST", "/sales-agent/process", data); }

        public CompletableFuture<Map<String, Object>> processAsync(Map<String, Object> data) { return async("POST", "/sales-agent/process", data); }
    }

    // ── Resource: Campaigns ────────────────────────────────────────────────────

    public final class CampaignsResource {
        public Map<String, Object> list(Map<String, Object> params) throws MisarReachException { return req("GET", "/campaigns" + qs(params), null); }
        public Map<String, Object> create(Map<String, Object> data) throws MisarReachException { return req("POST", "/campaigns", data); }
        public Map<String, Object> get(String id) throws MisarReachException { return req("GET", "/campaigns/" + id, null); }
        public Map<String, Object> update(String id, Map<String, Object> data) throws MisarReachException { return req("PATCH", "/campaigns/" + id, data); }
        public Map<String, Object> delete(String id) throws MisarReachException { return req("DELETE", "/campaigns/" + id, null); }
        public Map<String, Object> enqueue(String id, Map<String, Object> data) throws MisarReachException { return req("POST", "/campaigns/" + id + "/enqueue", data); }

        public CompletableFuture<Map<String, Object>> listAsync(Map<String, Object> params) { return async("GET", "/campaigns" + qs(params), null); }
        public CompletableFuture<Map<String, Object>> createAsync(Map<String, Object> data) { return async("POST", "/campaigns", data); }
    }

    // ── Resource: Contacts ─────────────────────────────────────────────────────

    public final class ContactsResource {
        public Map<String, Object> list(Map<String, Object> params) throws MisarReachException { return req("GET", "/contacts" + qs(params), null); }
        public Map<String, Object> create(Map<String, Object> data) throws MisarReachException { return req("POST", "/contacts", data); }
        public Map<String, Object> get(String id) throws MisarReachException { return req("GET", "/contacts/" + id, null); }
        public Map<String, Object> update(String id, Map<String, Object> data) throws MisarReachException { return req("PATCH", "/contacts/" + id, data); }
        public Map<String, Object> delete(String id) throws MisarReachException { return req("DELETE", "/contacts/" + id, null); }
        public Map<String, Object> bulk(Map<String, Object> data) throws MisarReachException { return req("POST", "/contacts/bulk", data); }
        public Map<String, Object> importContacts(Map<String, Object> data) throws MisarReachException { return req("POST", "/contacts/import", data); }
        public Map<String, Object> segments(Map<String, Object> params) throws MisarReachException { return req("GET", "/contacts/segments" + qs(params), null); }
        public Map<String, Object> stats(Map<String, Object> params) throws MisarReachException { return req("GET", "/contacts/stats" + qs(params), null); }

        public CompletableFuture<Map<String, Object>> listAsync(Map<String, Object> params) { return async("GET", "/contacts" + qs(params), null); }
        public CompletableFuture<Map<String, Object>> createAsync(Map<String, Object> data) { return async("POST", "/contacts", data); }
        public CompletableFuture<Map<String, Object>> importContactsAsync(Map<String, Object> data) { return async("POST", "/contacts/import", data); }
    }

    // ── Resource: Conversations ────────────────────────────────────────────────

    public final class ConversationsResource {
        public Map<String, Object> list(Map<String, Object> params) throws MisarReachException { return req("GET", "/conversations" + qs(params), null); }
        public Map<String, Object> get(String email) throws MisarReachException { return req("GET", "/conversations/" + enc(email), null); }
        public Map<String, Object> reply(String email, Map<String, Object> data) throws MisarReachException { return req("POST", "/conversations/" + enc(email) + "/reply", data); }
        public CompletableFuture<Map<String, Object>> listAsync(Map<String, Object> params) { return async("GET", "/conversations" + qs(params), null); }
        public CompletableFuture<Map<String, Object>> replyAsync(String email, Map<String, Object> data) { return async("POST", "/conversations/" + enc(email) + "/reply", data); }
    }

    // ── Resource: Campaign templates ───────────────────────────────────────────

    public final class CampaignTemplatesResource {
        public Map<String, Object> list(Map<String, Object> params) throws MisarReachException { return req("GET", "/campaign-templates" + qs(params), null); }
        public Map<String, Object> create(Map<String, Object> data) throws MisarReachException { return req("POST", "/campaign-templates", data); }

        public CompletableFuture<Map<String, Object>> listAsync(Map<String, Object> params) { return async("GET", "/campaign-templates" + qs(params), null); }
        public CompletableFuture<Map<String, Object>> createAsync(Map<String, Object> data) { return async("POST", "/campaign-templates", data); }
    }

    // ── Resource: Deliverability ───────────────────────────────────────────────

    public final class DeliverabilityResource {
        /**
         * Sender health. {@code bounceRate} and {@code complaintRate} are null when
         * there is not enough volume to judge — which is not the same as zero.
         */
        public Map<String, Object> get(Map<String, Object> params) throws MisarReachException { return req("GET", "/deliverability" + qs(params), null); }

        public CompletableFuture<Map<String, Object>> getAsync(Map<String, Object> params) { return async("GET", "/deliverability" + qs(params), null); }
    }

    // ── Resource: Notifications ────────────────────────────────────────────────

    public final class NotificationsResource {
        public Map<String, Object> list(Map<String, Object> params) throws MisarReachException { return req("GET", "/notifications" + qs(params), null); }
        /** Mark notifications read. Pass {@code {"ids": [...]}} or {@code {"all": true}}. */
        public Map<String, Object> markRead(Map<String, Object> data) throws MisarReachException { return req("PATCH", "/notifications", data); }

        public CompletableFuture<Map<String, Object>> listAsync(Map<String, Object> params) { return async("GET", "/notifications" + qs(params), null); }
        public CompletableFuture<Map<String, Object>> markReadAsync(Map<String, Object> data) { return async("PATCH", "/notifications", data); }
    }

    // ── Resource: Webhooks ─────────────────────────────────────────────────────

    public final class WebhooksResource {
        public Map<String, Object> list() throws MisarReachException { return req("GET", "/webhooks/endpoints", null); }
        /**
         * Register an endpoint. The response carries the signing secret exactly
         * once — store it then; it is not retrievable afterwards.
         */
        public Map<String, Object> create(Map<String, Object> data) throws MisarReachException { return req("POST", "/webhooks/endpoints", data); }

        public CompletableFuture<Map<String, Object>> listAsync() { return async("GET", "/webhooks/endpoints", null); }
        public CompletableFuture<Map<String, Object>> createAsync(Map<String, Object> data) { return async("POST", "/webhooks/endpoints", data); }
    }

    // ── Resource: Workspaces ───────────────────────────────────────────────────

    public final class WorkspacesResource {
        public Map<String, Object> list(Map<String, Object> params) throws MisarReachException { return req("GET", "/workspaces" + qs(params), null); }
        public Map<String, Object> create(Map<String, Object> data) throws MisarReachException { return req("POST", "/workspaces", data); }
        public Map<String, Object> members(String id) throws MisarReachException { return req("GET", "/workspaces/" + id + "/members", null); }
        public Map<String, Object> addMember(String id, Map<String, Object> data) throws MisarReachException { return req("POST", "/workspaces/" + id + "/members", data); }
        public Map<String, Object> removeMember(String id, Map<String, Object> data) throws MisarReachException { return req("DELETE", "/workspaces/" + id + "/members", data); }

        public CompletableFuture<Map<String, Object>> listAsync(Map<String, Object> params) { return async("GET", "/workspaces" + qs(params), null); }
    }

    // ── Resource: Settings ─────────────────────────────────────────────────────

    public final class SettingsResource {
        public Map<String, Object> getSenderAddress() throws MisarReachException { return req("GET", "/settings/sender-address", null); }
        public Map<String, Object> setSenderAddress(Map<String, Object> data) throws MisarReachException { return req("PUT", "/settings/sender-address", data); }
    }

    // ── Resource: Ads ──────────────────────────────────────────────────────────

    public final class AdsResource {
        public Map<String, Object> linkedinCompanyAudience(Map<String, Object> data) throws MisarReachException { return req("POST", "/ads/linkedin/company-audience", data); }
    }
}
