plugins {
    id("com.android.application")
    id("org.lsposed.lsparanoid")
}

lsparanoid {
    seed = if (RAND_SEED != 0) RAND_SEED else null
    includeDependencies = true
    // lsparanoid 0.6.0 dropped `global` for a filter. `classFilter = { true }` is
    // its documented replacement -- obfuscate every class, not only @Obfuscate-
    // annotated ones. The default is null, i.e. annotated classes only, so simply
    // deleting the old line would still build and still pass CI while quietly
    // leaving most of the stub's strings in the clear.
    classFilter = { true }
}

android {
    namespace = "com.topjohnwu.magisk"

    val url: String? = null  // Kyubi: never bake a foreign release host into the stub

    defaultConfig {
        applicationId = "io.github.robthepcguy.kyubi"
        versionCode = 1
        versionName = "1.0"
        buildConfigField("String", "APK_URL", url?.let { "\"$it\"" } ?: "null" )
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = false
            proguardFiles("proguard-rules.pro")
        }
    }
}

setupStub()

dependencies {
    implementation(project(":app:shared"))
}
