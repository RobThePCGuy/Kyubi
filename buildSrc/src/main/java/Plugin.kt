
import org.eclipse.jgit.api.Git
import org.eclipse.jgit.internal.storage.file.FileRepository
import org.eclipse.jgit.lib.Constants
import org.eclipse.jgit.revwalk.RevWalk
import org.gradle.api.GradleException
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.kotlin.dsl.provideDelegate
import java.io.File
import java.util.*

private val props = Properties()
private var commitHash = ""
private var computedBuildCode = 0

// Highest Android versionCode shipped before the build-code split. Deliberately
// NOT derived from magisk.versionCode: the two are equal today only by accident
// of history, and deriving one from the other would recouple the meanings.
private const val LEGACY_BUILD_CODE_BASE = 31_000

object Config {
    operator fun get(key: String): String? {
        val v = props[key] as? String ?: return null
        return if (v.isBlank()) null else v
    }

    fun contains(key: String) = get(key) != null

    val version: String get() = get("version") ?: commitHash

    // Magisk core compatibility level the daemon implements. Feeds flags.h and
    // util_functions.sh; compared against the installed daemon's `magisk -V`.
    val coreVersionCode: Int get() = get("magisk.versionCode")!!.toInt()

    // Monotonic ordering key for the APK. NOT an identity -- the commit SHA is.
    val buildCode: Int get() = computedBuildCode

    val stubVersion: String get() = get("magisk.stubVersion")!!
}

private fun computeBuildCode(repo: FileRepository): Int {
    val anchorSha = Config["kyubi.buildCodeAnchor"]
        ?: throw GradleException("kyubi.buildCodeAnchor is missing from gradle.properties")

    // resolve() builds an ObjectId from any well-formed 40-hex string WITHOUT
    // consulting the object database, so a null check alone does not detect a
    // missing anchor -- it would surface later as a raw MissingObjectException
    // from parseCommit, losing the actionable message. Check existence explicitly.
    val anchorId = repo.resolve(anchorSha)
        ?: throw GradleException("kyubi.buildCodeAnchor '$anchorSha' is not a valid object id")
    if (!repo.newObjectReader().use { it.has(anchorId) })
        throw GradleException(
            "Cannot resolve Kyubi build-code anchor $anchorSha -- the commit is not " +
            "in this clone. Run `git fetch --unshallow`.")
    val headId = repo.resolve(Constants.HEAD)
        ?: throw GradleException("Cannot resolve HEAD")

    // addRange() is `anchor..head`; it does NOT require the anchor to be an
    // ancestor. Without this check a rewritten history whose anchor object still
    // exists yields a plausible but wrong count instead of failing.
    RevWalk(repo).use { walk ->
        val anchor = walk.parseCommit(anchorId)
        val head = walk.parseCommit(headId)
        if (!walk.isMergedInto(anchor, head))
            throw GradleException(
                "Kyubi build-code anchor $anchorSha is not an ancestor of HEAD -- the " +
                "release lineage was rewritten. Fetching more history will not fix this.")
    }

    val count = Git(repo).log().addRange(anchorId, headId).call().count()
    if (count == 0)
        throw GradleException("HEAD is the legacy versionCode $LEGACY_BUILD_CODE_BASE anchor")

    return LEGACY_BUILD_CODE_BASE + count
}

class MagiskPlugin : Plugin<Project> {
    override fun apply(project: Project) = project.applyPlugin()

    private fun Project.applyPlugin() {
        initRandom(rootProject.file("dict.txt"))
        props.clear()
        rootProject.file("gradle.properties").inputStream().use { props.load(it) }
        val configPath: String? by this
        val config = configPath?.let { File(it) } ?: rootProject.file("config.prop")
        if (config.exists())
            config.inputStream().use { props.load(it) }

        val repo = FileRepository(rootProject.file(".git"))
        val refId = repo.refDatabase.exactRef("HEAD").objectId
        commitHash = repo.newObjectReader().abbreviate(refId, 8).name()
        computedBuildCode = computeBuildCode(repo)
    }
}
