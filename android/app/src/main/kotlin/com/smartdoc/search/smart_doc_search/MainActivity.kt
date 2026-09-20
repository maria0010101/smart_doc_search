package com.smartdoc.search.smart_doc_search

import android.os.Bundle
import com.smartdoc.search.smart_doc_search.koredb.KoreDBNativeStore
import com.smartdoc.search.smart_doc_search.koredb.PdfNativeProcessor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val KOREDB_CHANNEL = "com.smartdoc.search/koredb"
    private val TOOLS_CHANNEL = "com.smartdoc.search/native_tools"

    private lateinit var koreDB: KoreDBNativeStore
    private val backgroundExecutor = Executors.newCachedThreadPool()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        koreDB = KoreDBNativeStore(applicationContext)

        // KoreDB Bridge Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KOREDB_CHANNEL).setMethodCallHandler { call, result ->
            backgroundExecutor.execute {
                try {
                    when (call.method) {
                        "insertDocument" -> {
                            val docJson = call.argument<String>("document") ?: ""
                            val id = koreDB.insertDocument(docJson)
                            runOnUiThread { result.success(id) }
                        }
                        "updateDocument" -> {
                            val docJson = call.argument<String>("document") ?: ""
                            val ok = koreDB.updateDocument(docJson)
                            runOnUiThread { result.success(ok) }
                        }
                        "deleteDocument" -> {
                            val id = call.argument<String>("id") ?: ""
                            val ok = koreDB.deleteDocument(id)
                            runOnUiThread { result.success(ok) }
                        }
                        "getDocument" -> {
                            val id = call.argument<String>("id") ?: ""
                            val doc = koreDB.getDocument(id)
                            runOnUiThread { result.success(doc) }
                        }
                        "getAllDocuments" -> {
                            val docs = koreDB.getAllDocuments()
                            runOnUiThread { result.success(docs) }
                        }
                        "queryByTags" -> {
                            val tags = call.argument<List<String>>("tags") ?: emptyList()
                            val mode = call.argument<String>("mode") ?: "AND"
                            val res = koreDB.queryByTags(tags, mode)
                            runOnUiThread { result.success(res) }
                        }
                        "hybridSearch" -> {
                            val keywords = call.argument<List<String>>("keywords") ?: emptyList()
                            val tags = call.argument<List<String>>("tags") ?: emptyList()
                            val tagMode = call.argument<String>("tagMode") ?: "AND"
                            val limit = call.argument<Int>("limit") ?: 20
                            val offset = call.argument<Int>("offset") ?: 0
                            val embList = call.argument<List<Double>>("semanticEmbedding")
                            val embedding = embList?.map { it.toFloat() }?.toFloatArray()

                            val searchRes = koreDB.hybridSearch(
                                keywords = keywords,
                                tags = tags,
                                tagMode = tagMode,
                                semanticEmbedding = embedding,
                                limit = limit,
                                offset = offset
                            )
                            runOnUiThread { result.success(searchRes.toString()) }
                        }
                        "insertPage" -> {
                            val pageJson = call.argument<String>("page") ?: ""
                            val id = koreDB.insertPage(pageJson)
                            runOnUiThread { result.success(id) }
                        }
                        "getPages" -> {
                            val docId = call.argument<String>("documentId") ?: ""
                            val pages = koreDB.getPages(docId)
                            runOnUiThread { result.success(pages) }
                        }
                        "vectorSearch" -> {
                            val embList = call.argument<List<Double>>("embedding") ?: emptyList()
                            val topK = call.argument<Int>("topK") ?: 10
                            val embedding = FloatArray(embList.size) { embList[it].toFloat() }
                            val hits = koreDB.vectorSearch(embedding, topK)
                            val hitsArr = JSONArray()
                            for ((docId, score) in hits) {
                                val obj = JSONObject()
                                obj.put("id", docId)
                                obj.put("score", score.toDouble())
                                hitsArr.put(obj)
                            }
                            runOnUiThread { result.success(hitsArr.toString()) }
                        }
                        "getAllTags" -> {
                            val tags = koreDB.getAllTags()
                            runOnUiThread { result.success(tags) }
                        }
                        "updateTag" -> {
                            val tagJson = call.argument<String>("tag") ?: ""
                            val ok = koreDB.updateTag(tagJson)
                            runOnUiThread { result.success(ok) }
                        }
                        "deleteTag" -> {
                            val tagId = call.argument<String>("id") ?: ""
                            val ok = koreDB.deleteTag(tagId)
                            runOnUiThread { result.success(ok) }
                        }
                        "getStats" -> {
                            val stats = koreDB.getStats()
                            runOnUiThread { result.success(stats.toString()) }
                        }
                        "exportBackup" -> {
                            val backup = koreDB.exportBackup()
                            runOnUiThread { result.success(backup) }
                        }
                        "restoreBackup" -> {
                            val backupJson = call.argument<String>("backupJson") ?: ""
                            val ok = koreDB.restoreBackup(backupJson)
                            runOnUiThread { result.success(ok) }
                        }
                        "clearAll" -> {
                            val ok = koreDB.clearAll()
                            runOnUiThread { result.success(ok) }
                        }
                        else -> {
                            runOnUiThread { result.notImplemented() }
                        }
                    }
                } catch (e: Exception) {
                    runOnUiThread { result.error("KOREDB_ERROR", e.message, null) }
                }
            }
        }

        // Native Tools Channel (PDF Rendering & Layout Analysis)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TOOLS_CHANNEL).setMethodCallHandler { call, result ->
            backgroundExecutor.execute {
                try {
                    when (call.method) {
                        "renderPdfPages" -> {
                            val pdfPath = call.argument<String>("pdfPath") ?: ""
                            val outputDir = call.argument<String>("outputDir") ?: ""
                            val maxPages = call.argument<Int>("maxPages") ?: 50
                            val pages = PdfNativeProcessor.renderPdfPages(applicationContext, pdfPath, outputDir, maxPages)
                            runOnUiThread { result.success(pages) }
                        }
                        "analyzeLayout" -> {
                            val text = call.argument<String>("text") ?: ""
                            val blocks = PdfNativeProcessor.analyzeLayout(text)
                            runOnUiThread { result.success(blocks.toString()) }
                        }
                        "getDefaultLiteratureDirectory" -> {
                            try {
                                val publicDocs = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOCUMENTS)
                                val appFolder = java.io.File(publicDocs, "Smart_Doc")
                                runOnUiThread { result.success(appFolder.absolutePath) }
                            } catch (e: Exception) {
                                runOnUiThread { result.success("/storage/emulated/0/Documents/Smart_Doc") }
                            }
                        }
                        "copyToDocuments" -> {
                            val sourcePath = call.argument<String>("sourcePath") ?: ""
                            val fileName = call.argument<String>("fileName") ?: ""
                            val targetDir = call.argument<String>("targetDir")
                            val sourceFile = java.io.File(sourcePath)
                            if (!sourceFile.exists()) {
                                runOnUiThread { result.error("FILE_NOT_FOUND", "檔案不存在: $sourcePath", null) }
                                return@execute
                            }
                            try {
                                val copiedPath = copyFileToDeviceDocuments(sourceFile, fileName, targetDir)
                                runOnUiThread { result.success(copiedPath) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("COPY_ERROR", e.message, null) }
                            }
                        }
                        "exportBackupToDownloads" -> {
                            val fileName = call.argument<String>("fileName") ?: "koredb_backup.json"
                            val bytes = call.argument<ByteArray>("bytes")
                            val content = call.argument<String>("content")
                            val dataBytes = bytes ?: (content?.toByteArray(Charsets.UTF_8) ?: ByteArray(0))
                            val mimeType = if (fileName.endsWith(".gz", ignoreCase = true)) "application/gzip" else "application/json"
                            try {
                                val savedPath = exportFileToDownloads(fileName, dataBytes, mimeType)
                                runOnUiThread { result.success(savedPath) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("EXPORT_ERROR", e.message, null) }
                            }
                        }
                        "openFile" -> {
                            val filePath = call.argument<String>("filePath") ?: ""
                            var file = java.io.File(filePath)
                            if (!file.exists()) {
                                // Fallback: Check Smart_Doc, legacy SmartDocSearch, external and internal paths
                                val fileName = java.io.File(filePath).name
                                val publicDocs = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOCUMENTS)
                                val candidate1 = java.io.File(publicDocs, "Smart_Doc/$fileName")
                                val candidate2 = java.io.File(publicDocs, "SmartDocSearch/$fileName")
                                val candidate3 = applicationContext.getExternalFilesDir(android.os.Environment.DIRECTORY_DOCUMENTS)?.let { java.io.File(it, "Smart_Doc/$fileName") }
                                val candidate4 = applicationContext.getExternalFilesDir(android.os.Environment.DIRECTORY_DOCUMENTS)?.let { java.io.File(it, "SmartDocSearch/$fileName") }
                                val candidate5 = java.io.File(applicationContext.filesDir, "Documents/Smart_Doc/$fileName")
                                val candidate6 = java.io.File(applicationContext.filesDir, "Documents/$fileName")

                                file = when {
                                    candidate1.exists() -> candidate1
                                    candidate2.exists() -> candidate2
                                    candidate3 != null && candidate3.exists() -> candidate3
                                    candidate4 != null && candidate4.exists() -> candidate4
                                    candidate5.exists() -> candidate5
                                    candidate6.exists() -> candidate6
                                    else -> file
                                }
                            }
                            if (!file.exists()) {
                                runOnUiThread { result.error("FILE_NOT_FOUND", "檔案不存在: $filePath", null) }
                                return@execute
                            }
                            try {
                                val uri = androidx.core.content.FileProvider.getUriForFile(
                                    applicationContext,
                                    "${applicationContext.packageName}.fileprovider",
                                    file
                                )
                                val mimeType = when {
                                    file.name.endsWith(".pdf", ignoreCase = true) -> "application/pdf"
                                    file.name.endsWith(".png", ignoreCase = true) -> "image/png"
                                    file.name.endsWith(".jpg", ignoreCase = true) || file.name.endsWith(".jpeg", ignoreCase = true) -> "image/jpeg"
                                    file.name.endsWith(".webp", ignoreCase = true) -> "image/webp"
                                    file.name.endsWith(".txt", ignoreCase = true) || file.name.endsWith(".log", ignoreCase = true) -> "text/plain"
                                    file.name.endsWith(".md", ignoreCase = true) || file.name.endsWith(".markdown", ignoreCase = true) -> "text/markdown"
                                    file.name.endsWith(".csv", ignoreCase = true) -> "text/csv"
                                    file.name.endsWith(".json", ignoreCase = true) -> "application/json"
                                    file.name.endsWith(".gz", ignoreCase = true) -> "application/gzip"
                                    file.name.endsWith(".zip", ignoreCase = true) -> "application/zip"
                                    file.name.endsWith(".ppt", ignoreCase = true) || file.name.endsWith(".pptx", ignoreCase = true) -> "application/vnd.ms-powerpoint"
                                    else -> "*/*"
                                }
                                val intent = android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, mimeType)
                                    addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                val chooser = android.content.Intent.createChooser(intent, "開啟原始檔案").apply {
                                    addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                                    addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                applicationContext.startActivity(chooser)
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("OPEN_ERROR", e.message, null) }
                            }
                        }
                        else -> {
                            runOnUiThread { result.notImplemented() }
                        }
                    }
                } catch (e: Exception) {
                    runOnUiThread { result.error("TOOLS_ERROR", e.message, null) }
                }
            }
        }
    }

    /**
     * Copies imported literature file to device Documents directory.
     * Tries public /storage/emulated/0/Documents/Smart_Doc first,
     * then app-specific external Documents, and finally internal Documents.
     */
    private fun copyFileToDeviceDocuments(sourceFile: java.io.File, preferredName: String, customTargetDir: String? = null): String {
        val name = if (preferredName.isNotEmpty()) preferredName else sourceFile.name

        // Strategy 0: Custom target directory (if specified by user)
        if (!customTargetDir.isNullOrBlank()) {
            try {
                val customFolder = java.io.File(customTargetDir)
                if (!customFolder.exists()) {
                    customFolder.mkdirs()
                }
                if (customFolder.exists()) {
                    val targetFile = java.io.File(customFolder, name)
                    sourceFile.copyTo(targetFile, overwrite = true)
                    if (targetFile.exists() && targetFile.length() > 0) {
                        return targetFile.absolutePath
                    }
                }
            } catch (_: Exception) {}
        }

        // Strategy 1: Public Documents Directory (/storage/emulated/0/Documents/Smart_Doc)
        try {
            val publicDocs = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOCUMENTS)
            val appFolder = java.io.File(publicDocs, "Smart_Doc")
            if (!appFolder.exists()) {
                appFolder.mkdirs()
            }
            if (appFolder.exists()) {
                val targetFile = java.io.File(appFolder, name)
                sourceFile.copyTo(targetFile, overwrite = true)
                if (targetFile.exists() && targetFile.length() > 0) {
                    return targetFile.absolutePath
                }
            }
        } catch (_: Exception) {}

        // Strategy 2: App external storage Documents directory
        try {
            val extDocsDir = applicationContext.getExternalFilesDir(android.os.Environment.DIRECTORY_DOCUMENTS)
            if (extDocsDir != null) {
                val appFolder = java.io.File(extDocsDir, "Smart_Doc")
                if (!appFolder.exists()) appFolder.mkdirs()
                val targetFile = java.io.File(appFolder, name)
                sourceFile.copyTo(targetFile, overwrite = true)
                if (targetFile.exists() && targetFile.length() > 0) {
                    return targetFile.absolutePath
                }
            }
        } catch (_: Exception) {}

        // Strategy 3: Internal app files Documents directory
        val internalDocs = java.io.File(applicationContext.filesDir, "Documents/Smart_Doc")
        if (!internalDocs.exists()) internalDocs.mkdirs()
        val targetFile = java.io.File(internalDocs, name)
        sourceFile.copyTo(targetFile, overwrite = true)
        return targetFile.absolutePath
    }

    /**
     * Exports database backup file to the device public Downloads directory (/storage/emulated/0/Download).
     * Strategy 1: MediaStore.Downloads (Android 10+ / API 29+), standard scoped storage.
     * Strategy 2: Direct write to Environment.DIRECTORY_DOWNLOADS.
     * Strategy 3: App external files Downloads directory.
     * Strategy 4: App internal files directory.
     */
    private fun exportFileToDownloads(fileName: String, dataBytes: ByteArray, mimeType: String): String {
        // Strategy 1: MediaStore.Downloads (Android Q+, API 29+)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            try {
                val resolver = applicationContext.contentResolver
                // Remove existing entry with identical name in MediaStore if present
                try {
                    val projection = arrayOf(android.provider.MediaStore.MediaColumns._ID)
                    val selection = "${android.provider.MediaStore.MediaColumns.DISPLAY_NAME} = ?"
                    val selectionArgs = arrayOf(fileName)
                    resolver.query(
                        android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                        projection, selection, selectionArgs, null
                    )?.use { cursor ->
                        while (cursor.moveToNext()) {
                            val id = cursor.getLong(cursor.getColumnIndexOrThrow(android.provider.MediaStore.MediaColumns._ID))
                            val deleteUri = android.content.ContentUris.withAppendedId(
                                android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, id
                            )
                            resolver.delete(deleteUri, null, null)
                        }
                    }
                } catch (_: Exception) {}

                val contentValues = android.content.ContentValues().apply {
                    put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(android.provider.MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, android.os.Environment.DIRECTORY_DOWNLOADS)
                    put(android.provider.MediaStore.MediaColumns.IS_PENDING, 1)
                }

                val uri = resolver.insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                if (uri != null) {
                    resolver.openOutputStream(uri)?.use { os ->
                        os.write(dataBytes)
                        os.flush()
                    }
                    contentValues.clear()
                    contentValues.put(android.provider.MediaStore.MediaColumns.IS_PENDING, 0)
                    resolver.update(uri, contentValues, null, null)

                    val publicDownloads = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS)
                    val targetFile = java.io.File(publicDownloads, fileName)
                    if (targetFile.exists() && targetFile.length() > 0) {
                        return targetFile.absolutePath
                    }
                    return "/storage/emulated/0/Download/$fileName"
                }
            } catch (e: Exception) {
                android.util.Log.w("MainActivity", "MediaStore export to Downloads failed: ${e.message}")
            }
        }

        // Strategy 2: Direct file write to public Download directory
        try {
            val publicDownloads = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS)
            if (!publicDownloads.exists()) {
                publicDownloads.mkdirs()
            }
            val targetFile = java.io.File(publicDownloads, fileName)
            targetFile.writeBytes(dataBytes)
            if (targetFile.exists() && targetFile.length() > 0) {
                android.media.MediaScannerConnection.scanFile(
                    applicationContext,
                    arrayOf(targetFile.absolutePath),
                    arrayOf(mimeType),
                    null
                )
                return targetFile.absolutePath
            }
        } catch (e: Exception) {
            android.util.Log.w("MainActivity", "Direct Download folder write failed: ${e.message}")
        }

        // Strategy 3: App external files Downloads directory
        try {
            val extDownloadDir = applicationContext.getExternalFilesDir(android.os.Environment.DIRECTORY_DOWNLOADS)
            if (extDownloadDir != null) {
                if (!extDownloadDir.exists()) extDownloadDir.mkdirs()
                val targetFile = java.io.File(extDownloadDir, fileName)
                targetFile.writeBytes(dataBytes)
                if (targetFile.exists() && targetFile.length() > 0) {
                    return targetFile.absolutePath
                }
            }
        } catch (_: Exception) {}

        // Strategy 4: App internal files directory
        val internalDir = java.io.File(applicationContext.filesDir, "Download")
        if (!internalDir.exists()) internalDir.mkdirs()
        val targetFile = java.io.File(internalDir, fileName)
        targetFile.writeBytes(dataBytes)
        return targetFile.absolutePath
    }
}
