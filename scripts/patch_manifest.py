import os

path = "android/app/src/main/AndroidManifest.xml"

if not os.path.exists(path):
    print(f"Warning: {path} not found yet. Skipping patch.")
    exit(0)

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

# App name patch
if 'android:label="file_converter_app"' in content:
    content = content.replace(
        'android:label="file_converter_app"',
        'android:label="ConvertKaro"',
    )
elif 'android:label="@string/app_name"' not in content:
    # Fallback replacement if label is different
    content = content.replace(
        'android:label="',
        'android:label="ConvertKaro" data-old="',
    )

# Mailto intent queries patch for Android 11+
mailto_query = """    <queries>
        <intent>
            <action android:name="android.intent.action.SENDTO" />
            <data android:scheme="mailto" />
        </intent>
    </queries>
</manifest>"""

if "android.intent.action.SENDTO" not in content:
    if "</manifest>" in content:
        content = content.replace("</manifest>", mailto_query)

with open(path, "w", encoding="utf-8") as f:
    f.write(content)

print("AndroidManifest.xml patched successfully!")
