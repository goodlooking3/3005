# تقرير التدقيق التقني المحايد — Wasel / واصل

**المستودع:** `yemenfast/wasll23.09.2026`  
**الفرع:** `main`  
**مرجع التدقيق:** `cb9fc2784a7be2dc76c9b30a9259e9220e014fe2`  
**تاريخ التدقيق:** 27 سبتمبر 2026  
**نطاق التدقيق:** المصدر المنشور، البنية، المجال المحاسبي، SQLite، الأمن المحلي، الموصلات، CI/CD المعلن، وثائق الإغلاق، وحالة Android/Windows.  
**طبيعة التدقيق:** مراجعة مصدرية عن بُعد؛ لم أعتبر أي Runtime أو تثبيت جهاز ناجحًا إلا إذا كان موثقًا في المستودع.

## 1. تأكيد الوصول

تم الوصول فعليًا إلى المستودع الخاص عبر حساب GitHub المرتبط بالمشروع.

صلاحيات الوصول التي أعادها GitHub:
- admin
- maintain
- push
- pull
- triage

الفرع الافتراضي: `main`.

آخر commit مفحوص:
`cb9fc2784a7be2dc76c9b30a9259e9220e014fe2` — `fix: support older android versions`.

## 2. الخلاصة التنفيذية

المشروع تجاوز مرحلة النموذج الأولي البصري بوضوح. توجد قاعدة بيانات SQLite، طبقة مستودعات، محاسبة وسندات، محافظ، موصلات، نسخ احتياطي مشفر، مصادقة محلية، تدقيق، مزامنة، وبوابات بناء موثقة.

لكن المشروع **لم يصل بعد إلى إغلاق إنتاجي كامل**. أهم أسباب ذلك ليست غياب البناء؛ بل الفصل بين:

1. نجاح البناء المحلي/الآلي.
2. اكتمال المسارات المرئية والتفاعلية.
3. اعتماد تكاملات الإنتاج الحقيقية.
4. توقيع Android الإنتاجي.
5. اختبار أجهزة حقيقية.
6. الحوكمة التشغيلية والمراقبة بعد الإصدار.

التقييم الحالي المقترح، بوصفه تقديرًا هندسيًا لا نتيجة اختبار آلي:

| المحور | التقدير | الحكم |
|---|---:|---|
| اكتمال البنية الأساسية | 78% | متقدم |
| اكتمال المجال والبيانات | 72% | متقدم لكن يحتاج توحيدًا |
| التكاملات الفعلية | 45% | غير مكتملة إنتاجيًا |
| جودة الواجهات والمسارات | 60% | عملية جزئيًا وليست مكتملة كمنتج |
| الأمن المحلي والنسخ الاحتياطي | 68% | جيد كأساس، يحتاج تشديد إنتاجي |
| البناء المحلي/الموثق | 82% | قوي |
| الإطلاق الإنتاجي | 45% | غير مغلق |
| الإغلاق الكلي | 55% | لم يصل إلى Release Closure |
| **الإنجاز الهندسي الكلي** | **حوالي 68%** | مرحلة متقدمة قبل الإغلاق |

هذه النسب ليست قياس تغطية اختبار، ولا تعني أن 68% من الأسطر مكتملة؛ إنها تقدير لحالة المنتج مقارنة بمتطلبات منصة قابلة للنشر.

## 3. ما تم إنجازه فعليًا

### 3.1 البنية
- Flutter متعدد المنصات مع Android وWindows.
- فصل نسبي بين core/data/services/features.
- SQLite محلي.
- Repository layer للمحاسبة والبيانات.
- Connector abstraction.
- إعدادات إنتاج ومحلي.
- نظام تصميم وواجهة RTL.

### 3.2 المحاسبة
المصدر يحتوي على:
- Account.
- AccountKind.
- Voucher / VoucherLine.
- Party.
- CompanyProfile.
- FinancialSummary.
- Journal entries.
- العملات وأسعار الصرف.
- ربط الحسابات بالمحافظ.
- قيود على الحسابات غير الموجودة أو غير النشطة بحسب سجل التطوير.
- دعم العملات على مستوى سطر السند.
- دورة حياة موحدة لعمليات المحفظة.
- منع التكرار لبعض العمليات بالاعتماد على مرجع المصدر.

هذا يمثل أساسًا محاسبيًا حقيقيًا نسبيًا، وليس مجرد شاشات.

### 3.3 قاعدة البيانات
يوجد مسار SQLite مع:
- معاملات transaction.
- audit log.
- sync queue.
- connector configurations.
- bank sandbox transactions.
- incoming messages.
- journal entries.
- remittances.
- vouchers/accounts.

كما تم توثيق إصلاحات تتعلق بالأقفال، الذرية، التكرار، وترحيل الإصدارات.

### 3.4 الأمن والنسخ الاحتياطي
تم العثور على:
- تجزئة كلمات المرور محليًا.
- local_auth للبصمة.
- flutter_secure_storage.
- AES-GCM للنسخ الاحتياطي.
- استعادة transactionally.
- فحص نسخة backup قبل الاستعادة.
- عدم إبقاء مواد التوقيع المؤقتة في المستودع بحسب الوثائق.

لكن ذلك لا يساوي بعد نظام أمن إنتاجي كامل.

## 4. حالة البناء

آخر إصلاح رفع حد توافق Android من API 31 إلى حد Flutter الفعلي API 24.

وثيقة commit الأخير تسجل:
- Flutter 3.47.5.
- Dart 3.13.4.
- Android SDK 36.
- JDK 21.
- target SDK 36.
- Universal APK موثق.
- حذف مواد التوقيع المؤقتة.

كما توثق السجلات السابقة نجاح:
- Flutter quality gate في مرحلة سابقة.
- Local Android build.
- Windows build.
- Windows installer.

**الحكم:** قدرة البناء قوية نسبيًا، لكن هذا لا يساوي Release Production.

السبب الحاسم: الـAPK الموثق محليًا كان بتوقيع مؤقت وغير إنتاجي، بينما الإغلاق النهائي يتطلب keystore مؤسسيًا، تحققًا من التوقيع، وتثبيتًا واختبارًا على جهاز حقيقي.

## 5. حالة الإغلاق

الإغلاق الحالي يجب تصنيفه:

**Source / Engineering Closure: جزئي**  
**Build Closure: متقدم**  
**Product Closure: غير مكتمل**  
**Production Closure: غير مغلق**

الفجوات التي تمنع الإغلاق الكامل:
1. اختبار قبول Android حقيقي.
2. اختبار Windows حقيقي.
3. تحقق كامل من RTL والصلاحيات والإشعارات.
4. اختبار SQLite والترقية من إصدارات أقدم.
5. اختبار PDF/File Picker/Backup.
6. إكمال التفاعلات التي كانت موثقة سابقًا كفجوات.
7. ربط التكاملات الإنتاجية الحقيقية بدل sandbox/configured-only.
8. توقيع Android إنتاجي.
9. تثبيت هوية التطبيق النهائية وapplication ID النهائي إن لم يكن قد اعتمد بعد.
10. مراقبة الأعطال والصحة التشغيلية.
11. سياسة بيانات واحتفاظ وخصوصية مرتبطة ببيانات الإشعارات.

## 6. ملاحظات معمارية مهمة

### 6.1 إيجابي
الانتقال من شاشة واحدة إلى features وservices وrepositories خطوة صحيحة.

### 6.2 الخطر الرئيسي
ما زالت بعض المسؤوليات مركزة في طبقات قديمة، ويظهر ذلك في كبر بعض الملفات وفي اعتماد أجزاء من التطبيق على `AccountingRepository` و`LocalDatabase` كطبقات واسعة.

المطلوب في النسخة العالمية هو الانتقال تدريجيًا إلى:

`Presentation → Application → Domain → Infrastructure → Database`

مع عقود واضحة بين الطبقات، وليس فقط تقسيم الملفات.

### 6.3 نموذج المحاسبة
استخدام `double` للمبالغ المالية موجود في النماذج الحالية. هذا مناسب لبعض الواجهات لكنه ليس أفضل أساس لمنصة مالية عالمية.

المسار المستهدف:
- integer minor units أو Decimal domain type.
- currency precision policy.
- exchange-rate value object.
- rounding policy.
- posting invariants.
- immutable journal entries.
- reversal بدل التعديل المباشر بعد الترحيل.

## 7. الموصلات والتكاملات

يوجد عقد `ConnectorAdapter`، وهذه نقطة معمارية جيدة.

لكن العقد الحالي بسيط:

- connect
- disconnect
- testConnection
- status

ولمنصة عالمية يلزم توسيعه ليشمل:
- capability discovery.
- authentication lifecycle.
- token rotation.
- webhook verification.
- idempotency key.
- cursor-based sync.
- retry policy.
- exponential backoff.
- rate limits.
- conflict resolution.
- dead-letter queue.
- health state.
- observability.
- audit correlation ID.

والأهم: عدم الخلط بين:
**Configured Connector**
و
**Live Production Integration**.

## 8. الأمن — نقاط يجب رفعها قبل الإنتاج

النسخ الاحتياطي المشفر جيد كأساس، لكن مفتاح النسخة الاحتياطية محفوظ محليًا على الجهاز نفسه. هذا يجعل النموذج مناسبًا للنسخة المحلية، وليس وحده نموذجًا لاستعادة آمنة بين أجهزة أو مؤسسة.

المطلوب عالميًا:
- device-bound key.
- key rotation.
- recovery mechanism.
- encrypted export with explicit user passphrase.
- secure deletion policy.
- redaction مركزي.
- threat model.
- security event log.
- session lifecycle.
- brute-force protection.
- secure production signing.
- dependency vulnerability scanning.

## 9. خطة الإكمال — World-Class Platform Track

### GATE A — Foundation Lock
**الهدف:** تثبيت العقود قبل إضافة وظائف جديدة.

- Domain contracts.
- Money/Decimal.
- Currency.
- Tenant/Company identity.
- Repository contracts.
- Error model.
- ID strategy.
- Audit correlation ID.
- Migration policy.
- Offline-first policy.

**مخرج البوابة:** Architecture Baseline v1.

### GATE B — Accounting Core
- Chart of Accounts.
- Journal.
- Voucher lifecycle.
- Posting engine.
- Reversal.
- Period close.
- Multi-currency.
- Exchange-rate history.
- Trial balance.
- General ledger.
- Receivables/Payables.
- Audit trail.

**مخرج البوابة:** Accounting Core Production Candidate.

### GATE C — Operational Domains
بالترتيب:
1. Company / Tenant.
2. Wallet.
3. Remittance.
4. Parties.
5. Bank.
6. Sales.
7. Purchases.
8. Inventory.
9. Expenses.
10. Reports.

كل وحدة تمر:
**Domain → Application → Infrastructure → Presentation → Database → Manual Verify → Push → GitHub Source Verification**

### GATE D — Integration Platform
إنشاء Integration SDK داخلي:
- Connector SDK.
- OAuth/token vault.
- Webhook gateway.
- Idempotency.
- Sync cursor.
- Retry/backoff.
- DLQ.
- conflict engine.
- connector health.
- observability.

ثم:
- WhatsApp Business Platform.
- SMS.
- Webhook.
- Bank APIs.
- Email عند الحاجة.

### GATE E — Security & Compliance
- Threat model.
- Secrets management.
- Production keystore.
- SBOM.
- dependency audit.
- static analysis.
- secure logging.
- privacy policy.
- data retention.
- export/delete policy.
- backup recovery drills.

### GATE F — Platform Operations
- Crash reporting.
- health checks.
- structured logs.
- metrics.
- audit correlation.
- remote diagnostics دون تسريب البيانات.
- feature flags.
- controlled migrations.
- rollback strategy.

### GATE G — Device Acceptance
Android:
- install.
- upgrade.
- notification access.
- permissions.
- biometric.
- SQLite.
- backup/restore.
- PDF.
- file picker.
- offline mode.
- low storage.
- process death/restart.

Windows:
- install.
- upgrade.
- uninstall.
- restart.
- SQLite.
- PDF.
- backup.
- file picker.
- long-running session.

### GATE H — Release Engineering
لا يُعلن الإصدار إلا مع:
- immutable release commit.
- signed artifacts.
- SHA-256.
- SBOM.
- provenance.
- release notes.
- migration notes.
- rollback plan.
- acceptance report.
- known issues.
- versioned database schema.

## 10. ترتيب الأولويات المقترح

**P0 — لا تضف وحدات جديدة قبل إغلاقها**
1. Money/Decimal.
2. Production signing.
3. Device acceptance.
4. Database migration/restore verification.
5. Authentication/session hardening.

**P1**
6. Accounting posting engine.
7. Audit/correlation.
8. Connector SDK.
9. Sync/idempotency/conflict.

**P2**
10. Complete Wallet/Remittance UI.
11. Reports.
12. Sales/Purchases/Inventory.

**P3**
13. Production integrations.
14. Observability.
15. SBOM/security automation.

**P4**
16. Release Candidate.
17. Upgrade test.
18. Disaster recovery drill.
19. Production launch.

## 11. ما لا ينبغي فعله الآن

- لا تضف عشرات الشاشات قبل تثبيت domain contracts.
- لا تعتبر Sandbox connector تكاملًا إنتاجيًا.
- لا تعتبر APK غير موقع إنتاجيًا Release.
- لا تستخدم نجاح CI وحده كدليل قبول المنتج.
- لا تجعل `LocalDatabase` طبقة معرفة بكل المجالات إلى أجل غير محدود.
- لا توسع المزامنة قبل تثبيت idempotency وconflict semantics.
- لا تستخدم `double` كأساس نهائي لمحرك مالي عالمي.
- لا تخلط بين إغلاق المصدر وإغلاق المنتج.

## 12. النتيجة النهائية

**Wasel ليس مشروعًا فارغًا أو مجرد UI prototype.** يحتوي على أساس تطبيقي ومحاسبي وبيانات وأمن محلي وبناء متعدد المنصات بدرجة نضج واضحة.

وفي المقابل، **لا توجد في الأدلة المصدرية التي راجعتها أسباب كافية لإعلان Production Closure كامل حتى الآن**.

المرحلة الصحيحة التالية ليست إعادة بناء المشروع من الصفر؛ بل تنفيذ **Closure-to-Platform Program** يحافظ على الموجود، يثبت العقود المالية، يفصل البنية القديمة تدريجيًا، يحول الموصلات إلى منصة تكامل حقيقية، ثم يغلق اختبارات الأجهزة والتوقيع والإصدار.

**تقدير الوضع الحالي:**
- Engineering maturity: **متقدم**
- Build maturity: **متقدم**
- Product maturity: **متوسط/متقدم**
- Production readiness: **متوسط**
- Final closure: **غير مغلق**
- تقدير الإنجاز الكلي: **حوالي 68%**

هذا التقييم مصدرّي ومحايد، ولا يساوي نتيجة اختبار Runtime مستقل.

---
**مراجع المصدر داخل المستودع:** README، pubspec، main.dart، models، accounting repository، connector service/adapter، auth service، secure backup service، session progress، production closure، independent production readiness audit، وملفات GitHub Actions.
