import os

def make_replacements():
    pairs = []
    # 2-byte UTF-8 sequences
    for high in range(0xC0, 0xFF):
        for low in range(0x80, 0xC0):
            try:
                original = bytes([high, low]).decode('utf-8')
                # PowerShell on Windows uses CP1252 (not strict Latin-1) for 0x80-0x9F
                mojibake = bytes([high]).decode('cp1252') + bytes([low]).decode('cp1252')
                pairs.append((mojibake, original))
            except Exception:
                pass
    # 3-byte UTF-8 sequences
    for b1 in range(0xE0, 0xF0):
        for b2 in range(0x80, 0xC0):
            for b3 in range(0x80, 0xC0):
                try:
                    original = bytes([b1, b2, b3]).decode('utf-8')
                    mojibake = (bytes([b1]).decode('cp1252') +
                                bytes([b2]).decode('cp1252') +
                                bytes([b3]).decode('cp1252'))
                    pairs.append((mojibake, original))
                except Exception:
                    pass
    # Longest first so 3-char sequences are replaced before 2-char sub-sequences
    pairs.sort(key=lambda x: -len(x[0]))
    return pairs

replacements = make_replacements()

files = [
    'lib/pages/eleveur/eleveur_home.dart',
    'lib/pages/eleveur/eleveur_nav.dart',
    'lib/pages/mes_alertes_page.dart',
    'lib/pages/particulier/particulier_home.dart',
    'lib/pages/particulier/particulier_nav.dart',
    'lib/pages/particulier/animaux_perdus_page.dart',
]

for path in files:
    if not os.path.exists(path):
        print(f'NOT FOUND: {path}')
        continue
    with open(path, 'r', encoding='utf-8-sig') as f:
        content = f.read()
    original = content
    for bad, good in replacements:
        if bad in content:
            content = content.replace(bad, good)
    if content != original:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f'Fixed: {path}')
    else:
        print(f'No change: {path}')
