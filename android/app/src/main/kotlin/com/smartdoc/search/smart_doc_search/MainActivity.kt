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
                        "openFile" -> {
                            val filePath = call.argument<String>("filePath") ?: ""
                            val file = java.io.File(filePath)
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
                                    filePath.endsWith(".pdf", ignoreCase = true) -> "application/pdf"
                                    filePath.endsWith(".png", ignoreCase = true) -> "image/png"
                                    filePath.endsWith(".jpg", ignoreCase = true) || filePath.endsWith(".jpeg", ignoreCase = true) -> "image/jpeg"
                                    filePath.endsWith(".webp", ignoreCase = true) -> "image/webp"
                                    filePath.endsWith(".txt", ignoreCase = true) -> "text/plain"
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
}
