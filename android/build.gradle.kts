plugins {
    // AGP 9 compiles Kotlin itself, so there's no separate Kotlin Android plugin.
    id("com.android.application") version "9.5.1" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.21" apply false
}
