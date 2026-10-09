# v0.1.9 — 跨行搜尋與響應式全文閱讀

- 首頁快捷檢索與檢索頁：Android、桌面 SQLite 與 Dart 備援搜尋統一處理 OCR 的 LF、CRLF、CR 換行，中文跨行詞彙與英文跨行詞句可命中，AND／排除條件亦採用相同規則。
- 文獻清單：搜尋範圍新增 OCR 全文，支援跨行詞句；保留標題、摘要、標籤搜尋與分類、排序功能。
- 文獻詳情：單頁與連續全文區域撐滿可用寬度；OCR 短行重新串接後依視窗寬度自動折行，保留空白行分段。頁內搜尋與高亮同步處理跨行詞句。
- 舊 SQLite 全文索引直接相容，不需重新匯入文獻。全文複製與資料庫中的原始 OCR 內容維持原樣。
- Android 版本為 `0.1.9+10`。

## 驗證與手機安裝

一般環境：

```bash
cd /home/hpd/smart_doc_search
./tool/build_and_install_android.sh
# 多台裝置時可指定序號：./tool/build_and_install_android.sh DEVICE_SERIAL
```

此指令會先執行靜態分析與全套 Flutter 測試、建置 release APK，再以 `adb install -r` 更新手機並啟動程式（保留現有文獻資料）。新 APK 為 `smart_doc_search-v0.1.9.apk`。

新增回歸測試：`test/search_line_breaks_test.dart`。受限於無法開啟本機 socket 的環境，可執行以下補充檢查：

```bash
dart tool/verify_document_text.dart
flutter build bundle --no-pub --target tool/verify_flutter_changes.dart
LD_PRELOAD=/usr/lib/libsqlite3.so /home/hpd/development/flutter/bin/cache/artifacts/engine/linux-x64/flutter_tester --disable-vm-service build/flutter_assets/kernel_blob.bin
```

手機手動確認：

1. 匯入內容包含 `慢性阻塞性\n肺病` 與 `Heart\nfailure` 的 PDF 或文字文獻。
2. 在首頁、文獻清單、檢索頁分別搜尋 `慢性阻塞性肺病`、`heart failure`，確認文獻可找到；AND 與排除條件保持正確。
3. 在文獻詳情搜尋 `heart failure`，確認出現高亮並可定位命中頁。
4. 切換單頁／連續全文、手機直向／橫向，確認文字隨寬度換行。桌面縮放視窗確認全文區域會一起加寬。
5. 複製全文確認原始 OCR 換行仍保留。
