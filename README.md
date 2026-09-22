# 個人智能文獻檢索 (Smart Document Search) v0.1.5

基於 Flutter + Kotlin 原生橋接、嵌入式 KoreDB 引擎、SQLite 跨平台引擎與多模型雲端 / 地端 AI 的個人智能文獻檢索系統（支援 Android 與 Windows 11）。

---

## 專案亮點與特點

1. **離線檢索優先與跨平台支援**：
   - 所有的查詢檢索（BM25 全文關鍵字檢索、多標籤 AND/OR 組合、語義向量相似度搜尋）全在端側本地進行，無網路環境亦可完整離線查詢。
   - Android 原生使用嵌入式 KoreDB，Windows / Desktop 平台使用 SQLite 支援同等高效反向索引與全文檢索。
2. **檢索定位直達：優先呈現文獻內容與命中頁面**：
   - 檢索結果點選文獻開啟詳情時，優先呈現第一分頁「文獻內容」，自動切換至檢索結果呈現之頁數頁面，省去手動翻頁步驟。
   - 支援分頁版面影像縮放、OCR 全文辨識、結構化區塊與連續全文模式；條列式 AI 摘要與標籤內文改為第二分頁。
3. **文獻管理專屬分頁與首頁快捷導航**：
   - 首頁旁新增「文獻」分頁，可完整檢視所有已匯入文獻，支援文獻名稱即時更名與刪除作業。
   - 首頁儀表板「文獻總數」按鈕與最近文獻「查看全部」一鍵跳轉至文獻清單分頁。
   - 底部導航欄簡化聚焦（首頁、文獻、檢索、AI分析、標籤、設定），匯入功能由首頁「匯入新文獻」按鈕進入。
4. **多模型 AI 推理與雲端/地端自由切換**：
   - 支援呼叫地端 Ollama 服務（如 `qwen2.5:3b`、`llama3.2:3b` 等）。
   - 內建 DeepSeek API、OpenAI GPT API、Anthropic Claude API、Google Gemini API 等主流 AI 雲端模型選用與自訂金鑰支援。
5. **專業疾病分類與醫學標籤深度辨識**：
   - 支援疾病分類專用模式（ICD-10-CM 診斷編碼、ICD-10-PCS 手術處置代碼、醫學術語、症狀維度）。
   - 標籤依維度層次化呈現，支援超長標籤雙行自適應與省略防破版。
6. **全文條列式重點摘要與精確頁碼定位**：
   - 以全文內容進行條列式核心摘要，英文文獻自動提供高品質繁體中文對照摘要。
   - 摘要自動附帶來源頁碼（如 `(P.1)`），支援一鍵跳轉至對應頁面版面。
7. **原生文字直接提取與文件安全副本存儲**：
   - 具文字圖層之 PDF 與純文字文件直接提取原生文字，無需額外 OCR；無文字圖層則自動呼叫端側高精度 OCR。
   - 匯入文獻自動於內部 Documents 資料夾存放副本，確保本機原始檔案可隨時直接開啟檢閱。
8. **自適應平板與桌面主從雙欄佈局 (Master-Detail)**：
   - 手機模式採用 Material 3 響應式單欄設計。
   - 平板與桌面模式自動切換為雙欄主從導航架構，左側即時瀏覽清單，右側同步載入文獻詳情與頁面版面。
9. **備份與還原機制**：
   - 支援全庫 JSON 導出與導入備份，具備 GZip 壓縮與跨平台相容性。

---

## 技術架構

| 層級 | 實作方案 | 說明 |
|:---|:---|:---|
| 前端框架 | Flutter 3.47 (Dart 3.13) | Material 3 響應式介面，支援深色模式 |
| 原生橋接 | Kotlin + MethodChannel | `com.smartdoc.search/koredb` 與 `com.smartdoc.search/native_tools` |
| 本地核心資料庫 | KoreDB Native Store (Kotlin) | 支援文件 CRUD、頁面管理、反向標籤索引、BM25 全文索引、向量餘弦檢索 |
| 文件渲染 | Android Native `PdfRenderer` | 高解析度將 PDF 頁面轉為清晰預覽圖像 |
| 網路通訊 | Dio (HTTP Client) | 呼叫區域網 Ollama (`/api/chat`, `/api/embeddings`) 或 FastAPI |
| 狀態管理與數據庫封裝 | Repository Pattern + Clean Architecture | 徹底解耦 UI、Domain 與 Native Data Sources |

---

## 快速建置與執行

### 執行單元測試
```bash
flutter test
```

### 建置 Debug APK
```bash
flutter build apk --debug
```

### 建置 Release APK
```bash
flutter build apk --release
```

產出 APK 位置：
- Release APK: `/home/hpd/下載/smart_doc_search-release.apk` (54.7 MB)
- 原始建置目錄: `/home/hpd/AndroidStudioProjects/smart_doc_search/build/app/outputs/flutter-apk/app-release.apk`

---

## 目錄結構說明

```text
smart_doc_search/
├── android/
│   └── app/src/main/kotlin/com/smartdoc/search/smart_doc_search/
│       ├── MainActivity.kt               # MethodChannel 事件分發與橋接
│       └── koredb/
│           ├── KoreDBNativeStore.kt      # KoreDB 原生嵌入式資料庫與向量/BM25檢索
│           └── PdfNativeProcessor.kt     # 原生 PDF 渲染與版面分析器
├── lib/
│   ├── main.dart                         # 主應用程式入口與底部導覽
│   ├── core/
│   │   ├── constants/app_constants.dart  # 全域常數、Ollama 模型與標籤維度
│   │   ├── theme/app_theme.dart          # Material 3 深淺主題與分類顏色
│   │   └── utils/
│   │       ├── hash_util.dart            # SHA-256 雜湊查重計算
│   │       └── text_normalizer.dart      # 全半形轉換、同義詞映射與標籤清洗
│   ├── data/
│   │   ├── datasources/
│   │   │   ├── koredb_datasource.dart    # KoreDB MethodChannel 與純 Dart 雙向容災
│   │   │   └── ollama_client.dart        # Ollama API & FastAPI 客戶端與重試
│   │   ├── models/document_model.dart    # Document, PageItem, TagItem, SearchQuery
│   │   └── repositories/
│   │       └── document_repository.dart  # 資料倉儲模式封裝
│   └── features/
│       ├── home/home_screen.dart         # 儀表板、統計數據、最近文獻
│       ├── search/                       # 混合檢索介面與服務
│       ├── import/                       # 批次匯入、進度追蹤
│       ├── document/                     # 文獻詳情、OCR 全文檢視、標籤審核
│       ├── tags/                         # 標籤列表、合併、別名
│       └── settings/                     # Ollama 連線測試、模型選用、備份還原
└── test/
    ├── unit_test.dart                    # SHA-256、正規化、資料模型、混合檢索單元測試
    └── widget_test.dart                  # UI Widget 冒煙測試與導覽驗證
```
