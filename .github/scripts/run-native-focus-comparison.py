from pathlib import Path
import hashlib
import json
import plistlib
import subprocess

root = Path(__file__).resolve().parents[2]
work = root / "build/native-focus-comparison"
output = work / "output"
output.mkdir(parents=True, exist_ok=True)
app = work / "Native Focus Comparison.app"
binary = app / "Contents/MacOS/NativeFocusComparison"
binary.parent.mkdir(parents=True, exist_ok=True)
original = root / "ShichiZip/FileManager/Window/FileManagerToolbarSupport.swift"
source = original.read_text()
field = source[source.index("/// A native toolbar-sized path editor"):source.index("/// Uses a separate native toolbar")]
combined = work / "Comparison.swift"
combined.write_text("import AppKit\nimport QuartzCore\nimport Darwin\n" + field + "\n" + (root / ".github/scripts/NativeFocusComparison.swift").read_text())
commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
(output / "source-proof.json").write_text(json.dumps({"diagnostic_commit": commit, "production_baseline": "980abc58eababfb0b2593d3632954c118ffb0121", "candidate_changes": "extraLarge on macOS 26+, direct toolbar hosting", "field_source_sha256": hashlib.sha256(field.encode()).hexdigest(), "toolbar_source_sha256": hashlib.sha256(original.read_bytes()).hexdigest(), "notes": "A uses the actual FileManagerTitlePathField candidate source. B and C compare 9pt insets with no font, rich-text or control-size differences. Only the diagnostic branch contains the custom cell and native-inset prototype. All fields are directly hosted by NSToolbarItem."}, indent=2) + "\n")
info = {"CFBundleIdentifier": "local.Zonz.ShichiZip.NativeFocusComparison", "CFBundleName": "Native Focus Comparison", "CFBundleExecutable": "NativeFocusComparison", "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "LSMinimumSystemVersion": "27.0", "NSHighResolutionCapable": True}
(app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
command = ["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete", "-parse-as-library", "-target", "arm64-apple-macos27.0", str(combined), "-o", str(binary)]
with (output / "compile.log").open("w") as log:
    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
if result.returncode:
    print((output / "compile.log").read_text())
    raise SystemExit(result.returncode)
subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
with (output / "runtime.log").open("w") as log:
    result = subprocess.run([str(binary), str(output)], stdout=log, stderr=subprocess.STDOUT, timeout=120)
print((output / "runtime.log").read_text())
raise SystemExit(result.returncode)
