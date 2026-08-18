package io.misar.reach

import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.util.Optional
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Flow
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class MisarReachClientTest {

    // ── Stub HttpClient (no network) ────────────────────────────────────────────

    private fun stubClient(
        status: Int,
        body: String,
        headers: Map<String, List<String>> = emptyMap(),
    ): HttpClient = object : HttpClient() {
        override fun <T> send(request: HttpRequest, handler: HttpResponse.BodyHandler<T>): HttpResponse<T> {
            val stubHeaders = java.net.http.HttpHeaders.of(headers) { _, _ -> true }
            val info = object : HttpResponse.ResponseInfo {
                override fun statusCode() = status
                override fun headers() = stubHeaders
                override fun version() = Version.HTTP_1_1
            }
            val subscriber = handler.apply(info)
            subscriber.onSubscribe(object : Flow.Subscription {
                override fun request(n: Long) {}
                override fun cancel() {}
            })
            if (body.isNotEmpty()) {
                subscriber.onNext(listOf(ByteBuffer.wrap(body.toByteArray(StandardCharsets.UTF_8))))
            }
            subscriber.onComplete()
            val result: T = subscriber.body.toCompletableFuture().join()
            return object : HttpResponse<T> {
                override fun statusCode() = status
                override fun request() = request
                override fun headers() = stubHeaders
                override fun body(): T = result
                override fun previousResponse(): Optional<HttpResponse<T>> = Optional.empty()
                override fun uri(): URI = request.uri()
                override fun version() = Version.HTTP_1_1
                override fun sslSession(): Optional<javax.net.ssl.SSLSession> = Optional.empty()
            }
        }

        override fun <T> sendAsync(request: HttpRequest, handler: HttpResponse.BodyHandler<T>):
            CompletableFuture<HttpResponse<T>> = CompletableFuture.completedFuture(send(request, handler))

        override fun <T> sendAsync(
            request: HttpRequest,
            handler: HttpResponse.BodyHandler<T>,
            pushHandler: HttpResponse.PushPromiseHandler<T>?,
        ): CompletableFuture<HttpResponse<T>> = CompletableFuture.completedFuture(send(request, handler))

        override fun cookieHandler(): Optional<java.net.CookieHandler> = Optional.empty()
        override fun connectTimeout(): Optional<java.time.Duration> = Optional.empty()
        override fun followRedirects(): Redirect = Redirect.NORMAL
        override fun proxy(): Optional<java.net.ProxySelector> = Optional.empty()
        override fun sslContext(): javax.net.ssl.SSLContext = javax.net.ssl.SSLContext.getDefault()
        override fun sslParameters(): javax.net.ssl.SSLParameters = javax.net.ssl.SSLParameters()
        override fun authenticator(): Optional<java.net.Authenticator> = Optional.empty()
        override fun version(): Version = Version.HTTP_1_1
        override fun executor(): Optional<java.util.concurrent.Executor> = Optional.empty()
    }

    private fun clientWith(
        status: Int,
        body: String,
        headers: Map<String, List<String>> = emptyMap(),
    ): MisarReachClient =
        MisarReachClient(
            apiKey = "mrk_test",
            maxRetries = 1,
            httpClient = stubClient(status, body, headers),
        )

    private fun contentType(value: String) = mapOf("content-type" to listOf(value))

    // ── Tests ───────────────────────────────────────────────────────────────────

    @Test
    fun `leads search returns parsed response on 200`() = runBlocking {
        val client = clientWith(200, """{"jobId":"job_1","status":"queued"}""")
        val result = client.leads.search(mapOf("query" to "SaaS founders"))
        assertEquals("job_1", result["jobId"])
        assertEquals("queued", result["status"])
    }

    @Test
    fun `contacts list returns parsed response on 200`() = runBlocking {
        val client = clientWith(200, """{"data":[]}""")
        val result = client.contacts.list()
        assertTrue(result.containsKey("data"))
    }

    @Test
    fun `channels status returns parsed response on 200`() = runBlocking {
        val client = clientWith(200, """{"sms":{"connected":true}}""")
        val result = client.channels.status()
        assertTrue(result.containsKey("sms"))
    }

    @Test
    fun `deals create returns parsed response on 201`() = runBlocking {
        val client = clientWith(201, """{"id":"deal_1"}""")
        val result = client.deals.create(mapOf("title" to "New deal"))
        assertEquals("deal_1", result["id"])
    }

    @Test
    fun `error envelope throws with status and message`() = runBlocking {
        val client = clientWith(401, """{"error":{"code":"unauthorized","message":"Invalid API key"}}""")
        val ex = assertFailsWith<MisarReachException> {
            client.leads.search(mapOf("query" to "x"))
        }
        assertEquals(401, ex.status)
        assertTrue(ex.message!!.contains("Invalid API key"))
    }

    @Test
    fun `empty body on 200 returns empty map`() = runBlocking {
        val client = clientWith(200, "")
        val result = client.contacts.list()
        assertEquals(emptyMap(), result)
    }

    @Test
    fun `lead job SSE stream emits each named frame`() = runBlocking {
        // MisarReach names its events and sends `: keepalive` every 20s. It does
        // not send a [DONE] sentinel — the stream ends when the server closes it.
        val sse = "event: progress\ndata: {\"message\":\"searching\"}\n\n" +
            ": keepalive\n\n" +
            "event: found\ndata: {\"total\":12}\n\n" +
            "event: complete\ndata: {\"total_found\":12}\n\n"

        val client = clientWith(200, sse, contentType("text/event-stream"))
        val events = client.leads.stream("job_1").toList()

        // The keepalive comment must not surface as an event.
        assertEquals(listOf("progress", "found", "complete"), events.map { it.event })
        assertEquals(12, events[1].data?.get("total"))
    }

    @Test
    fun `lead job stream reports an already finished job`() = runBlocking {
        // A finished job is answered with a JSON snapshot rather than a stream.
        // Parsed as SSE this emits nothing, so the caller could not tell a
        // finished job from a silent one.
        val client = clientWith(
            200,
            """{"status":"done","total_found":42,"error":null}""",
            contentType("application/json"),
        )

        val events = client.leads.stream("job_done").toList()

        assertEquals(1, events.size)
        assertEquals("complete", events[0].event)
        assertEquals(42, events[0].data?.get("total_found"))
    }

    @Test
    fun `lead job stream reports a failed job as error`() = runBlocking {
        val client = clientWith(
            200,
            """{"status":"failed","error":"no sources reachable"}""",
            contentType("application/json"),
        )

        val events = client.leads.stream("job_bad").toList()

        assertEquals("error", events[0].event)
    }

    @Test
    fun `lead job stream refusal is typed`() = runBlocking {
        val client = clientWith(
            402,
            """{"error":"monthly lead searches used up","upgrade":true,
                "feature":"lead_searches","limit":50,"current":50,
                "upgrade_url":"/settings?tab=billing"}""",
            contentType("application/json"),
        )

        // A plan refusal on the stream must raise the same typed error the JSON
        // helper raises, not a generic exception with a fixed message.
        val ex = assertFailsWith<UpgradeRequiredException> {
            client.leads.stream("job_1").toList()
        }

        assertEquals(402, ex.status)
        assertEquals("lead_searches", ex.feature)
        assertTrue(ex.message!!.contains("monthly lead searches used up"))
        // The server sends it app-relative; the SDK resolves it.
        assertEquals("https://misarreach.com/settings?tab=billing", ex.upgradeUrl)
    }
}
