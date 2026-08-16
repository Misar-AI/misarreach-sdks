package io.misar.reach

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import com.fasterxml.jackson.module.kotlin.readValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import java.net.URI
import java.net.URLEncoder
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.charset.StandardCharsets
import java.time.Duration

/**
 * MisarReach developer API client (`https://api.misar.io/reach/api`).
 *
 * Authenticate with an `mrk_` API key. Every suspend method performs up to
 * [maxRetries] attempts with exponential back-off (starting at 500 ms) on
 * retryable HTTP statuses (429, 500, 502, 503, 504).
 *
 * ```kotlin
 * val client = MisarReachClient("mrk_...")
 * val job = client.leads.search(mapOf("query" to "SaaS founders"))
 * client.leads.stream(job["jobId"] as String).collect { println(it) }
 * ```
 */
class MisarReachClient(
    private val apiKey: String,
    private val baseUrl: String = "https://api.misar.io/reach/api",
    private val maxRetries: Int = 3,
    httpClient: HttpClient? = null,
) {
    private val normalizedBase = baseUrl.trimEnd('/')

    private val http: HttpClient = httpClient ?: HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(10))
        .build()

    private val mapper = jacksonObjectMapper()

    // ── resource accessors ────────────────────────────────────────────────────
    val leads = LeadsResource()
    val deals = DealsResource()
    val pipeline = PipelineResource()
    val channels = ChannelsResource()
    val autopilot = AutopilotResource()
    val salesAgent = SalesAgentResource()
    val campaigns = CampaignsResource()
    val contacts = ContactsResource()
    val conversations = ConversationsResource()
    val workspaces = WorkspacesResource()
    val settings = SettingsResource()
    val ads = AdsResource()
    val campaignTemplates = CampaignTemplatesResource()
    val deliverability = DeliverabilityResource()
    val notifications = NotificationsResource()
    val webhooks = WebhooksResource()

    // ── Core HTTP ─────────────────────────────────────────────────────────────

    private fun Map<String, Any>.toQueryString(): String {
        if (isEmpty()) return ""
        return "?" + entries.joinToString("&") { (k, v) ->
            "${URLEncoder.encode(k, StandardCharsets.UTF_8)}=${URLEncoder.encode(v.toString(), StandardCharsets.UTF_8)}"
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun extractMessage(body: String?): String {
        if (body.isNullOrBlank()) return "error"
        return runCatching {
            val parsed = mapper.readValue<Map<String, Any>>(body)
            when (val err = parsed["error"]) {
                is Map<*, *> -> (err as Map<String, Any>)["message"]?.toString()
                is String -> err
                else -> null
            } ?: parsed["message"]?.toString()
        }.getOrNull() ?: body
    }

    private suspend fun requestUrl(method: String, url: String, body: Any? = null): Map<String, Any> {
        val bodyStr = if (body != null) mapper.writeValueAsString(body) else "{}"
        var lastException: Exception? = null

        repeat(maxRetries) { attempt ->
            if (attempt > 0) Thread.sleep(500L * (1L shl (attempt - 1)))

            val bodyPublisher = when (method) {
                "GET" -> HttpRequest.BodyPublishers.noBody()
                "DELETE" -> if (body != null) HttpRequest.BodyPublishers.ofString(bodyStr)
                            else HttpRequest.BodyPublishers.noBody()
                else -> HttpRequest.BodyPublishers.ofString(bodyStr)
            }

            val request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .timeout(Duration.ofSeconds(30))
                .header("Authorization", "Bearer $apiKey")
                .header("Content-Type", "application/json")
                .header("Accept", "application/json")
                .method(method, bodyPublisher)
                .build()

            val response: HttpResponse<String>
            try {
                response = http.send(request, HttpResponse.BodyHandlers.ofString())
            } catch (e: Exception) {
                lastException = MisarReachNetworkException(e.message ?: "network error")
                return@repeat
            }

            val status = response.statusCode()

            if (status in RETRYABLE && attempt < maxRetries - 1) {
                lastException = MisarReachException(status, response.body() ?: "retryable error")
                return@repeat
            }

            if (status in 200..299) {
                val rb = response.body()
                if (rb.isNullOrBlank()) return emptyMap()
                return mapper.readValue<Map<String, Any>>(rb)
            }

            throw MisarReachException(status, extractMessage(response.body()))
        }

        throw lastException ?: MisarReachNetworkException("max retries exceeded")
    }

    private suspend fun request(method: String, path: String, body: Any? = null): Map<String, Any> =
        requestUrl(method, "$normalizedBase$path", body)

    /**
     * Open a Server-Sent Events stream. Emits one map per JSON `data:` frame
     * until the stream closes or a `[DONE]` sentinel arrives.
     */
    private fun sse(path: String): Flow<Map<String, Any>> = flow {
        val request = HttpRequest.newBuilder()
            .uri(URI.create("$normalizedBase$path"))
            .header("Authorization", "Bearer $apiKey")
            .header("Accept", "text/event-stream")
            .GET()
            .build()

        val response = http.send(request, HttpResponse.BodyHandlers.ofLines())
        val status = response.statusCode()
        if (status !in 200..299) {
            throw MisarReachException(status, "stream request failed")
        }

        response.body().use { lines ->
            for (line in lines) {
                val trimmed = line?.trim() ?: continue
                if (!trimmed.startsWith("data:")) continue
                val data = trimmed.removePrefix("data:").trim()
                if (data.isEmpty()) continue
                if (data == "[DONE]") break
                runCatching { mapper.readValue<Map<String, Any>>(data) }
                    .getOrNull()
                    ?.let { emit(it) }
            }
        }
    }.flowOn(Dispatchers.IO)

    // ── Resource: Lead Finder ──────────────────────────────────────────────────

    /** Lead Finder — search, discover, enrich, verify, score, lists, saved searches, scoring rules, jobs. */
    inner class LeadsResource {
        suspend fun account(): Map<String, Any> = request("GET", "/lead-finder/account")
        suspend fun config(): Map<String, Any> = request("GET", "/lead-finder/config")
        suspend fun search(data: Map<String, Any>): Map<String, Any> = request("POST", "/lead-finder/search", data)
        suspend fun discover(data: Map<String, Any>): Map<String, Any> = request("POST", "/lead-finder/discover", data)
        suspend fun enrich(data: Map<String, Any>): Map<String, Any> = request("POST", "/lead-finder/enrich", data)
        suspend fun verify(data: Map<String, Any>): Map<String, Any> = request("POST", "/lead-finder/verify", data)
        suspend fun score(data: Map<String, Any>): Map<String, Any> = request("POST", "/lead-finder/score", data)
        suspend fun leads(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/lead-finder/leads${params.toQueryString()}")
        suspend fun export(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/lead-finder/export${params.toQueryString()}")
        suspend fun recommendations(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/lead-finder/recommendations${params.toQueryString()}")
        suspend fun searchHistory(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/lead-finder/search-history${params.toQueryString()}")
        suspend fun previewMessage(data: Map<String, Any>): Map<String, Any> = request("POST", "/lead-finder/preview-message", data)
        suspend fun sendToCampaign(data: Map<String, Any>): Map<String, Any> = request("POST", "/lead-finder/send-to-campaign", data)
        suspend fun addToSegment(data: Map<String, Any>): Map<String, Any> = request("POST", "/lead-finder/add-to-segment", data)

        suspend fun company(domain: String): Map<String, Any> = request("GET", "/lead-finder/companies/$domain")
        suspend fun companyPeople(domain: String, params: Map<String, Any> = emptyMap()): Map<String, Any> =
            request("GET", "/lead-finder/companies/$domain/people${params.toQueryString()}")

        suspend fun job(jobId: String): Map<String, Any> = request("GET", "/lead-finder/jobs/$jobId")
        suspend fun jobFeedback(jobId: String, data: Map<String, Any>): Map<String, Any> =
            request("POST", "/lead-finder/jobs/$jobId/feedback", data)

        /** GET /lead-finder/jobs/{jobId}/stream — Server-Sent Events as a [Flow]. */
        fun stream(jobId: String): Flow<Map<String, Any>> = sse("/lead-finder/jobs/$jobId/stream")

        suspend fun lists(): Map<String, Any> = request("GET", "/lead-finder/lists")
        suspend fun createList(data: Map<String, Any>): Map<String, Any> = request("POST", "/lead-finder/lists", data)
        suspend fun syncList(listId: String, data: Map<String, Any>): Map<String, Any> = request("POST", "/lead-finder/lists/$listId/sync", data)

        suspend fun savedSearches(): Map<String, Any> = request("GET", "/lead-finder/saved-searches")
        suspend fun createSavedSearch(data: Map<String, Any>): Map<String, Any> = request("POST", "/lead-finder/saved-searches", data)
        suspend fun deleteSavedSearch(id: String): Map<String, Any> = request("DELETE", "/lead-finder/saved-searches/$id")

        suspend fun scoringRules(): Map<String, Any> = request("GET", "/lead-finder/scoring-rules")
        suspend fun createScoringRule(data: Map<String, Any>): Map<String, Any> = request("POST", "/lead-finder/scoring-rules", data)
        suspend fun updateScoringRule(id: String, data: Map<String, Any>): Map<String, Any> = request("PATCH", "/lead-finder/scoring-rules/$id", data)
        suspend fun deleteScoringRule(id: String): Map<String, Any> = request("DELETE", "/lead-finder/scoring-rules/$id")
    }

    // ── Resource: Deals ────────────────────────────────────────────────────────

    inner class DealsResource {
        suspend fun list(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/deals${params.toQueryString()}")
        suspend fun create(data: Map<String, Any>): Map<String, Any> = request("POST", "/deals", data)
        suspend fun update(id: String, data: Map<String, Any>): Map<String, Any> = request("PATCH", "/deals/$id", data)
        suspend fun delete(id: String): Map<String, Any> = request("DELETE", "/deals/$id")
        suspend fun activity(id: String): Map<String, Any> = request("GET", "/deals/$id/activity")
        suspend fun suggestions(id: String): Map<String, Any> = request("GET", "/deals/$id/suggestions")

        /**
         * Apply one operation to many deals at once —
         * `{"ids": [...], "op": "tag"|"untag"|"stage"|"delete", ...}`. Tag writes
         * are applied atomically server-side, so concurrent callers cannot lose a tag.
         */
        suspend fun bulk(data: Map<String, Any>): Map<String, Any> = request("POST", "/deals/bulk", data)
    }

    // ── Resource: Pipeline ─────────────────────────────────────────────────────

    inner class PipelineResource {
        suspend fun get(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/pipeline${params.toQueryString()}")
        suspend fun create(data: Map<String, Any>): Map<String, Any> = request("POST", "/pipeline", data)
    }

    // ── Resource: Channels ─────────────────────────────────────────────────────

    /** Multi-channel outreach connections + status + opt-in links. */
    inner class ChannelsResource {
        suspend fun status(): Map<String, Any> = request("GET", "/channels/status")
        suspend fun updateStatus(data: Map<String, Any>): Map<String, Any> = request("PATCH", "/channels/status", data)
        suspend fun optInLinks(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/channels/opt-in-links${params.toQueryString()}")
        suspend fun connectSms(data: Map<String, Any>): Map<String, Any> = request("POST", "/channels/sms/connect", data)
        suspend fun connectWhatsapp(data: Map<String, Any>): Map<String, Any> = request("POST", "/channels/whatsapp/connect", data)
        suspend fun connectTelegram(data: Map<String, Any>): Map<String, Any> = request("POST", "/channels/telegram/connect", data)
        suspend fun connectTwitter(data: Map<String, Any>): Map<String, Any> = request("POST", "/channels/twitter/connect", data)
        suspend fun connectInstagram(data: Map<String, Any>): Map<String, Any> = request("POST", "/channels/instagram/connect", data)
        suspend fun connectFacebook(data: Map<String, Any>): Map<String, Any> = request("POST", "/channels/facebook/connect", data)
        suspend fun connectDiscord(data: Map<String, Any>): Map<String, Any> = request("POST", "/channels/discord/connect", data)
        suspend fun subscribePush(data: Map<String, Any>): Map<String, Any> = request("POST", "/channels/push/subscribe", data)
        suspend fun unsubscribePush(data: Map<String, Any>): Map<String, Any> = request("DELETE", "/channels/push/subscribe", data)
    }

    // ── Resource: Autopilot ────────────────────────────────────────────────────

    inner class AutopilotResource {
        suspend fun start(data: Map<String, Any>): Map<String, Any> = request("POST", "/autopilot/start", data)
        suspend fun runs(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/autopilot/runs${params.toQueryString()}")
        suspend fun get(id: String): Map<String, Any> = request("GET", "/autopilot/$id")
        suspend fun status(id: String): Map<String, Any> = request("GET", "/autopilot/$id/status")
        suspend fun updateStatus(id: String, data: Map<String, Any>): Map<String, Any> = request("POST", "/autopilot/$id/status", data)
    }

    // ── Resource: Sales Agent ──────────────────────────────────────────────────

    inner class SalesAgentResource {
        suspend fun config(): Map<String, Any> = request("GET", "/sales-agent/config")
        suspend fun updateConfig(data: Map<String, Any>): Map<String, Any> = request("PATCH", "/sales-agent/config", data)
        suspend fun actions(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/sales-agent/actions${params.toQueryString()}")
        suspend fun conversations(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/sales-agent/conversations${params.toQueryString()}")
        suspend fun process(data: Map<String, Any>): Map<String, Any> = request("POST", "/sales-agent/process", data)
    }

    // ── Resource: Campaigns ────────────────────────────────────────────────────

    inner class CampaignsResource {
        suspend fun list(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/campaigns${params.toQueryString()}")
        suspend fun create(data: Map<String, Any>): Map<String, Any> = request("POST", "/campaigns", data)
        suspend fun get(id: String): Map<String, Any> = request("GET", "/campaigns/$id")
        suspend fun update(id: String, data: Map<String, Any>): Map<String, Any> = request("PATCH", "/campaigns/$id", data)
        suspend fun delete(id: String): Map<String, Any> = request("DELETE", "/campaigns/$id")
        suspend fun enqueue(id: String, data: Map<String, Any>): Map<String, Any> = request("POST", "/campaigns/$id/enqueue", data)
    }

    // ── Resource: Contacts ─────────────────────────────────────────────────────

    inner class ContactsResource {
        suspend fun list(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/contacts${params.toQueryString()}")
        suspend fun create(data: Map<String, Any>): Map<String, Any> = request("POST", "/contacts", data)
        suspend fun get(id: String): Map<String, Any> = request("GET", "/contacts/$id")
        suspend fun update(id: String, data: Map<String, Any>): Map<String, Any> = request("PATCH", "/contacts/$id", data)
        suspend fun delete(id: String): Map<String, Any> = request("DELETE", "/contacts/$id")
        suspend fun bulk(data: Map<String, Any>): Map<String, Any> = request("POST", "/contacts/bulk", data)
        suspend fun importContacts(data: Map<String, Any>): Map<String, Any> = request("POST", "/contacts/import", data)
        suspend fun segments(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/contacts/segments${params.toQueryString()}")
        suspend fun stats(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/contacts/stats${params.toQueryString()}")
    }

    // ── Resource: Conversations ────────────────────────────────────────────────

    inner class ConversationsResource {
        suspend fun list(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/conversations${params.toQueryString()}")
        suspend fun get(email: String): Map<String, Any> =
            request("GET", "/conversations/${URLEncoder.encode(email, StandardCharsets.UTF_8)}")

        suspend fun reply(email: String, data: Map<String, Any>): Map<String, Any> =
            request("POST", "/conversations/${URLEncoder.encode(email, StandardCharsets.UTF_8)}/reply", data)
    }

    // ── Resource: Campaign templates ───────────────────────────────────────────

    inner class CampaignTemplatesResource {
        suspend fun list(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/campaign-templates${params.toQueryString()}")
        suspend fun create(data: Map<String, Any>): Map<String, Any> = request("POST", "/campaign-templates", data)
    }

    // ── Resource: Deliverability ───────────────────────────────────────────────

    inner class DeliverabilityResource {
        /**
         * Sender health. `bounceRate` and `complaintRate` are null when there is
         * not enough volume to judge — which is not the same as zero.
         */
        suspend fun get(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/deliverability${params.toQueryString()}")
    }

    // ── Resource: Notifications ────────────────────────────────────────────────

    inner class NotificationsResource {
        suspend fun list(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/notifications${params.toQueryString()}")

        /** Mark notifications read. Pass `{"ids": [...]}` or `{"all": true}`. */
        suspend fun markRead(data: Map<String, Any>): Map<String, Any> = request("PATCH", "/notifications", data)
    }

    // ── Resource: Webhooks ─────────────────────────────────────────────────────

    inner class WebhooksResource {
        suspend fun list(): Map<String, Any> = request("GET", "/webhooks/endpoints")

        /**
         * Register an endpoint. The response carries the signing secret exactly
         * once — store it then; it is not retrievable afterwards.
         */
        suspend fun create(data: Map<String, Any>): Map<String, Any> = request("POST", "/webhooks/endpoints", data)
    }

    // ── Resource: Workspaces ───────────────────────────────────────────────────

    inner class WorkspacesResource {
        suspend fun list(params: Map<String, Any> = emptyMap()): Map<String, Any> = request("GET", "/workspaces${params.toQueryString()}")
        suspend fun create(data: Map<String, Any>): Map<String, Any> = request("POST", "/workspaces", data)
        suspend fun members(id: String): Map<String, Any> = request("GET", "/workspaces/$id/members")
        suspend fun addMember(id: String, data: Map<String, Any>): Map<String, Any> = request("POST", "/workspaces/$id/members", data)
        suspend fun removeMember(id: String, data: Map<String, Any>): Map<String, Any> = request("DELETE", "/workspaces/$id/members", data)
    }

    // ── Resource: Settings ─────────────────────────────────────────────────────

    inner class SettingsResource {
        suspend fun getSenderAddress(): Map<String, Any> = request("GET", "/settings/sender-address")
        suspend fun setSenderAddress(data: Map<String, Any>): Map<String, Any> = request("PUT", "/settings/sender-address", data)
    }

    // ── Resource: Ads ──────────────────────────────────────────────────────────

    inner class AdsResource {
        suspend fun linkedinCompanyAudience(data: Map<String, Any>): Map<String, Any> =
            request("POST", "/ads/linkedin/company-audience", data)
    }

    companion object {
        private val RETRYABLE = setOf(429, 500, 502, 503, 504)
    }
}
