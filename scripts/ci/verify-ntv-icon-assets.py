"""Verify actual actool output, not just the source icon declarations."""
import plistlib
from pathlib import Path
import sys

with Path(sys.argv[1]).open('rb') as file:
    info = plistlib.load(file)
icons = info.get('CFBundleIcons', {})
if icons.get('CFBundlePrimaryIcon') != 'NTVPrimaryIcon':
    raise SystemExit('The compiled primary nTV icon is missing.')
if 'NTVSystemIcon' not in icons.get('CFBundleAlternateIcons', []):
    raise SystemExit('The compiled alternate nTV icon is missing; do not deliver this bundle.')
if b'NTVSystemIcon' not in Path(sys.argv[2]).read_bytes():
    raise SystemExit('The alternate n rendition is absent from the compiled asset catalogue.')
print('Compiled primary and alternate nTV icon assets verified.')
