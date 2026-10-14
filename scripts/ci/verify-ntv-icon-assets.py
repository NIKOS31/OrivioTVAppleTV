"""Verify actual actool output, not just the source icon declarations."""
import plistlib
from pathlib import Path
import sys

with Path(sys.argv[1]).open('rb') as file:
    info = plistlib.load(file)
icons = info.get('CFBundleIcons', {})
if icons.get('CFBundlePrimaryIcon') != 'NTVPrimaryIconV2':
    raise SystemExit('The compiled primary nTV icon is missing.')
alternatives = icons.get('CFBundleAlternateIcons', [])
if not isinstance(alternatives, (list, dict)) or 'NTVSystemIcon' not in alternatives:
    raise SystemExit('The compiled alternate nTV icon is missing; do not deliver this bundle.')
if isinstance(alternatives, dict) and alternatives['NTVSystemIcon'].get('CFBundleIconName') != 'NTVSystemIcon':
    raise SystemExit('The compiled alternate icon declaration does not name its actual rendition.')
if b'NTVSystemIcon' not in Path(sys.argv[2]).read_bytes():
    raise SystemExit('The alternate n rendition is absent from the compiled asset catalogue.')
print('Compiled primary and alternate nTV icon assets verified.')
