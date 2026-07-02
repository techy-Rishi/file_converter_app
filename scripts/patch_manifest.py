"""Patches the freshly-generated AndroidManifest.xml with the app's
display name.

Run from the repo root as: python3 scripts/patch_manifest.py
"""

path = "android/app/src/main/AndroidManifest.xml"

with open(path, "r") as f:
    content = f.read()

content = content.replace(
    'android:label="file_converter_app"',
    'android:label="ConvertKaro"',
)

with open(path, "w") as f:
    f.write(content)

assert "ConvertKaro" in content, "App name insert failed!"

print("Manifest patched successfully:")
print(content)
