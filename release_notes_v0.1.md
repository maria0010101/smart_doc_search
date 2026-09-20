## 個人智能文獻檢索 (Smart Document Search) v0.1 發佈摘要

本專案為基於 Flutter 3.47、Kotlin 原生嵌入式 KoreDB 引擎、SQLite 跨平台數據庫與多模型 AI 的個人智能文獻檢索與醫學知識管理系統。

---

### 🌟 核心功能與特色

1. **離線檢索優先與跨平台支援**：
   - 全文檢索（BM25）、多標籤組合檢索（AND/OR）、語義向量相似度搜尋全在本地端進行，無網路亦可離線運作。
   - Android 平台使用嵌入式 KoreDB，Windows / Desktop 平台使用 SQLite 支援同等高效反向索引與混合檢索。
2. **多模型 AI 推理支援**：
   - 支援區域網自架 Ollama（推薦 `qwen2.5:3b`、`llama3.2:3b` 等）。
   - 支援主流雲端 AI API：DeepSeek API、OpenAI GPT API、Anthropic Claude API、Google Gemini API，並支援端側加密保存自訂金鑰。
3. **專業疾病分類與醫學標籤深度辨識**：
   - 支援疾病分類專用模式（ICD-10-CM 診斷代碼、ICD-10-PCS 手術處置代碼、醫學術語、症狀維度）。
   - 標籤依維度階層分類呈現，並具備長標籤雙行自適應與省略防破版設計。
4. **全文條列式重點摘要與精確頁碼定位**：
   - 支援全文條列式核心摘要，英文文獻自動生成繁體中文對照摘要。
   - 摘要自動標註來源頁碼（如 `(P.1)`），點擊即刻跳轉至對應頁面版面。
5. **原生文字直接提取與安全副本管理**：
   - 具文字圖層之 PDF 與純文字檔案直接提取原生文字，無需額外 OCR；無文字圖層則自動呼叫端側高精度 OCR。
   - 匯入文獻自動備份於內部 Documents 目錄，開啟原始檔案時直接以該副本開啟。
6. **自適應平板與桌面主從雙欄佈局 (Master-Detail)**：
   - 手機模式採用 Material 3 響應式單欄設計。
   - 平板與桌面寬螢幕模式自動啟用 Master-Detail 雙欄佈局，提升檢索與文獻查閱效率。
7. **備份與還原機制**：
   - 支援全庫 JSON 導出與導入備份，具備 GZip 壓縮與跨平台相容性。
8. **深色模式 (Dark Theme) 閱讀體驗優化**：
   - 摘要與辨識內文採用深琥珀黑與深黑底色，文字為高對比暖白與極光淺白，大幅提升長時間閱讀舒適度。

---

### 📦 發佈下載附件 (Release Assets)

- **Android APK**: `smart_doc_search-v0.1.apk` (Release 版，支援 Android 8.0+)
- **Windows 11 版本**: 
  - 本專案具備完整 Windows C++ Desktop 專案架構（`windows/` 目錄），可在 Windows 11 主機上直接執行 `flutter build windows --release` 產出執行檔。
  - 亦可於 Windows 平台一鍵打包執行。
