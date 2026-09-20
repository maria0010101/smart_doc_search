package com.smartdoc.search.smart_doc_search.koredb

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.locks.ReentrantReadWriteLock
import kotlin.concurrent.read
import kotlin.concurrent.write
import kotlin.math.sqrt

/**
 * KoreDB Native Embedded Engine:
 * Implements document storage, inverted tag indexing, BM25 text ranking,
 * and high-performance SIMD-friendly vector similarity search.
 */
class KoreDBNativeStore(private val context: Context) {

    private val dbDir: File by lazy {
        File(context.filesDir, "koredb").apply { if (!exists()) mkdirs() }
    }
    private val docsFile: File by lazy { File(dbDir, "documents.json") }
    private val pagesFile: File by lazy { File(dbDir, "pages.json") }
    private val tagsFile: File by lazy { File(dbDir, "tags.json") }

    private val lock = ReentrantReadWriteLock()

    // In-memory indexes
    private val documents = ConcurrentHashMap<String, JSONObject>()
    private val pages = ConcurrentHashMap<String, MutableList<JSONObject>>() // docId -> pages
    private val tagInvertedIndex = ConcurrentHashMap<String, MutableSet<String>>() // tagName -> docIds
    private val tagMetadata = ConcurrentHashMap<String, JSONObject>() // tagId -> tagJson
    private val vectorEmbeddings = ConcurrentHashMap<String, FloatArray>() // docId -> embedding

    init {
        loadFromDisk()
    }

    private fun loadFromDisk() = lock.write {
        try {
            if (docsFile.exists()) {
                val content = docsFile.readText()
                if (content.isNotBlank()) {
                    val arr = JSONArray(content)
                    for (i in 0 until arr.length()) {
                        val doc = arr.getJSONObject(i)
                        val id = doc.getString("id")
                        documents[id] = doc

                        // Cache embedding if exists
                        if (doc.has("embedding") && !doc.isNull("embedding")) {
                            val embArr = doc.getJSONArray("embedding")
                            val floats = FloatArray(embArr.length()) { idx -> embArr.getDouble(idx).toFloat() }
                            if (floats.isNotEmpty()) {
                                vectorEmbeddings[id] = floats
                            }
                        }

                        // Index tags
                        if (doc.has("tags")) {
                            val tags = doc.getJSONArray("tags")
                            for (t in 0 until tags.length()) {
                                val tagObj = tags.getJSONObject(t)
                                val tagName = tagObj.optString("name", "").trim().lowercase()
                                if (tagName.isNotEmpty()) {
                                    tagInvertedIndex.computeIfAbsent(tagName) { mutableSetOf() }.add(id)
                                }
                            }
                        }
                    }
                }
            }

            if (pagesFile.exists()) {
                val content = pagesFile.readText()
                if (content.isNotBlank()) {
                    val arr = JSONArray(content)
                    for (i in 0 until arr.length()) {
                        val page = arr.getJSONObject(i)
                        val docId = page.getString("documentId")
                        pages.computeIfAbsent(docId) { mutableListOf() }.add(page)
                    }
                }
            }

            if (tagsFile.exists()) {
                val content = tagsFile.readText()
                if (content.isNotBlank()) {
                    val arr = JSONArray(content)
                    for (i in 0 until arr.length()) {
                        val tagObj = arr.getJSONObject(i)
                        val id = tagObj.getString("id")
                        tagMetadata[id] = tagObj
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun persistDocuments() {
        val arr = JSONArray()
        documents.values.forEach { arr.put(it) }
        atomicWrite(docsFile, arr.toString(2))
    }

    private fun persistPages() {
        val arr = JSONArray()
        pages.values.flatten().forEach { arr.put(it) }
        atomicWrite(pagesFile, arr.toString(2))
    }

    private fun persistTags() {
        val arr = JSONArray()
        tagMetadata.values.forEach { arr.put(it) }
        atomicWrite(tagsFile, arr.toString(2))
    }

    private fun atomicWrite(file: File, content: String) {
        val tempFile = File(file.parentFile, "${file.name}.tmp")
        FileOutputStream(tempFile).use { it.write(content.toByteArray(Charsets.UTF_8)) }
        if (tempFile.exists()) {
            if (file.exists()) file.delete()
            tempFile.renameTo(file)
        }
    }

    fun insertDocument(docJsonStr: String): String = lock.write {
        val doc = JSONObject(docJsonStr)
        val id = doc.optString("id", java.util.UUID.randomUUID().toString())
        doc.put("id", id)
        if (!doc.has("createdAt")) doc.put("createdAt", System.currentTimeMillis())
        doc.put("updatedAt", System.currentTimeMillis())

        documents[id] = doc

        // Vector
        if (doc.has("embedding") && !doc.isNull("embedding")) {
            val embArr = doc.getJSONArray("embedding")
            val floats = FloatArray(embArr.length()) { idx -> embArr.getDouble(idx).toFloat() }
            if (floats.isNotEmpty()) {
                vectorEmbeddings[id] = floats
            }
        }

        // Tags
        rebuildDocTagIndex(id, doc)

        persistDocuments()
        id
    }

    fun updateDocument(docJsonStr: String): Boolean = lock.write {
        val doc = JSONObject(docJsonStr)
        val id = doc.optString("id")
        if (id.isEmpty() || !documents.containsKey(id)) return@write false

        doc.put("updatedAt", System.currentTimeMillis())
        documents[id] = doc

        // Vector
        if (doc.has("embedding") && !doc.isNull("embedding")) {
            val embArr = doc.getJSONArray("embedding")
            val floats = FloatArray(embArr.length()) { idx -> embArr.getDouble(idx).toFloat() }
            if (floats.isNotEmpty()) {
                vectorEmbeddings[id] = floats
            }
        } else {
            vectorEmbeddings.remove(id)
        }

        rebuildDocTagIndex(id, doc)
        persistDocuments()
        true
    }

    fun deleteDocument(id: String): Boolean = lock.write {
        if (!documents.containsKey(id)) return@write false

        documents.remove(id)
        pages.remove(id)
        vectorEmbeddings.remove(id)

        // Remove from tag index
        tagInvertedIndex.values.forEach { it.remove(id) }

        persistDocuments()
        persistPages()
        true
    }

    fun getDocument(id: String): String? = lock.read {
        documents[id]?.toString()
    }

    fun getAllDocuments(): String = lock.read {
        val arr = JSONArray()
        documents.values.forEach { arr.put(it) }
        arr.toString()
    }

    fun insertPage(pageJsonStr: String): String = lock.write {
        val page = JSONObject(pageJsonStr)
        val id = page.optString("id", java.util.UUID.randomUUID().toString())
        page.put("id", id)
        val docId = page.getString("documentId")

        val list = pages.computeIfAbsent(docId) { mutableListOf() }
        list.removeAll { it.optString("id") == id }
        list.add(page)

        persistPages()
        id
    }

    fun getPages(documentId: String): String = lock.read {
        val list = pages[documentId] ?: emptyList<JSONObject>()
        val arr = JSONArray()
        list.forEach { arr.put(it) }
        arr.toString()
    }

    private fun rebuildDocTagIndex(docId: String, doc: JSONObject) {
        // Remove old occurrences
        tagInvertedIndex.values.forEach { it.remove(docId) }

        if (doc.has("tags")) {
            val tags = doc.getJSONArray("tags")
            for (t in 0 until tags.length()) {
                val tagObj = tags.getJSONObject(t)
                val tagName = tagObj.optString("name", "").trim().lowercase()
                if (tagName.isNotEmpty()) {
                    tagInvertedIndex.computeIfAbsent(tagName) { mutableSetOf() }.add(docId)

                    // Track in tagMetadata (ensure uniqueness by tag name)
                    val tagId = tagObj.optString("id", java.util.UUID.randomUUID().toString())
                    val existingTag = tagMetadata.values.find {
                        it.optString("name", "").trim().equals(tagName, ignoreCase = true)
                    }
                    if (existingTag == null) {
                        tagObj.put("id", tagId)
                        tagMetadata[tagId] = tagObj
                    } else {
                        if (existingTag.optString("code_system").isEmpty() && tagObj.has("code_system")) {
                            existingTag.put("code_system", tagObj.optString("code_system"))
                        }
                    }
                }
            }
        }
        persistTags()
    }

    fun queryByTags(tags: List<String>, mode: String = "AND"): String = lock.read {
        if (tags.isEmpty()) {
            return@read getAllDocuments()
        }

        val normalized = tags.map { it.trim().lowercase() }.filter { it.isNotEmpty() }
        if (normalized.isEmpty()) {
            return@read getAllDocuments()
        }

        val matchedDocIds = if (mode.equals("OR", ignoreCase = true)) {
            val union = mutableSetOf<String>()
            for (t in normalized) {
                tagInvertedIndex[t]?.let { union.addAll(it) }
            }
            union
        } else {
            // AND
            var intersection: MutableSet<String>? = null
            for (t in normalized) {
                val set = tagInvertedIndex[t] ?: emptySet()
                if (intersection == null) {
                    intersection = set.toMutableSet()
                } else {
                    intersection.retainAll(set)
                }
            }
            intersection ?: emptySet()
        }

        val resultArr = JSONArray()
        matchedDocIds.forEach { id ->
            documents[id]?.let { resultArr.put(it) }
        }
        resultArr.toString()
    }

    /**
     * High-speed Cosine Similarity Vector Search
     */
    fun vectorSearch(targetEmbedding: FloatArray, topK: Int = 10): List<Pair<String, Float>> = lock.read {
        if (targetEmbedding.isEmpty() || vectorEmbeddings.isEmpty()) return emptyList()

        val results = mutableListOf<Pair<String, Float>>()
        val targetNorm = calculateNorm(targetEmbedding)
        if (targetNorm == 0f) return emptyList()

        for ((docId, emb) in vectorEmbeddings) {
            val sim = cosineSimilarity(targetEmbedding, targetNorm, emb)
            if (sim > 0.001f) {
                results.add(Pair(docId, sim))
            }
        }

        results.sortByDescending { it.second }
        results.take(topK)
    }

    private fun cosineSimilarity(v1: FloatArray, v1Norm: Float, v2: FloatArray): Float {
        val len = minOf(v1.size, v2.size)
        var dot = 0f
        var norm2Sq = 0f
        for (i in 0 until len) {
            dot += v1[i] * v2[i]
            norm2Sq += v2[i] * v2[i]
        }
        val v2Norm = sqrt(norm2Sq)
        if (v1Norm == 0f || v2Norm == 0f) return 0f
        return dot / (v1Norm * v2Norm)
    }

    private fun calculateNorm(v: FloatArray): Float {
        var sum = 0f
        for (x in v) sum += x * x
        return sqrt(sum)
    }

    /**
     * BM25 Fulltext Keyword Match Score
     */
    fun bm25Score(docText: String, terms: List<String>): Float {
        if (terms.isEmpty() || docText.isBlank()) return 0f
        val lowerText = docText.lowercase()
        var score = 0f
        for (term in terms) {
            val lowerTerm = term.lowercase().trim()
            if (lowerTerm.isEmpty()) continue
            // Simple term frequency calculation
            var count = 0
            var idx = 0
            while (true) {
                val found = lowerText.indexOf(lowerTerm, idx)
                if (found == -1) break
                count++
                idx = found + lowerTerm.length
            }
            if (count > 0) {
                val k1 = 1.2f
                val b = 0.75f
                val tf = count.toFloat()
                // BM25 term weighting
                val termScore = (tf * (k1 + 1f)) / (tf + k1 * (1f - b + b * (docText.length / 500f)))
                score += termScore
            }
        }
        return score
    }

    /**
     * Hybrid Search combining:
     * - w1 (0.4) * Keyword BM25 score
     * - w2 (0.4) * Vector cosine similarity
     * - w3 (0.2) * Tag match ratio
     */
    fun hybridSearch(
        keywords: List<String>,
        tags: List<String>,
        tagMode: String = "AND",
        semanticEmbedding: FloatArray? = null,
        limit: Int = 20,
        offset: Int = 0
    ): JSONObject = lock.read {
        val startTime = System.currentTimeMillis()

        // 1. Filter candidates by tags if tags are specified
        val candidateDocIds = if (tags.isNotEmpty()) {
            val tagMatchDocArr = JSONArray(queryByTags(tags, tagMode))
            val set = mutableSetOf<String>()
            for (i in 0 until tagMatchDocArr.length()) {
                set.add(tagMatchDocArr.getJSONObject(i).getString("id"))
            }
            set
        } else {
            documents.keys.toMutableSet()
        }

        // 2. Vector search scores
        val vectorScores = mutableMapOf<String, Float>()
        if (semanticEmbedding != null && semanticEmbedding.isNotEmpty()) {
            val vectorHits = vectorSearch(semanticEmbedding, topK = documents.size.coerceAtLeast(10))
            for ((docId, sim) in vectorHits) {
                vectorScores[docId] = sim
            }
        }

        // 3. Compute score for each candidate
        val w1 = 0.4f // keyword
        val w2 = 0.4f // vector
        val w3 = 0.2f // tags

        val scoredResults = mutableListOf<JSONObject>()

        for (docId in candidateDocIds) {
            val doc = documents[docId] ?: continue

            // Fulltext searchable string (title + summary + OCR text of all pages)
            val title = doc.optString("title", "")
            val summary = doc.optString("summary", "")
            val pageTexts = pages[docId]?.joinToString(" ") { it.optString("ocrText", "") } ?: ""
            val fullText = "$title $summary $pageTexts"

            // Keyword score
            val kwScore = if (keywords.isNotEmpty()) bm25Score(fullText, keywords) else 0f

            // Vector score
            val vecScore = vectorScores[docId] ?: 0f

            // Tag score
            var tagScore = 0f
            val matchedTagsList = mutableListOf<String>()
            if (tags.isNotEmpty() && doc.has("tags")) {
                val docTags = doc.getJSONArray("tags")
                var matchCount = 0
                for (t in 0 until docTags.length()) {
                    val docTagName = docTags.getJSONObject(t).optString("name", "").trim().lowercase()
                    for (queryTag in tags) {
                        if (docTagName.equals(queryTag.trim().lowercase(), ignoreCase = true)) {
                            matchCount++
                            matchedTagsList.add(queryTag)
                        }
                    }
                }
                tagScore = matchCount.toFloat() / tags.size.toFloat()
            }

            // Combined hybrid score
            val totalScore = if (keywords.isEmpty() && semanticEmbedding == null && tags.isEmpty()) {
                1.0f // All docs
            } else {
                (w1 * kwScore) + (w2 * vecScore) + (w3 * tagScore)
            }

            // Build highlight snippet if keyword matched
            var highlightSnippet: String? = null
            if (keywords.isNotEmpty()) {
                for (kw in keywords) {
                    val idx = fullText.indexOf(kw, ignoreCase = true)
                    if (idx != -1) {
                        val start = maxOf(0, idx - 40)
                        val end = minOf(fullText.length, idx + kw.length + 40)
                        highlightSnippet = "..." + fullText.substring(start, end).trim() + "..."
                        break
                    }
                }
            }

            val hitObj = JSONObject()
            hitObj.put("document", doc)
            hitObj.put("score", totalScore.toDouble())
            hitObj.put("highlight", highlightSnippet)
            hitObj.put("matchedTags", JSONArray(matchedTagsList))
            scoredResults.add(hitObj)
        }

        scoredResults.sortByDescending { it.getDouble("score") }

        val total = scoredResults.size
        val pagedList = scoredResults.drop(offset).take(limit)

        val response = JSONObject()
        response.put("items", JSONArray(pagedList))
        response.put("total", total)
        response.put("tookMs", System.currentTimeMillis() - startTime)
        response
    }

    fun getAllTags(): String = lock.read {
        val arr = JSONArray()
        // Compute real usage counts
        val usageCounts = mutableMapOf<String, Int>()
        for (doc in documents.values) {
            if (doc.has("tags")) {
                val tags = doc.getJSONArray("tags")
                for (t in 0 until tags.length()) {
                    val tagName = tags.getJSONObject(t).optString("name", "").trim().lowercase()
                    if (tagName.isNotEmpty()) {
                        usageCounts[tagName] = (usageCounts[tagName] ?: 0) + 1
                    }
                }
            }
        }

        for (tag in tagMetadata.values) {
            val name = tag.optString("name", "").trim().lowercase()
            tag.put("usageCount", usageCounts[name] ?: 0)
            arr.put(tag)
        }
        arr.toString()
    }

    fun updateTag(tagJsonStr: String): Boolean = lock.write {
        val tagObj = JSONObject(tagJsonStr)
        val id = tagObj.optString("id")
        if (id.isEmpty()) return@write false
        tagMetadata[id] = tagObj
        persistTags()
        true
    }

    fun deleteTag(tagId: String): Boolean = lock.write {
        val removed = tagMetadata.remove(tagId) ?: return@write false
        val removedName = removed.optString("name", "").trim().lowercase()
        tagInvertedIndex.remove(removedName)

        // Also remove tag from documents
        for (doc in documents.values) {
            if (doc.has("tags")) {
                val tags = doc.getJSONArray("tags")
                val newTags = JSONArray()
                for (t in 0 until tags.length()) {
                    val tObj = tags.getJSONObject(t)
                    if (tObj.optString("name", "").trim().lowercase() != removedName) {
                        newTags.put(tObj)
                    }
                }
                doc.put("tags", newTags)
            }
        }
        persistDocuments()
        persistTags()
        true
    }

    fun getStats(): JSONObject = lock.read {
        val stats = JSONObject()
        stats.put("documentCount", documents.size)
        stats.put("pageCount", pages.values.sumOf { it.size })
        val uniqueTagCount = tagMetadata.values.map { it.optString("name", "").trim().lowercase() }.filter { it.isNotEmpty() }.distinct().size
        stats.put("tagCount", uniqueTagCount)
        stats.put("vectorCount", vectorEmbeddings.size)

        var totalSize = 0L
        if (docsFile.exists()) totalSize += docsFile.length()
        if (pagesFile.exists()) totalSize += pagesFile.length()
        if (tagsFile.exists()) totalSize += tagsFile.length()
        stats.put("storageBytes", totalSize)
        stats
    }

    fun exportBackup(): String = lock.read {
        val root = JSONObject()
        val docsArr = JSONArray()
        documents.values.forEach { docsArr.put(it) }
        val pagesArr = JSONArray()
        pages.values.flatten().forEach { pagesArr.put(it) }
        val tagsArr = JSONArray()
        val exportedNames = mutableSetOf<String>()
        tagMetadata.values.forEach { tag ->
            val n = tag.optString("name", "").trim().lowercase()
            if (n.isNotEmpty() && !exportedNames.contains(n)) {
                exportedNames.add(n)
                tagsArr.put(tag)
            }
        }

        root.put("version", "2.0")
        root.put("timestamp", System.currentTimeMillis())
        root.put("documents", docsArr)
        root.put("pages", pagesArr)
        root.put("tags", tagsArr)
        root.toString(2)
    }

    fun restoreBackup(backupJson: String): Boolean = lock.write {
        try {
            val root = JSONObject(backupJson)
            documents.clear()
            pages.clear()
            tagInvertedIndex.clear()
            tagMetadata.clear()
            vectorEmbeddings.clear()

            if (root.has("documents") && !root.isNull("documents")) {
                val arr = root.getJSONArray("documents")
                for (i in 0 until arr.length()) {
                    val doc = arr.getJSONObject(i)
                    val id = doc.getString("id")
                    documents[id] = doc

                    if (doc.has("embedding") && !doc.isNull("embedding")) {
                        val embArr = doc.getJSONArray("embedding")
                        val floats = FloatArray(embArr.length()) { idx -> embArr.getDouble(idx).toFloat() }
                        if (floats.isNotEmpty()) {
                            vectorEmbeddings[id] = floats
                        }
                    }

                    if (doc.has("tags") && !doc.isNull("tags")) {
                        val tags = doc.getJSONArray("tags")
                        for (t in 0 until tags.length()) {
                            val tagName = tags.getJSONObject(t).optString("name", "").trim().lowercase()
                            if (tagName.isNotEmpty()) {
                                tagInvertedIndex.computeIfAbsent(tagName) { mutableSetOf() }.add(id)
                            }
                        }
                    }
                }
            }

            if (root.has("pages") && !root.isNull("pages")) {
                val arr = root.getJSONArray("pages")
                for (i in 0 until arr.length()) {
                    val p = arr.getJSONObject(i)
                    val docId = p.getString("documentId")
                    pages.computeIfAbsent(docId) { mutableListOf() }.add(p)
                }
            }

            if (root.has("tags") && !root.isNull("tags")) {
                val arr = root.getJSONArray("tags")
                val restoredNames = mutableSetOf<String>()
                for (i in 0 until arr.length()) {
                    val t = arr.getJSONObject(i)
                    val n = t.optString("name", "").trim().lowercase()
                    if (n.isNotEmpty() && !restoredNames.contains(n)) {
                        restoredNames.add(n)
                        tagMetadata[t.optString("id", java.util.UUID.randomUUID().toString())] = t
                    }
                }
            }

            persistDocuments()
            persistPages()
            persistTags()
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    fun clearAll(): Boolean = lock.write {
        documents.clear()
        pages.clear()
        tagInvertedIndex.clear()
        tagMetadata.clear()
        vectorEmbeddings.clear()
        if (docsFile.exists()) docsFile.delete()
        if (pagesFile.exists()) pagesFile.delete()
        if (tagsFile.exists()) tagsFile.delete()
        true
    }
}
