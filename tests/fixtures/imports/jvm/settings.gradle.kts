rootProject.name = "acme-billing"

// Path shaped, upward traversing, and live. JVM resolution never reads a
// build file, so this must resolve to nothing. It is here so that a later
// "resolve path shaped strings in .kts" rule cannot quietly escape the root.
includeBuild("../../../../..")
