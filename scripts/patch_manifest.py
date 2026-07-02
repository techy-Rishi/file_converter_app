"""Patches the freshly-generated AndroidManifest.xml with the app's
display name and the AdMob Application ID meta-data tag.

Run from the repo root as: python3 scripts/patch_manifest.py
"""

path = "android/app/src/main/AndroidManifest.xml"

with open(path, "r") as f:
    content = f.read()

content = content.replace(
    'android:label="file_converter_app"',
    'android:label="ConvertKaro"',
)

admob_meta_data = (
    '    <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" '
    'android:value="ca-app-pub-3940256099942544~3347511713"/>\n'
    '    </application>'
)
content = content.replace('</application>', admob_meta_data)

with open(path, "w") as f:
    f.write(content)

assert "com.google.android.gms.ads.APPLICATION_ID" in content, "AdMob App ID insert failed!"
assert "ConvertKaro" in content, "App name insert failed!"

print("Manifest patched successfully:")
print(content)
