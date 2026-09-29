# دليل بناء نسخ المتاجر — Clippify (STORE_BUILD)

> آخر تحديث: 2026-08-24 — وكيل AGENT-E3
> الحالة: **إعداد المتجر جاهز جزئياً** — البناء مُعطَّل حالياً بأخطاء Dart في `lib/` (انظر §المعوّقات).

---

## 1) ما تم إنجازه

| البند | الحالة |
|---|---|
| أيقونة التطبيق `assets/icon/icon.png` (1024×1024) | ✅ مولّدة عبر `scripts/make_icon.ps1` (تدرّج #7C3AED→#4F46E5 + حرف C أبيض + مثلث تشغيل) |
| أيقونات Android (mipmap + adaptive) و iOS | ✅ 31 ملف Android + 21 ملف iOS عبر `flutter_launcher_icons` |
| `applicationId` = `com.clippify.app` | ✅ `android/app/build.gradle.kts` |
| `minSdk 24` / compileSdk+targetSdk 36 (من Flutter SDK، ≥34) | ✅ |
| إذن `INTERNET` + `android:label="Clippify"` | ✅ `AndroidManifest.xml` |
| iOS: `CFBundleDisplayName`، أذونات الصور، `ITSAppUsesNonExemptEncryption=false` | ✅ `ios/Runner/Info.plist` |
| Bundle ID iOS = `com.clippify.app` | ✅ `project.pbxproj` (6 أسطر) |
| Splash (`#0B0B10` + الأيقونة + android12) | ✅ `flutter_native_splash:create` |

## 2) قائمة فحص Google Play Console

1. **حساب المطوّر**: ⚠️ *placeholder* — يلزم حساب Google Play مفعّل (رسوم 25$ لمرة واحدة) وربطه بمعرّف التطبيق النهائي.
2. **مفتاح التوقيع** (مرة واحدة):
   ```powershell
   keytool -genkey -v -keystore android\app\clippify-release.jks `
     -keyalg RSA -keysize 2048 -validity 10000 -alias clippify `
     -storepass <STORE_PASS> -keypass <KEY_PASS>
   ```
   - أنشئ `android/key.properties` (لا ترفعه إلى git):
     ```properties
     storePassword=<STORE_PASS>
     keyPassword=<KEY_PASS>
     keyAlias=clippify
     storeFile=../app/clippify-release.jks
     ```
   - ثم استبدل `signingConfig = signingConfigs.getByName("debug")` في `android/app/build.gradle.kts` بإعداد يقرأ `key.properties`.
   - احتفظ بنسخة احتياطية من `.jks` — فقدانها = فقدان تحديثات التطبيق نهائياً.
3. **بناء AAB**:
   ```powershell
   flutter build appbundle --release --build-number=<versionCode>
   # المخرج: build\app\outputs\bundle\release\app-release.aab
   ```
4. **اختبار AAB على جهاز** (اختياري):
   ```powershell
   # من أداة bundletool (حمّلها من GitHub الرسمي)
   java -jar bundletool.jar build-apks --bundle=build\app\outputs\bundle\release\app-release.aab --output=clippify.apks --ks=android\app\clippify-release.jks --ks-key-alias=clippify
   java -jar bundletool.jar install-apks --apks=clippify.apks
   ```
5. **رفع الإصدار**: Play Console → Testing → Internal testing → إنشاء إصدار جديد → رفع `.aab`.
6. **بيانات المتجر**: الاسم "Clippify"، الوصف، لقطات شاشة، أيقونة 512×512، سياسة خصوصية (إلزامية).

## 3) قائمة فحص TestFlight (iOS)

1. **حساب Apple Developer**: ⚠️ *placeholder* — يلزم حساب (99$/سنة).
2. **التوقيع** يتم من Xcode: Signing & Capabilities → Team + Provisioning Profile تلقائي. لا تُعدّل ملفات التوقيع يدوياً.
3. **البناء** (يتطلب macOS):
   ```bash
   flutter build ipa --release --build-number=<CFBundleVersion>
   # المخرج: build/ios/ipa/clippify.ipa
   ```
4. **الرفع**: عبر Xcode → Organizer → Distribute App → App Store Connect، أو:
   ```bash
   xcrun altool --upload-app -f build/ios/ipa/clippify.ipa -u <apple-id> -p <app-specific-password>
   ```
5. **TestFlight**: App Store Connect → TestFlight → معالجة البناء → إضافة المختبرين.
6. ملاحظة: أذونات الصور (`NSPhotoLibrary*`) مضافة بالفعل — قد تسأل Apple عن سبب الاستخدام عند المراجعة.

## 4) سياسة رفع `versionCode`

- المصدر الوحيد: سطر `version: 1.0.0+1` في `pubspec.yaml`.
- **الرقم بعد `+` هو versionCode/CFBundleVersion** — يجب أن يزداد +1 مع كل رفع للمتجر، دون إعادة استخدام رقم قديم.
- الاسم قبل `+` هو versionName/CFBundleShortVersionString (semver: major.minor.patch).
- يمكن تجاوزه مؤقتاً عند البناء: `flutter build appbundle --build-number=2`.

## 5) ما لا يزال placeholder

| البند | التفاصيل |
|---|---|
| حساب Play Console حقيقي | غير مرتبط — `com.clippify.app` محجوز محلياً فقط |
| حساب Apple Developer | غير موجود — التوقيع iOS لم يُجرَّب |
| `key.properties` + `.jks` | غير مُنشأين (عمداً — لا تُرفع للمستودع) |
| توقيع release في gradle | ما زال debug keys (سطر 32 في `build.gradle.kts`) |
| `MainActivity.kt` لا يزال في حزمة `com.example.flutter_client` | مقبول (namespace ≠ applicationId)؛ النقل اختياري ويتطلب تحديث `namespace` + مسار الملف معاً |

## 6) معوّقات حالية (Blockers)

`flutter build apk --debug` يفشل حالياً في مرحلة `kernel_snapshot` بسبب 4 أخطاء Dart موجودة مسبقاً في `lib/` (خارج نطاق هذا الوكيل — يملكها وكلاء آخرون):

1. `lib/features/layout/widgets/settings_modal.dart:387` — `WidgetStatePropertyAll<BorderSide>` لا يُسند إلى `BorderSide?` (الحل: إزالة `WidgetStatePropertyAll` أو استخدام `side:` من النوع الصحيح).
2. `lib/features/layout/widgets/settings_modal.dart:713` — `BorderSide` لا يُسند إلى `WidgetStateProperty<BorderSide?>?` (الحل: `side: const WidgetStatePropertyAll(BorderSide(...))`).
3. `lib/features/results/auto_edit_results_screen.dart:416` و `:468` — `context` غير معرّف.

بعد إصلاحها أعد التشغيل: `flutter build apk --debug`.

## 7) ملفات هذا الإعداد

- `scripts/make_icon.ps1` — مولّد الأيقونة (إعادة التوليد عند تغيير الهوية البصرية).
- `pubspec.yaml` — كتل `flutter_launcher_icons` و `flutter_native_splash` في نهاية الملف (append-only).
- بعد أي تعديل على الأيقونة/السبلاش: `dart run flutter_launcher_icons` ثم `dart run flutter_native_splash:create`.
