import groovy.json.JsonSlurper
import java.net.URI
val configurationRoot = rootProject.projectDir.parentFile.resolve("Configuration/Supabase")
fun publicSettings(environment: String): Pair<String, String> {
 val file = configurationRoot.resolve("$environment.local.json")
 val contents = providers.fileContents(layout.projectDirectory.file(file.absolutePath)).asText.orNull ?: return "" to ""
 val data = JsonSlurper().parseText(contents) as Map<*, *>
 val url = (data["projectUrl"] as? String).orEmpty().trimEnd('/')
 val key = (data["publishableKey"] as? String).orEmpty().trim()
 if (key.startsWith("REPLACE_WITH_") || key.isBlank()) return "" to ""
 val uri = URI(url)
 val expected = if (environment == "production") "https://ampzpsyzhcekdbcrrqpb.supabase.co" else "https://hijtwgugzzpjjkuutyfy.supabase.co"
 require((environment == "staging" && url != "https://ampzpsyzhcekdbcrrqpb.supabase.co" || url == expected) && uri.scheme == "https" && uri.host != null && uri.port == -1 && uri.userInfo == null && uri.query == null && uri.fragment == null && uri.path.isNullOrEmpty() && key.startsWith("sb_publishable_")) { "Local service configuration requires HTTPS and a public publishable key" }
 return url to key
}
fun literal(value: String): String = groovy.json.JsonOutput.toJson(value)
val serviceSettings = mapOf("debug" to publicSettings("development"), "release" to publicSettings("production"), "staging" to publicSettings("staging"))
extra["publicServiceSettings"] = serviceSettings

val stagingFirebase = rootProject.file("../Configuration/Firebase/Staging/google-services.json")
if (stagingFirebase.isFile && configurationRoot.resolve("staging.local.json").isFile) {
 copy { from(stagingFirebase); into(project.file("src/staging")) }
}

