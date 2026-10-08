# 版本 0.1.8 更新說明 (Release Notes)

發布日期：2026-10-08  
版本編號：`v0.1.8` (Build `0.1.8+9`)  
支援平台：Android (APK) & Windows 11 Desktop (64-bit)

---

## 🌟 重大更新項目

### 1. 疾病分類領域文件數據擷取強化 (參考 RapidDoc)
- **結構化臨床實體抽取**：全面強化臨床文獻的主要診斷（Principal Diagnosis）、次要診斷/合併症（Secondary Diagnoses）、醫療處置與處方手術（Procedures）。
- **臨床檢驗指標與數值表格**：精確解析 HbA1c（糖化血色素）、血壓 (BP)、eGFR（腎絲球過濾率）、WBC（白血球）、Creatinine（肌酸酐）、LDL-C 等檢驗項目、數值、單位與臨床參考值/控制目標。
- **標準疾病分類編碼抽取**：支援 ICD-10-CM 與 ICD-10-PCS（嚴格 7 碼手術處置碼）之代碼及對應中文名稱解析。
- **端側啟發式備援**：內建離線正規表達式與啟發式抽取引擎，確保在無網路或 LLM 未輸出特定欄位時仍可完整抓取臨床資訊。
- **視覺化卡片**：於文獻詳情頁面「摘要與標籤」分頁新增「疾病分類與臨床數據結構化擷取 (RapidDoc)」專屬卡片。

### 2. 學術論文元數據抓取 (參考 GraphifyPDF)
- **學術特徵自動抽取**：自動識別論文作者群（Authors）、DOI 數位物件識別碼、出版年份、發表期刊/來源（Journal）與重要參考文獻引用（Citations）。
- **專屬學術卡片**：於文獻詳情頁面呈顯學術元數據，便於學術研究回溯與文獻引用。

### 3. 跨文獻知識網絡與知識圖譜構建 (參考 llm-knowledge-graph)
- **知識三元組抽取**：抽取文獻中的「主體—關係—客體」（Subject-Predicate-Object）三元組關係（如「第2型糖尿病 導致併發 冠狀動脈疾病」）。
- **力導向互動知識圖譜**：
  - 採用力導向彈簧排版演算法（Force-directed spring-embedder layout），在手機與桌面端均自動置中最佳化呈現。
  - 支援雙指手勢縮放、畫布拖曳平移與一鍵視角置中重設。
  - 支援實體類別即時篩選（全部、文獻、疾病/診斷、ICD 編碼、醫學術語、概念）。
  - 點擊任意實體節點可即時彈出相關聯文獻清單，並可一鍵直達文獻詳情。
- **跨文獻關聯推薦 (Cross-Document Related Information)**：
  - 於檢索結果卡片與文獻詳情頁新增「跨文獻關聯推薦」，依共同 ICD 編碼、疾病診斷與三元組鏈結強度，即時推薦具備高度醫學關聯性的其他文獻。

### 4. 單一 LLM 模型一體化處理
- 整合現有配置的 LLM API 金鑰（Ollama / DeepSeek / OpenAI / Claude / Gemini / FastAPI），以單一 JSON Prompt 一併產製條列式摘要、多維標籤、RapidDoc 臨床數據、GraphifyPDF 學術元數據與圖譜三元組，完全免除多模型伺服器配置負擔。

---

## 🛠️ 下載與安裝

- **Android 裝置**：下載 `smart_doc_search-v0.1.8.apk` 直接安裝更新。
- **Windows 11 桌面端**：下載 `smart_doc_search-windows-v0.1.8.zip`，解壓縮後執行 `smart_doc_search.exe` 即可使用。
