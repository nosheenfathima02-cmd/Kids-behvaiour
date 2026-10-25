"""Checks the store listing text in store-listing.md against the store limits."""
import pathlib
import re
import sys

LIMITS = {
    'play_title': 30, 'play_short': 80, 'play_full': 4000,
    'ios_name': 30, 'ios_subtitle': 30, 'ios_promo': 170, 'ios_keywords': 100,
}
text = pathlib.Path(__file__).with_name('store-listing.md').read_text(encoding='utf-8')
ok = True
for key, limit in LIMITS.items():
    m = re.search(rf'<!-- {key} -->\n(.*?)\n<!-- /{key} -->', text, re.S)
    if not m:
        print(f'{key}: missing'); ok = False; continue
    n = len(m.group(1))
    status = 'ok' if n <= limit else 'TOO LONG'
    ok &= n <= limit
    print(f'{key:13} {n:5} / {limit:<5} {status}')
sys.exit(0 if ok else 1)
