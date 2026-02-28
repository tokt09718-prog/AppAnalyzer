#!/bin/bash
set -e

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   🚀 AppAnalyzer - بناء تلقائي كامل     ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ══════════════════════════════════════
#  الجزء 1: إنشاء هيكل المشروع
# ══════════════════════════════════════
echo "📁 [1/5] إنشاء هيكل المشروع..."

mkdir -p app/src/main/java/com/appanalyzer
mkdir -p app/src/main/res/layout
mkdir -p app/src/main/res/values
mkdir -p app/src/main/res/mipmap-hdpi
mkdir -p gradle/wrapper

# ══════════════════════════════════════
#  الجزء 2: كتابة ملفات الكود
# ══════════════════════════════════════
echo "✍️  [2/5] كتابة ملفات الكود..."

# ── AndroidManifest.xml ──
cat > app/src/main/AndroidManifest.xml << 'MANIFEST'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools"
    package="com.appanalyzer">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.PACKAGE_USAGE_STATS" tools:ignore="ProtectedPermissions"/>
    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES" />

    <application
        android:allowBackup="true"
        android:label="AppAnalyzer"
        android:supportsRtl="true"
        android:theme="@style/AppTheme">

        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <activity android:name=".AppDetailActivity" android:exported="false"/>

    </application>
</manifest>
MANIFEST

# ── AppInfo.kt ──
cat > app/src/main/java/com/appanalyzer/AppInfo.kt << 'APPINFO'
package com.appanalyzer

import android.graphics.drawable.Drawable

data class AppInfo(
    val name: String,
    val packageName: String,
    val icon: Drawable,
    val isSystem: Boolean,
    val permissions: List<String>,
    val sentBytes: Long,
    val receivedBytes: Long,
    val riskLevel: Int
) {
    val riskLabel: String get() = when {
        riskLevel >= 70 -> "خطر عالي"
        riskLevel >= 40 -> "خطر متوسط"
        riskLevel >= 10 -> "خطر منخفض"
        else            -> "آمن"
    }

    val riskColor: String get() = when {
        riskLevel >= 70 -> "#FF4444"
        riskLevel >= 40 -> "#FFAA00"
        else            -> "#44BB44"
    }

    fun formattedBytes(bytes: Long): String = when {
        bytes >= 1_000_000_000 -> "%.1f GB".format(bytes / 1_000_000_000.0)
        bytes >= 1_000_000     -> "%.1f MB".format(bytes / 1_000_000.0)
        bytes >= 1_000         -> "%.1f KB".format(bytes / 1_000.0)
        else                   -> "$bytes B"
    }
}
APPINFO

# ── MainActivity.kt ──
cat > app/src/main/java/com/appanalyzer/MainActivity.kt << 'MAIN'
package com.appanalyzer

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.TrafficStats
import android.os.Bundle
import android.provider.Settings
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView

class MainActivity : AppCompatActivity() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var progressBar: ProgressBar
    private lateinit var searchView: SearchView
    private lateinit var adapter: AppAdapter
    private val appList = mutableListOf<AppInfo>()
    private val filteredList = mutableListOf<AppInfo>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        recyclerView = findViewById(R.id.recyclerView)
        progressBar = findViewById(R.id.progressBar)
        searchView = findViewById(R.id.searchView)

        if (!hasUsageStatsPermission()) {
            Toast.makeText(this, "يرجى منح صلاحية مراقبة الاستخدام", Toast.LENGTH_LONG).show()
            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
        }

        adapter = AppAdapter(filteredList) {
            val intent = Intent(this, AppDetailActivity::class.java)
            intent.putExtra("packageName", it.packageName)
            startActivity(intent)
        }

        recyclerView.layoutManager = LinearLayoutManager(this)
        recyclerView.adapter = adapter

        searchView.setOnQueryTextListener(object : SearchView.OnQueryTextListener {
            override fun onQueryTextSubmit(query: String?) = false
            override fun onQueryTextChange(newText: String?): Boolean {
                filterApps(newText ?: ""); return true
            }
        })

        loadApps()
    }

    private fun hasUsageStatsPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun loadApps() {
        progressBar.visibility = View.VISIBLE
        Thread {
            val pm = packageManager
            val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
            for (app in apps) {
                val permissions = try {
                    pm.getPackageInfo(app.packageName, PackageManager.GET_PERMISSIONS).requestedPermissions?.toList() ?: emptyList()
                } catch (e: Exception) { emptyList() }

                val sent = TrafficStats.getUidTxBytes(app.uid).let { if (it == TrafficStats.UNSUPPORTED.toLong()) 0L else it }
                val recv = TrafficStats.getUidRxBytes(app.uid).let { if (it == TrafficStats.UNSUPPORTED.toLong()) 0L else it }

                val dangerousPerms = listOf("READ_CONTACTS","READ_SMS","SEND_SMS","CAMERA","RECORD_AUDIO","ACCESS_FINE_LOCATION","READ_CALL_LOG","READ_PHONE_STATE","WRITE_EXTERNAL_STORAGE","RECEIVE_SMS")
                var risk = permissions.count { p -> dangerousPerms.any { d -> p.contains(d) } } * 8
                val total = sent + recv
                risk += when { total > 500_000_000 -> 30; total > 100_000_000 -> 15; total > 10_000_000 -> 5; else -> 0 }

                appList.add(AppInfo(
                    name = pm.getApplicationLabel(app).toString(),
                    packageName = app.packageName,
                    icon = pm.getApplicationIcon(app),
                    isSystem = (app.flags and ApplicationInfo.FLAG_SYSTEM) != 0,
                    permissions = permissions,
                    sentBytes = sent,
                    receivedBytes = recv,
                    riskLevel = risk.coerceIn(0, 100)
                ))
            }
            appList.sortByDescending { it.riskLevel }
            filteredList.addAll(appList)
            runOnUiThread { progressBar.visibility = View.GONE; adapter.notifyDataSetChanged() }
        }.start()
    }

    private fun filterApps(query: String) {
        filteredList.clear()
        filteredList.addAll(if (query.isEmpty()) appList else appList.filter { it.name.contains(query, true) || it.packageName.contains(query, true) })
        adapter.notifyDataSetChanged()
    }
}
MAIN

# ── AppAdapter.kt ──
cat > app/src/main/java/com/appanalyzer/AppAdapter.kt << 'ADAPTER'
package com.appanalyzer

import android.graphics.Color
import android.view.*
import android.widget.*
import androidx.recyclerview.widget.RecyclerView

class AppAdapter(private val apps: List<AppInfo>, private val onClick: (AppInfo) -> Unit) :
    RecyclerView.Adapter<AppAdapter.VH>() {

    inner class VH(v: View) : RecyclerView.ViewHolder(v) {
        val icon: ImageView = v.findViewById(R.id.appIcon)
        val name: TextView = v.findViewById(R.id.appName)
        val pkg: TextView = v.findViewById(R.id.appPackage)
        val risk: TextView = v.findViewById(R.id.riskLabel)
        val riskBar: ProgressBar = v.findViewById(R.id.riskBar)
        val net: TextView = v.findViewById(R.id.networkUsage)
        val perms: TextView = v.findViewById(R.id.permCount)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
        VH(LayoutInflater.from(parent.context).inflate(R.layout.item_app, parent, false))

    override fun onBindViewHolder(h: VH, pos: Int) {
        val app = apps[pos]
        h.icon.setImageDrawable(app.icon)
        h.name.text = app.name
        h.pkg.text = app.packageName
        h.risk.text = app.riskLabel
        h.risk.setTextColor(Color.parseColor(app.riskColor))
        h.riskBar.progress = app.riskLevel
        h.net.text = "↑${app.formattedBytes(app.sentBytes)} ↓${app.formattedBytes(app.receivedBytes)}"
        h.perms.text = "${app.permissions.size} صلاحية"
        h.itemView.setOnClickListener { onClick(app) }
    }

    override fun getItemCount() = apps.size
}
ADAPTER

# ── AppDetailActivity.kt ──
cat > app/src/main/java/com/appanalyzer/AppDetailActivity.kt << 'DETAIL'
package com.appanalyzer

import android.content.pm.*
import android.graphics.Color
import android.net.TrafficStats
import android.os.Bundle
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import java.text.SimpleDateFormat
import java.util.*

class AppDetailActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_app_detail)

        val packageName = intent.getStringExtra("packageName") ?: return
        try {
            val pm = packageManager
            val pi = pm.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
            val ai = pm.getApplicationInfo(packageName, 0)
            val fmt = SimpleDateFormat("yyyy/MM/dd", Locale.getDefault())

            findViewById<ImageView>(R.id.detailIcon).setImageDrawable(pm.getApplicationIcon(ai))
            findViewById<TextView>(R.id.detailName).text = pm.getApplicationLabel(ai).toString()
            findViewById<TextView>(R.id.detailPackage).text = packageName
            findViewById<TextView>(R.id.detailVersion).text = "الإصدار: ${pi.versionName}"
            findViewById<TextView>(R.id.detailInstall).text = "التثبيت: ${fmt.format(Date(pi.firstInstallTime))}"
            findViewById<TextView>(R.id.detailUpdate).text = "التحديث: ${fmt.format(Date(pi.lastUpdateTime))}"

            val layout = findViewById<LinearLayout>(R.id.permissionsLayout)
            val dangerous = mapOf(
                "READ_CONTACTS" to "📒 قراءة جهات الاتصال",
                "READ_SMS" to "💬 قراءة الرسائل",
                "SEND_SMS" to "📤 إرسال الرسائل",
                "CAMERA" to "📷 الكاميرا",
                "RECORD_AUDIO" to "🎙️ تسجيل الصوت",
                "ACCESS_FINE_LOCATION" to "📍 الموقع الدقيق",
                "READ_CALL_LOG" to "📞 سجل المكالمات",
                "READ_PHONE_STATE" to "📱 معلومات الهاتف",
                "WRITE_EXTERNAL_STORAGE" to "💾 التخزين",
                "GET_ACCOUNTS" to "👤 الحسابات"
            )

            val perms = pi.requestedPermissions ?: emptyArray()
            var dangerCount = 0
            for (p in perms) {
                val short = p.substringAfterLast(".")
                val desc = dangerous[short]
                if (desc != null) dangerCount++
                layout.addView(TextView(this).apply {
                    text = if (desc != null) "⚠️ $desc" else "✅ $short"
                    setTextColor(if (desc != null) Color.parseColor("#CC3300") else Color.parseColor("#006600"))
                    textSize = 13f; setPadding(8,4,8,4)
                })
            }
            findViewById<TextView>(R.id.permSummary).text =
                "الإجمالي: ${perms.size}  |  خطيرة: $dangerCount"

            val sent = TrafficStats.getUidTxBytes(ai.uid).let { if (it < 0) 0L else it }
            val recv = TrafficStats.getUidRxBytes(ai.uid).let { if (it < 0) 0L else it }
            val info = AppInfo("","",pm.getApplicationIcon(ai),false, emptyList(),sent,recv,0)
            findViewById<TextView>(R.id.networkSummary).text =
                "↑ مُرسَل: ${info.formattedBytes(sent)}\n↓ مُستقبَل: ${info.formattedBytes(recv)}"

        } catch (e: Exception) {
            Toast.makeText(this, "خطأ في التحليل", Toast.LENGTH_SHORT).show()
        }
    }
}
DETAIL

# ── Layouts ──
cat > app/src/main/res/layout/activity_main.xml << 'XML1'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:orientation="vertical" android:background="#0F0F1A">
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="🔍 محلل التطبيقات" android:textColor="#00D4FF"
        android:textSize="22sp" android:textStyle="bold"
        android:gravity="center" android:padding="16dp" android:background="#1A1A2E"/>
    <SearchView android:id="@+id/searchView" android:layout_width="match_parent"
        android:layout_height="wrap_content" android:queryHint="ابحث..."
        android:iconifiedByDefault="false" android:background="#1A1A2E"/>
    <ProgressBar android:id="@+id/progressBar" android:layout_width="match_parent"
        android:layout_height="wrap_content" android:visibility="gone"/>
    <androidx.recyclerview.widget.RecyclerView android:id="@+id/recyclerView"
        android:layout_width="match_parent" android:layout_height="0dp"
        android:layout_weight="1" android:padding="8dp"/>
</LinearLayout>
XML1

cat > app/src/main/res/layout/item_app.xml << 'XML2'
<?xml version="1.0" encoding="utf-8"?>
<androidx.cardview.widget.CardView
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent" android:layout_height="wrap_content"
    android:layout_margin="6dp" app:cardCornerRadius="12dp"
    app:cardBackgroundColor="#1A1A2E" app:cardElevation="4dp">
    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:padding="12dp" android:gravity="center_vertical">
        <ImageView android:id="@+id/appIcon" android:layout_width="48dp"
            android:layout_height="48dp" android:layout_marginEnd="12dp"/>
        <LinearLayout android:layout_width="0dp" android:layout_height="wrap_content"
            android:layout_weight="1" android:orientation="vertical">
            <TextView android:id="@+id/appName" android:layout_width="wrap_content"
                android:layout_height="wrap_content" android:textColor="#FFFFFF"
                android:textSize="15sp" android:textStyle="bold"/>
            <TextView android:id="@+id/appPackage" android:layout_width="wrap_content"
                android:layout_height="wrap_content" android:textColor="#6666AA"
                android:textSize="11sp" android:maxLines="1" android:ellipsize="end"/>
            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="horizontal" android:layout_marginTop="4dp">
                <TextView android:id="@+id/networkUsage" android:layout_width="0dp"
                    android:layout_height="wrap_content" android:layout_weight="1"
                    android:textColor="#00D4FF" android:textSize="11sp"/>
                <TextView android:id="@+id/permCount" android:layout_width="wrap_content"
                    android:layout_height="wrap_content" android:textColor="#FFAA44" android:textSize="11sp"/>
            </LinearLayout>
            <ProgressBar android:id="@+id/riskBar"
                style="@style/Widget.AppCompat.ProgressBar.Horizontal"
                android:layout_width="match_parent" android:layout_height="5dp"
                android:layout_marginTop="4dp" android:max="100"/>
        </LinearLayout>
        <TextView android:id="@+id/riskLabel" android:layout_width="wrap_content"
            android:layout_height="wrap_content" android:textSize="11sp"
            android:textStyle="bold" android:layout_marginStart="8dp"/>
    </LinearLayout>
</androidx.cardview.widget.CardView>
XML2

cat > app/src/main/res/layout/activity_app_detail.xml << 'XML3'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:background="#0F0F1A">
    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:padding="16dp">
        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
            android:orientation="horizontal" android:padding="12dp"
            android:background="#1A1A2E" android:layout_marginBottom="12dp">
            <ImageView android:id="@+id/detailIcon" android:layout_width="56dp"
                android:layout_height="56dp" android:layout_marginEnd="12dp"/>
            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="vertical">
                <TextView android:id="@+id/detailName" android:layout_width="wrap_content"
                    android:layout_height="wrap_content" android:textColor="#FFFFFF"
                    android:textSize="17sp" android:textStyle="bold"/>
                <TextView android:id="@+id/detailPackage" android:layout_width="wrap_content"
                    android:layout_height="wrap_content" android:textColor="#6666AA" android:textSize="11sp"/>
                <TextView android:id="@+id/detailVersion" android:layout_width="wrap_content"
                    android:layout_height="wrap_content" android:textColor="#00D4FF" android:textSize="12sp"/>
                <TextView android:id="@+id/detailInstall" android:layout_width="wrap_content"
                    android:layout_height="wrap_content" android:textColor="#8888AA" android:textSize="11sp"/>
                <TextView android:id="@+id/detailUpdate" android:layout_width="wrap_content"
                    android:layout_height="wrap_content" android:textColor="#8888AA" android:textSize="11sp"/>
            </LinearLayout>
        </LinearLayout>
        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:text="🌐 استخدام الشبكة" android:textColor="#00D4FF"
            android:textSize="15sp" android:textStyle="bold" android:layout_marginBottom="6dp"/>
        <TextView android:id="@+id/networkSummary" android:layout_width="match_parent"
            android:layout_height="wrap_content" android:textColor="#FFFFFF"
            android:textSize="14sp" android:padding="12dp" android:background="#1A1A2E"
            android:layout_marginBottom="12dp"/>
        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:text="🔐 الصلاحيات" android:textColor="#00D4FF"
            android:textSize="15sp" android:textStyle="bold" android:layout_marginBottom="6dp"/>
        <TextView android:id="@+id/permSummary" android:layout_width="wrap_content"
            android:layout_height="wrap_content" android:textColor="#FFAA44"
            android:textSize="13sp" android:layout_marginBottom="6dp"/>
        <LinearLayout android:id="@+id/permissionsLayout" android:layout_width="match_parent"
            android:layout_height="wrap_content" android:orientation="vertical"
            android:padding="12dp" android:background="#1A1A2E"/>
    </LinearLayout>
</ScrollView>
XML3

cat > app/src/main/res/values/styles.xml << 'STYLES'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="AppTheme" parent="Theme.AppCompat.DayNight.DarkActionBar">
        <item name="colorPrimary">#1A1A2E</item>
        <item name="colorPrimaryDark">#0F0F1A</item>
        <item name="colorAccent">#00D4FF</item>
    </style>
</resources>
STYLES

# ── Gradle Files ──
cat > app/build.gradle << 'GRADLE_APP'
plugins {
    id 'com.android.application'
    id 'kotlin-android'
}
android {
    compileSdk 34
    defaultConfig {
        applicationId "com.appanalyzer"
        minSdk 23
        targetSdk 34
        versionCode 1
        versionName "1.0"
    }
    buildTypes {
        release { minifyEnabled false }
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
    kotlinOptions { jvmTarget = '1.8' }
}
dependencies {
    implementation 'androidx.core:core-ktx:1.12.0'
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'com.google.android.material:material:1.11.0'
    implementation 'androidx.recyclerview:recyclerview:1.3.2'
    implementation 'androidx.cardview:cardview:1.0.0'
}
GRADLE_APP

cat > build.gradle << 'GRADLE_ROOT'
buildscript {
    ext.kotlin_version = '1.9.0'
    repositories { google(); mavenCentral() }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.2.0'
        classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlin_version"
    }
}
allprojects { repositories { google(); mavenCentral() } }
GRADLE_ROOT

cat > settings.gradle << 'SETTINGS'
rootProject.name = "AppAnalyzer"
include ':app'
SETTINGS

cat > gradle/wrapper/gradle-wrapper.properties << 'GWPROPS'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.4-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
GWPROPS

# ══════════════════════════════════════
#  الجزء 3: تثبيت Android SDK
# ══════════════════════════════════════
echo "⬇️  [3/5] تحميل Android SDK..."

ANDROID_HOME="$HOME/android-sdk"
mkdir -p "$ANDROID_HOME/cmdline-tools"

if [ ! -f "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
    wget -q --show-progress -O /tmp/tools.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
    unzip -q /tmp/tools.zip -d /tmp/cmdtools
    mv /tmp/cmdtools/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest"
    rm /tmp/tools.zip
fi

export ANDROID_HOME
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0"

echo "✅ [4/5] تثبيت المكونات..."
yes | sdkmanager --licenses > /dev/null 2>&1
sdkmanager "platforms;android-34" "build-tools;34.0.0" --verbose 2>&1 | grep -E "Done|Installing|Fetch"

echo "sdk.dir=$ANDROID_HOME" > local.properties

# ══════════════════════════════════════
#  الجزء 4: تحميل Gradle Wrapper
# ══════════════════════════════════════
echo "⚙️  [5/5] تجهيز Gradle وبناء APK..."

wget -q -O gradle/wrapper/gradle-wrapper.jar \
    "https://github.com/gradle/gradle/raw/v8.4.0/gradle/wrapper/gradle-wrapper.jar"

cat > gradlew << 'GRADLEW'
#!/bin/sh
JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
export JAVA_HOME
exec java -jar "$(dirname "$0")/gradle/wrapper/gradle-wrapper.jar" "$@"
GRADLEW
chmod +x gradlew

./gradlew assembleDebug --no-daemon --stacktrace 2>&1 | tail -30

# ══════════════════════════════════════
#  النتيجة
# ══════════════════════════════════════
APK="app/build/outputs/apk/debug/app-debug.apk"
if [ -f "$APK" ]; then
    SIZE=$(du -sh "$APK" | cut -f1)
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║        ✅ تم بناء APK بنجاح! 🎉          ║"
    echo "╠══════════════════════════════════════════╣"
    echo "║  📁 $APK"
    echo "║  📦 الحجم: $SIZE"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "💡 لتحميل الملف: انقر بالزر الأيمن على الملف"
    echo "   في Explorer ثم اختر Download"
else
    echo "❌ لم يتم إنشاء APK، راجع الأخطاء أعلاه"
    exit 1
fi
