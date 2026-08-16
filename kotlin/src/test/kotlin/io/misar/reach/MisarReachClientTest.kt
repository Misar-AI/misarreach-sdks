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

    private fun stubClient(status: Int, body: String): HttpClient = object : HttpClient() {
        override fun <T> send(request: HttpRequest, handler: HttpResponse.BodyHandler<T>): HttpResponse<T> {
            val info = object : HttpResponse.ResponseInfo {
                override fun statusCode() = status
                override fun headers() = java.net.http.HttpHeaders.of(emptyMap()) { _, _ -> true }
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
                override fun headers() = java.net.http.HttpHeaders.of(emptyMap()) { _, _ -> true }
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

    private fun clientWith(status: Int, body: String): MisarReachClient =
        MisarReachClient(apiKey = "mrk_test", maxRetries = 1, httpClient = stubClient(status, body))

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
    fun `lead job SSE stream parses frames`() = runBlocking {
        val sse = "data: {\"status\":\"running\",\"progress\":10}\n" +
            "\n" +
            "data: {\"status\":\"running\",\"progress\":100}\n" +
            "\n" +
            "data: [DONE]\n"
        val client = clientWith(200, sse)
        val events = client.leads.stream("job_1").toList()
        assertEquals(2, events.size)
        assertEquals(10, events[0]["progress"])
        assertEquals(100, events[1]["progress"])
    }
}
