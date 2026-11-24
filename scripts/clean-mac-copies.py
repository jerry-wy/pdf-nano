"""Remove this project's redundant app bundles, preserving the verified installation."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

installed = Path(sys.argv[1]).resolve()
project = Path(__file__).resolve().parent.parent
register = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'

def is_pdf_nano(path):
    try:
        info = plistlib.loads((path / 'Contents/Info.plist').read_bytes())
        return info.get('CFBundleIdentifier') == 'app.pdfnano.reader'
    except (OSError, plistlib.InvalidFileException):
        return False

if not is_pdf_nano(installed):
    raise SystemExit('No verified PDF Nano installation to retain; nothing removed.')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(installed)], check=True)

# Include removed historical names so their stale Open With records can be unregistered.
copies = {project / 'build' / name for name in (
    'PDF Nano.app', 'PDF Nano 1.1.4.app', 'PDF Nano 1.1.5.app'
)}
for directory in (project / 'build', Path('/Applications'), Path.home() / 'Applications'):
    copies.update(directory.glob('PDF Nano*.app'))

for copy in sorted(copies):
    if copy.resolve() == installed:
        continue
    if copy.is_symlink() or (copy.exists() and not is_pdf_nano(copy)):
        continue
    result = subprocess.run([register, '-u', str(copy)], capture_output=True, text=True)
    if result.returncode:
        print(f'Could not unregister {copy.name}; macOS may still show its cached entry.')
    if copy.exists():
        shutil.rmtree(copy)
        print(f'Removed duplicate: {copy}')
print(f'Kept: {installed}')
