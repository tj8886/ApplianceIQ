from pathlib import Path
import re

# Replace the legacy browser-LLM AI Insights path with the governed
# Intelligence -> Decision -> AI Manager implementation during deploy.
index = Path('index.html')
index_text = index.read_text(encoding='utf-8')
governed = Path('governed-ai-insights.function.js').read_text(encoding='utf-8').strip()
pattern = r"async function renderAI\(\)\{.*?\n\}\n\nfunction renderInsightCards"
replacement = governed + "\n\nfunction renderInsightCards"
updated, count = re.subn(pattern, replacement, index_text, count=1, flags=re.S)
if count != 1:
    raise SystemExit('Could not locate exactly one legacy renderAI function for governed replacement')
index.write_text(updated, encoding='utf-8')

# Shared management navigation is injected into every first-party Command Center view.
nav_script = '<script src="./manager-os-nav.js"></script>'
for filename in ['index.html','manager.html','my-work.html','decisions.html','predictions.html','executive.html','briefs.html']:
    p = Path(filename)
    text = p.read_text(encoding='utf-8')
    if nav_script not in text:
        text = text.replace('</body>', nav_script + '\n</body>')
    p.write_text(text, encoding='utf-8')

# Phase-specific integrations remain attached to their existing authoritative surfaces.
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
print('Unified Command Center management surfaces + governed AI Insights + Phases 6-8 integration ready')