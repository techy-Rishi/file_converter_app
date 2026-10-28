"""Patches the freshly-generated AndroidManifest.xml with the app's
display name and mailto intent queries for Android 11+.
"""

path = "android/app/src/main/AndroidManifest.xml"

with open(path, "r") as f:
    content = f.read()

content = content.replace(
    'android:label="file_converter_app"',
    'android:label="ConvertKaro"',
)

mailto_query = """    <queries>
        <intent>
            <action android:name="android.intent.action.SENDTO" />
            <data android:scheme="mailto" />
        </intent>
    </queries>
</manifest>"""

if "android.intent.action.SENDTO" not in content:
    content = content.replace("</manifest>", mailto_query)

with open(path, "w") as f:
    f.write(content)

assert "ConvertKaro" in content, "App name insert failed!"
print("Manifest patched successfully:")
print(content)
