from pathlib import Path

path = Path('manager.html')
text = path.read_text(encoding='utf-8')
scripts = [
    '<script type="module" src="./phase6-revenue-intelligence.js"></script>',
    '<script type="module" src="./phase7-automation.js"></script>',
]
for needle in scripts:
    if needle not in text:
        text = text.replace('</body>', needle + '\n</body>')
path.write_text(text, encoding='utf-8')

pred = Path('predictions.html')
pred_text = pred.read_text(encoding='utf-8')
p8 = '<script type="module" src="./phase8-forecasting.js"></script>'
if p8 not in pred_text:
    pred_text = pred_text.replace('</body>', p8 + '\n</body>')
pred.write_text(pred_text, encoding='utf-8')
print('Phases 6-8 Command Center integration ready')
