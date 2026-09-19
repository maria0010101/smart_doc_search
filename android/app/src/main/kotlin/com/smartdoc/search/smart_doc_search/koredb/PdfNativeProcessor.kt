package com.smartdoc.search.smart_doc_search.koredb

import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

/**
 * Native Android PDF Renderer & Layout Processor:
 * Efficiently extracts pages from PDF as high-resolution images
 * using native Android PdfRenderer, without external heavyweight dependencies.
 */
object PdfNativeProcessor {

    fun renderPdfPages(
        context: Context,
        pdfPath: String,
        outputDir: String,
        maxPages: Int = 50
    ): List<Map<String, Any>> {
        val results = mutableListOf<Map<String, Any>>()
        val pdfFile = File(pdfPath)
        if (!pdfFile.exists()) return results

        val outDir = File(outputDir).apply { if (!exists()) mkdirs() }
        var fileDescriptor: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null

        try {
            fileDescriptor = ParcelFileDescriptor.open(pdfFile, ParcelFileDescriptor.MODE_READ_ONLY)
            renderer = PdfRenderer(fileDescriptor)
            val pageCount = minOf(renderer.pageCount, maxPages)

            for (i in 0 until pageCount) {
                val page = renderer.openPage(i)
                // 2x scale for crisp readability on mobile
                val width = page.width * 2
                val height = page.height * 2
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)

                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                page.close()

                val pageImgFile = File(outDir, "page_${i + 1}_${System.currentTimeMillis()}.png")
                FileOutputStream(pageImgFile).use { out ->
                    bitmap.compress(Bitmap.CompressFormat.PNG, 90, out)
                }
                bitmap.recycle()

                val item = mutableMapOf<String, Any>()
                item["pageNumber"] = i + 1
                item["imagePath"] = pageImgFile.absolutePath
                item["width"] = width
                item["height"] = height
                results.add(item)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            try {
                renderer?.close()
                fileDescriptor?.close()
            } catch (ignored: Exception) {}
        }

        return results
    }

    /**
     * Rule-based layout block analyzer per Section FR-02:
     * Analyzes OCR lines and tags them as title, paragraph, table, figure, caption, or footer.
     */
    fun analyzeLayout(text: String): JSONArray {
        val blocks = JSONArray()
        val lines = text.split("\n").map { it.trim() }.filter { it.isNotEmpty() }

        var currentParagraph = StringBuilder()
        var blockIndex = 0

        for (line in lines) {
            val isTitle = line.length < 50 && (
                line.startsWith("#") ||
                line.matches(Regex("^[0-9]+[\\.、].*")) ||
                line.matches(Regex("^[一二三四五六七八九十]+[、].*")) ||
                line.matches(Regex("^(第[0-9]+[章節篇]|CHAPTER|Section).*"))
            )
            val isFooter = line.matches(Regex("^[0-9]+$")) || line.matches(Regex("^- [0-9]+ -$")) || line.contains("Page ")
            val isTable = line.contains("|") || line.contains("\t") || line.matches(Regex(".*\\s{3,}.*"))

            if (isTitle || isFooter || isTable) {
                // Flush paragraph
                if (currentParagraph.isNotEmpty()) {
                    val pBlock = JSONObject()
                    pBlock.put("type", "paragraph")
                    pBlock.put("text", currentParagraph.toString().trim())
                    pBlock.put("bbox", JSONArray(listOf(10, blockIndex * 30, 400, (blockIndex + 1) * 30)))
                    blocks.put(pBlock)
                    currentParagraph.clear()
                    blockIndex++
                }

                val block = JSONObject()
                when {
                    isTitle -> block.put("type", "title")
                    isFooter -> block.put("type", "footer")
                    isTable -> block.put("type", "table")
                }
                block.put("text", line)
                block.put("bbox", JSONArray(listOf(10, blockIndex * 30, 400, (blockIndex + 1) * 30)))
                blocks.put(block)
                blockIndex++
            } else {
                if (currentParagraph.isNotEmpty()) currentParagraph.append("\n")
                currentParagraph.append(line)
            }
        }

        if (currentParagraph.isNotEmpty()) {
            val pBlock = JSONObject()
            pBlock.put("type", "paragraph")
            pBlock.put("text", currentParagraph.toString().trim())
            pBlock.put("bbox", JSONArray(listOf(10, blockIndex * 30, 400, (blockIndex + 1) * 30)))
            blocks.put(pBlock)
        }

        return blocks
    }
}
