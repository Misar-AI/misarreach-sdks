plugins {
    kotlin("jvm") version "1.9.22"
    `java-library`
    `maven-publish`
    signing
}

group = "io.misar"
version = "1.0.0"

repositories {
    mavenCentral()
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.0")
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin:2.17.1")
    testImplementation(kotlin("test"))
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.0")
}

kotlin {
    jvmToolchain(17)
}

tasks.test {
    useJUnitPlatform()
}

java {
    withSourcesJar()
    withJavadocJar()
}

publishing {
    publications {
        create<MavenPublication>("mavenJava") {
            from(components["java"])
            groupId = "io.misar"
            artifactId = "misarreach-kotlin"

            pom {
                name.set("MisarReach Kotlin SDK")
                description.set("Official Kotlin SDK for the MisarReach developer API — coroutines, full coverage, SSE lead-job streaming")
                url.set("https://reach.misar.io/docs/sdks/kotlin")
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
                    connection.set("scm:git:git://github.com/misarai/misarreach-kotlin.git")
                    url.set("https://github.com/misarai/misarreach-kotlin")
                }
            }
        }
    }

    repositories {
        maven {
            name = "central"
            url = uri("https://central.sonatype.com/api/v1/publisher/upload")
            credentials {
                username = System.getenv("OSSRH_USERNAME") ?: "" // env var — no hardcoded value here
                password = System.getenv("OSSRH_PASSWORD") ?: "" // env var — no hardcoded value here
            }
        }
    }
}

signing {
    val gpgPrivateKey = System.getenv("MAVEN_GPG_PRIVATE_KEY") ?: ""
    val gpgPassphrase = System.getenv("MAVEN_GPG_PASSPHRASE") ?: ""
    useInMemoryPgpKeys(gpgPrivateKey, gpgPassphrase)
    sign(publishing.publications["mavenJava"])
}
