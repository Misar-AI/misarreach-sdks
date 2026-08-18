import com.vanniktech.maven.publish.SonatypeHost

plugins {
    kotlin("jvm") version "1.9.22"
    `java-library`
    // NOT `maven-publish` + `signing`. Those upload by PUTting each file to the
    // repository URL, but https://central.sonatype.com/api/v1/publisher/upload is
    // a bundle POST API, not a Maven repo — every PUT 404s and nothing is ever
    // published. This plugin speaks the Central Portal protocol.
    id("com.vanniktech.maven.publish") version "0.30.0"
}

group = "io.misar"
version = "5.0.3"

repositories {
    mavenCentral()
}

dependencies {
    // `api`, not `implementation`: leads.stream() returns Flow, so the type is part
    // of this library's ABI. Under `implementation` the POM scopes it to runtime and
    // a consumer cannot compile against the published artifact at all.
    api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.0")
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin:2.17.1")
    testImplementation(kotlin("test"))
    // Gradle 9 no longer puts the JUnit Platform launcher on the test runtime
    // classpath implicitly. Without it `gradle test` dies with "Failed to load
    // JUnit Platform" before running a single test.
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.0")
}

kotlin {
    jvmToolchain(17)
}

tasks.test {
    useJUnitPlatform()
}

// The sources and javadoc jars Central requires are produced by the publishing
// plugin, so declaring them here too would build two artifacts per classifier.

mavenPublishing {
    publishToMavenCentral(SonatypeHost.CENTRAL_PORTAL, automaticRelease = true)
    signAllPublications()
    coordinates("io.misar", "misarreach-kotlin", version.toString())

    pom {
        name.set("MisarReach Kotlin SDK")
        description.set(
            "Kotlin coroutine client for the MisarReach outreach and lead-generation API: " +
                "asynchronous lead search across 23 sources, streamed live as a Flow of " +
                "Server-Sent Events; CRM contacts, deals and a Kanban pipeline; multi-step " +
                "email, SMS, WhatsApp, web-push and social-DM campaigns; AI sales agent, " +
                "autopilot, deliverability and plan quotas. 17 resource groups covering all " +
                "94 REST operations as suspend functions over JSON maps, Bearer mrk_ auth, " +
                "exponential-backoff retries on 429/500/502/503/504, and a typed 402 " +
                "plan-cap refusal naming the exhausted counter. JVM 17+."
        )
        url.set("https://www.misarreach.com")
        licenses {
            license {
                name.set("MIT License")
                url.set("https://opensource.org/licenses/MIT")
            }
        }
        developers {
            developer {
                name.set("Misar AI")
                email.set("hello@misar.io")
                organization.set("Misar AI Technology Pvt Ltd")
                organizationUrl.set("https://misar.io")
            }
        }
        scm {
            connection.set("scm:git:git://github.com/Misar-AI/misarreach-sdks.git")
            developerConnection.set("scm:git:ssh://github.com/Misar-AI/misarreach-sdks.git")
            url.set("https://github.com/Misar-AI/misarreach-sdks/tree/main/kotlin")
        }
        issueManagement {
            system.set("GitHub Issues")
            url.set("https://github.com/Misar-AI/misarreach-sdks/issues")
        }
        properties.set(mapOf("documentation" to "https://docs.misar.io/reach"))
    }
}
