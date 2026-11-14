from pathlib import Path
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[2]
source = root / 'ShichiZip/FileManager/Window/FileManagerToolbarSupport.swift'
text = source.read_text()
output = root / 'build/path-background-comparison'
output.mkdir(parents=True, exist_ok=True)
combined = output / 'Comparison.swift'
combined.write_text('import AppKit\n@MainActor enum SZL10n { static func string(_ key: String) -> String { "Path" } }\n'
                    + text[text.index('/// A native toolbar-sized path editor'):]
                    + '\n' + (root / '.github/scripts/PathBackgroundComparison.swift').read_text())
(output / 'source-proof.json').write_text(json.dumps({
    'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'production_source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'source': str(source.relative_to(root)),
    'production_classes_copied_verbatim': True,
}, indent=2))
executable = output / 'Comparison'
subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-strict-concurrency=complete',
                '-parse-as-library', str(combined), '-o', str(executable)], check=True, cwd=root)
subprocess.run([str(executable), str(output)], check=True, cwd=root)
report = json.loads((output / 'results.json').read_text())
assert len(report['records']) == 48
assert not report['failures'], report['failures']
