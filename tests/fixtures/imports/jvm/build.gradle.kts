import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    java
    kotlin("jvm") version "2.0.20"
}

repositories {
    mavenCentral()
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
    implementation("com.fasterxml.jackson.core:jackson-databind:2.17.2")
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.3")
}

sourceSets["main"].java.srcDirs("src/main/java")

tasks.withType<KotlinCompile>().configureEach {
    kotlinOptions.jvmTarget = "17"
}

// Path shaped and upward traversing, in a file the extractor DOES parse
// (.kts is a JVM extension). Must resolve to nothing, and must never be
// followed out of the fixture directory.
apply(from = "../../../../scripts/code-graph.awk")
