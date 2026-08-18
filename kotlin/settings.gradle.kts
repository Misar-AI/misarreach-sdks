// Without this the project name comes from whatever directory the build runs
// in, so the local jar was named after the container's working directory. The
// publication sets artifactId explicitly, so published coordinates were never
// affected — but the build should not depend on its path.
rootProject.name = "misarreach-kotlin"
