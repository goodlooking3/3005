# تقرير الاختبارات النهائية وخطة إصدار واصل

**تاريخ التقرير:** 19 سبتمبر 2026

## 1. الحكم التنفيذي

نجح المشروع في جميع الفحوصات الآلية التي يمكن تنفيذها داخل بيئة Flutter/Linux الحالية. كما ثبت أن جميع الشاشات الرئيسية تُبنى وتصل إلى طبقات البيانات، وأن جميع التخزين التشغيلي يمر عبر SQLite الموحدة `wasel.db`.

لا يمكن إعلان **10/10 نهائية** أو جاهزية إطلاق كاملة قبل تنفيذ الفحص البصري الفعلي على Windows وAndroid حقيقيين. الاختبار البصري المنفذ حاليًا هو اختبار دخان Flutter يتحقق من إنشاء الشاشة وتحميلها الأولي دون استثناءات، وليس مقارنة صور أو تشغيلًا على جهاز مادي. التقييم الحالي هو **8.5/10 للجاهزية البرمجية داخل البيئة**، وتبقى بوابة الجهاز الحقيقي مفتوحة.

## 2. نتائج الاختبارات النهائية

| الفحص | الأمر أو الدليل | النتيجة |
|---|---|---|
| حارس طول الملفات | `dart run tool/check_file_lengths.dart` | ناجح |
| حارس ربط الشاشات | `dart run tool/check_screen_bindings.dart` | ناجح |
| حارس SQLite الموحدة | `dart run tool/check_sqlite_singleton.dart` | ناجح |
| التحليل الساكن | `flutter analyze --no-fatal-infos` | ناجح دون أخطاء مترجم؛ 18 ملاحظة تحسين غير مانعة |
| الاختبارات الكاملة | `flutter test --concurrency=1` | ناجح، exit code 0 |
| اختبار PDF العربي | `test/credit_note_export_test.dart` | ناجح مع خط Amiri مضمن |
| اختبار SQLite والأداء | `test/sqlite_performance_test.dart` | ناجح داخل اتصال `LocalDatabase` الموحد |
| اختبار دخان الشاشات | `test/screen_smoke_test.dart` | ناجح |
| حالة Git | فرع `main` | متزامن مع `origin/main` |

يضم المشروع **12 ملف اختبار** تغطي الموصلات، المحاسبة، المبيعات، المخزون، المشتريات، المحفظة، الرسائل، PDF، SQLite، وتدخين الشاشات.

## 3. مصفوفة الشاشات والتحقق الحالي

| الشاشة | ربط البيانات | العمليات المرئية | التحقق المتاح الآن | ما يلزم على الجهاز |
|---|---|---|---|---|
| لوحة المبيعات | `SalesEngine` وSQLite | فتح إضافة صنف، حركات، مرتجعات | اختبار دخان وتحليل ربط | قياس بصري على أحجام مختلفة |
| إضافة منتج | `InventoryLocalDb` وSQLite | حقول الصنف والسعر والتكلفة والكمية والحفظ | مراجعة الكود والتحليل | إدخال فعلي والتحقق من رسائل الخطأ |
| حركات المخزون | `SalesEngine` وSQLite | تحديث، بحث/تصفية حسب المسار الحالي | اختبار تكامل للحركات | فحص التمرير وRTL على جهاز |
| المردودات | `SalesEngine` وSQLite | فتح التفاصيل، كميات، زيادة/إنقاص، ترحيل، إلغاء | اختبارات البيع والمرتجع | اختبار اللمس والكيبورد والطباعة |
| السوق والمشتريات | `LocalVendorsDb` و`PurchaseEngine` وSQLite | تصنيف، مورد، إضافة للسلة، checkout | اختبار دخان وتكامل الشراء | التحقق من الشبكة والفراغ والـ checkout |
| التقارير المحاسبية | `AccountingReportsController` وSQLite | يومية، تدقيق، بحث، تحديث | اختبار دخان وتقارير | فحص RTL وتصدير وطباعة |
| مركز الموصلات | `ConnectorCenterController` وSQLite | تحديث، اختيار، رسائل، أرشفة، ترحيل | اختبار دخان ورسائل | استقبال إشعار Android فعلي |
| المحفظة | `WalletProvider` وSQLite | تحديث، تحويل، فلاتر، استيراد | اختبار دخان واختبارات المجال | اختبار الملفات والصلاحيات |
| شاشة الغلاف `VendorStoreScreen` | Wrapper تنقل | فتح `MarketplaceScreen` | مراجعة بنيوية | فحص انتقال بصري |

**الاستنتاج:** لا توجد شاشة أعمال رئيسية مثبتة كواجهة عرض فقط. المدقق الآلي يرفض شاشة بلا مصدر بيانات أو بلا تفاعل. لكن هذا لا يثبت وحده جودة التخطيط البصري أو سهولة الاستخدام على جهاز حقيقي.

## 4. حالة التحقق البصري

### ما تم إثباته

تم تمرير جميع الشاشات الرئيسية عبر Flutter test binding. تحقق الاختبار من إنشاء الواجهات، تشغيل التحميل الأولي، وعدم وقوع استثناءات. كما تم التحقق من وجود معالجات للأزرار والحقول والفلاتر، ومن عدم وجود مؤشرات `TODO` أو `placeholder` غير مغلقة.

### ما لم يُنفذ بعد

لم يتم أخذ golden screenshots أو تشغيل التطبيق على نافذة Windows فعلية أو شاشة Android فعلية. لذلك لم يُثبت بعد ما يلي:

- عدم وجود overflow عند أحجام Windows المختلفة.
- صحة RTL على شاشة هاتف حقيقية.
- وضوح الخطوط والأرقام العربية في كل الشاشات.
- سلامة لوحة المفاتيح واللمس.
- شكل dialogs والـ snackbars على الجهاز.
- الطباعة والمشاركة وفتح الملفات خارج بيئة الاختبار.
- صلاحيات الإشعارات والملفات والبصمة.

## 5. خطة التشغيل والبناء النهائية على Windows

### المتطلبات

يجب استخدام Windows 10 أو Windows 11 بنظام 64-bit، مع Flutter stable مطابق للإصدار المثبت في المشروع، Visual Studio مع workload **Desktop development with C++**، Windows SDK، وInno Setup.

### بوابة ما قبل البناء

على جهاز Windows، ينفذ الفريق:

```powershell
flutter doctor -v
flutter pub get
dart run tool/check_file_lengths.dart
dart run tool/check_screen_bindings.dart
dart run tool/check_sqlite_singleton.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --concurrency=1
```

لا يبدأ البناء إذا فشل أي أمر من هذه الأوامر.

### البناء المحلي

```powershell
flutter config --enable-windows-desktop
flutter build windows --release --dart-define=WASEL_LOCAL_ONLY=true
```

بعد البناء:

1. ضغط `build/windows/x64/runner/Release` إلى ZIP.
2. حساب SHA-256.
3. بناء مثبت Inno Setup عبر `windows/wasel.iss`.
4. حساب SHA-256 للمثبت.
5. تثبيت التطبيق في مسار جديد.
6. تشغيله وإنشاء قاعدة SQLite جديدة.
7. تنفيذ شراء وبيع ومرتجع وتحويل محفظة.
8. تصدير PDF وExcel وفتح الملفات الناتجة.
9. إغلاق التطبيق وفتحه والتحقق من استمرار `wasel.db`.
10. اختبار الترقية من نسخة سابقة، ثم الإزالة وإعادة التثبيت.

### معيار قبول Windows

يُقبل البناء إذا نجح التثبيت والتشغيل والترقية، ولم يظهر overflow أو crash، وحُفظت البيانات بعد إعادة التشغيل، ونجح PDF وExcel، وطابق SHA-256 artifact، ولم تُسجل أسرار أو بيانات مالية حساسة في logs.

## 6. خطة التشغيل والبناء النهائية على Android

### المتطلبات

يجب استخدام Android 12 أو أحدث، ويفضل اختبار جهاز منخفض ومتوسط المواصفات. يجب تفعيل USB debugging، تثبيت Android SDK وplatform tools، وتوفير توقيع release محفوظ خارج المستودع.

### بوابة ما قبل البناء

```bash
flutter doctor -v
flutter pub get
dart run tool/check_file_lengths.dart
dart run tool/check_screen_bindings.dart
dart run tool/check_sqlite_singleton.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --concurrency=1
```

### البناء

للاختبار المحلي:

```bash
flutter build apk --release \
  --target-platform android-arm64 \
  --dart-define=WASEL_LOCAL_ONLY=true
```

للإصدار الموقّع، تُستخدم إعدادات signing الآمنة في Gradle أو CI، ولا تُحفظ كلمات المرور أو ملفات keystore في Git.

### قائمة الاختبار اليدوي

1. تثبيت APK وتشغيله لأول مرة.
2. إنشاء الملف التعريفي وتسجيل الدخول والخروج.
3. إنشاء صنف ومورد وحساب ومحفظة.
4. تنفيذ شراء ثم بيع ثم مرتجع جزئي وكامل.
5. التحقق من توازن القيود وتحديث كمية المخزون.
6. فتح التقارير والبحث والتصفية والتحديث.
7. تصدير PDF عربي وExcel ومشاركتهما.
8. إنشاء backup مشفر واستعادته على profile نظيف.
9. تفعيل Notification Access يدويًا.
10. إرسال إشعار اختبار من التطبيقات المدعومة.
11. التحقق من وصول payload المنقح إلى Flutter وSQLite.
12. اختبار إشعار فارغ أو بلا مبلغ أو بعملة غير معروفة.
13. اختبار إيقاف الشبكة وإعادتها والتأكد من بقاء queue.
14. اختبار البصمة، الإشعارات، قفل الشاشة، وإعادة تشغيل الهاتف.
15. مراجعة `adb logcat` بحثًا عن token أو بيانات مالية حساسة.

### معيار قبول Android

يُقبل APK إذا نجحت دورة الأعمال كاملة، وبقيت البيانات بعد إعادة التشغيل، ونجحت الصلاحيات والإشعارات والنسخ والاستعادة، ولم يحدث crash أو فقد بيانات أو تكرار ترحيل، وكانت الواجهات سليمة في RTL وعلى لوحة المفاتيح واللمس.

## 7. بوابات الإصدار والتراجع

يجب إنشاء Release Candidate من commit محدد فقط. تحفظ artifacts مع checksum. لا يُنشر APK أو Windows installer قبل توقيع محضر قبول الجهازين. إذا فشل أي اختبار ميداني، يُعاد الإصدار إلى آخر commit مقبول، وتُفتح ملاحظة إصلاح، ولا تُعطل بوابة CI لتجاوز الفشل.

تم تشديد workflow البناء بحيث لا تستمر عملية البناء عند فشل التحليل أو الاختبارات أو حواجز طول الملفات وربط الشاشات وSQLite. ويظل البناء النهائي مؤجلًا حتى تتوفر أجهزة Windows وAndroid الحقيقية.

## 8. قرار الجاهزية الحالي

| المجال | القرار |
|---|---|
| جودة Dart وFlutter | جاهز للبوابة الميدانية |
| SQLite الموحدة | مغلقة ومثبتة آليًا |
| الشاشات والربط الوظيفي | جاهزة لاختبار الجهاز |
| التحقق البصري الفعلي | غير مكتمل دون جهاز حقيقي |
| Windows release | لم يُنفذ بعد |
| Android release | لم يُنفذ بعد |
| إعلان 10/10 النهائي | مؤجل حتى اجتياز Windows وAndroid |

## المراجع

[1]: https://docs.flutter.dev/testing "Flutter testing documentation"
[2]: https://docs.flutter.dev/platform-integration/windows/building "Flutter Windows build documentation"
[3]: https://docs.flutter.dev/deployment/android "Flutter Android deployment documentation"
[4]: https://developer.android.com/reference/android/service/notification/NotificationListenerService "Android notification listener documentation"
[5]: https://github.com/alialjowfi/wasll12.11.2026 "مستودع مشروع واصل"
