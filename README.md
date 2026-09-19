# 個人智能文獻檢索 (Smart Document Search) Android APK

基於 Flutter + Kotlin 原生橋接、嵌入式 KoreDB 引擎與區域網 Ollama API 的個人智能文獻檢索 Android 應用程式。

---

## 專案亮點與特點

1. **離線檢索優先**：
   - 所有的查詢檢索（BM25 全文關鍵字檢索、多標籤 AND/OR 組合、語義向量相似度搜尋）全在手機端本地進行，無網路環境亦可完整離線查詢。
2. **高效端側 KoreDB 引擎**：
   - Kotlin 原生嵌入式 LSM/文件/圖/向量存儲引擎。
   - 具備反向索引（Inverted Index）、快速標籤倒排查表與向量餘弦相似度計算。
3. **區域網 Ollama API 智能標籤生成**：
   - 支援呼叫 PC 端的 Ollama 服務（推薦 `qwen2.5:3b`、`llama3.2:3b` 等）。
   - 支援九大維度結構化標籤生成（主題、領域、方法、對象、結論、文檔類型、語言、年份、作者/機構）。
   - 具備自動格式校驗、JSON 清洗與最多 3 次智能重試機制。
   - 支援可選的 FastAPI 中間層 (`/generate-tags`, `/embed`)。
4. **多格式文件匯入與 SHA-256 查重**：
   - 支援 PDF、圖片（JPG、PNG、WebP）、PPT 批量匯入。
   - 原生 PDF 頁面渲染與版面區塊分析（Title, Paragraph, Table, Figure, Footer）。
   - 自動計算 SHA-256 雜湊碼，防止重複匯入。
5. **混合檢索 (Hybrid Search)**：
   - 結合關鍵字 BM25 分數 (0.4) + 語義向量餘弦相似度 (0.4) + 標籤匹配度 (0.2)。
   - 支援關鍵字搜尋高亮展示、文件格式與日期範圍篩選、多維度排序。
6. **人工審核與標籤管理**：
   - 標籤分類歸納、引用次數統計、審核狀態切換（已驗證/待審核）。
   - 支援新增、編輯、刪除、同義詞別名設定與標籤合併（Tag Merging）。
7. **備份與還原**：
   - 支援 KoreDB 全庫 JSON 導出與導入備份。

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
