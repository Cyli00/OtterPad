package io.github.cyli00.otterpad

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "io.github.cyli00.otterpad/share"
        private const val PDF_MIME_TYPE = "application/pdf"
        private const val BINARY_MIME_TYPE = "application/octet-stream"
        private val PDF_HEADER = "%PDF-".toByteArray(Charsets.US_ASCII)
    }

    private var channel: MethodChannel? = null
    private var pendingFilePaths: List<String>? = null
    private var initialIntentProcessed = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialSharedFiles" -> {
                        result.success(pendingFilePaths)
                        pendingFilePaths = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        if (!initialIntentProcessed) {
            initialIntentProcessed = true
            pendingFilePaths = extractFilePaths(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // singleTop 下必须更新当前 Intent，避免后续 getInitialSharedFiles 读到旧数据。
        setIntent(intent)
        val paths = extractFilePaths(intent)
        if (paths.isNotEmpty()) {
            channel?.invokeMethod("onSharedFiles", paths)
        }
    }

    private fun extractFilePaths(intent: Intent): List<String> {
        val uris = mutableListOf<Uri>()

        when (intent.action) {
            Intent.ACTION_VIEW -> {
                intent.data?.let { uris.add(it) }
            }
            Intent.ACTION_SEND -> {
                getStreamUri(intent)?.let { uris.add(it) }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                getStreamUris(intent)?.let { uris.addAll(it) }
            }
        }

        return uris.mapNotNull { copyToTemp(it) }
    }

    private fun getStreamUri(intent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
    }

    private fun getStreamUris(intent: Intent): List<Uri>? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }
    }

    private fun copyToTemp(uri: Uri): String? {
        return try {
            val mimeType = contentResolver.getType(uri)
            if (
                mimeType != null &&
                mimeType != PDF_MIME_TYPE &&
                mimeType != BINARY_MIME_TYPE
            ) {
                return null
            }

            val inputStream = contentResolver.openInputStream(uri) ?: return null
            inputStream.use { input ->
                val header = ByteArray(PDF_HEADER.size)
                var bytesRead = 0
                while (bytesRead < header.size) {
                    val count = input.read(header, bytesRead, header.size - bytesRead)
                    if (count <= 0) return null
                    bytesRead += count
                }
                if (!header.contentEquals(PDF_HEADER)) return null

                val fileName = resolveFileName(uri)
                val dir = File(cacheDir, "shared_pdfs")
                dir.mkdirs()
                val dest = File(dir, fileName)
                try {
                    FileOutputStream(dest).use { out ->
                        out.write(header)
                        input.copyTo(out)
                    }
                    dest.absolutePath
                } catch (error: Exception) {
                    dest.delete()
                    throw error
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun resolveFileName(uri: Uri): String {
        var name: String? = null
        if (uri.scheme == "content") {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) {
                        val display = cursor.getString(idx)
                        if (!display.isNullOrBlank()) name = display
                    }
                }
            }
        }
        if (name.isNullOrBlank()) {
            name = uri.lastPathSegment
        }
        if (name.isNullOrBlank()) {
            name = "shared_${System.currentTimeMillis()}.pdf"
        }

        // content://media/.../1000059098 这类 URI 常无扩展名；Dart 侧按 .pdf 过滤，必须补齐。
        var safe = name.substringAfterLast('/').substringAfterLast('\\')
        safe = safe.replace(Regex("[\\/:*?\"<>|]"), "_")
        if (safe.isBlank()) {
            safe = "shared_${System.currentTimeMillis()}.pdf"
        }
        if (!safe.lowercase().endsWith(".pdf")) {
            safe = "$safe.pdf"
        }
        return safe
    }
}
