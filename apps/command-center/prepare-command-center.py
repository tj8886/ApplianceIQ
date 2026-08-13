from pathlib import Path

path = Path('manager.html')
text = path.read_text(encoding='utf-8')
needle = '<script type="module" src="./phase6-revenue-intelligence.js"></script>'
if needle not in text:
    text = text.replace('</body>', needle + '\n</body>')
    path.write_text(text, encoding='utf-8')
print('Phase 6 Command Center integration ready')
