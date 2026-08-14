#!/usr/bin/env python3
"""
Patch script: Adds Floor Analytics to CRM Command Centre + IQ Field sidebar nav.
Run from ~/ApplianceIQ:  python3 patch-floor-analytics.py
"""
import os, sys

BASE = os.path.expanduser('~/ApplianceIQ')

# ─── 1. PATCH CRM COMMAND CENTRE ───
crm_path = os.path.join(BASE, 'apps/crm/index.html')
print(f'Patching CRM: {crm_path}')

with open(crm_path, 'r') as f:
    crm = f.read()

# Find the end of renderCommandCentre — inject floor analytics section before trackEvent
FLOOR_SECTION = r"""
  // ===== FLOOR PRESENCE ANALYTICS =====
  try {
    const {data: floorData} = await sb.rpc('get_floor_vs_sales', {p_org_id: currentOrg.id});
    if (floorData && floorData.total_displays > 0) {
      const bf = floorData.brand_floor || [];
      const bs = floorData.brand_sales || [];
      // Merge brand floor + sales into comparison rows
      const brandMap = {};
      bf.forEach(b => { brandMap[b.brand] = { floor_pct: b.floor_pct, floor_units: b.floor_units }; });
      bs.forEach(b => {
        if (!brandMap[b.brand]) brandMap[b.brand] = { floor_pct: 0, floor_units: 0 };
        brandMap[b.brand].sales_pct = b.sales_pct;
        brandMap[b.brand].sales_amount = b.sales_amount;
      });
      const brandRows = Object.entries(brandMap)
        .map(([name, d]) => ({ name, floor_pct: d.floor_pct||0, sales_pct: d.sales_pct||0, sales_amount: d.sales_amount||0, delta: (d.sales_pct||0) - (d.floor_pct||0) }))
        .sort((a,b) => b.floor_pct - a.floor_pct);

      let floorHtml = '<div class="cc-section"><h3>🏬 Floor Presence vs Sales</h3>'
        + '<div class="cc-grid">'
        + '<div class="cc-card"><div class="cc-lbl">Displays</div><div class="cc-val num">' + floorData.total_displays + '</div><div class="cc-sub">' + floorData.store_count + ' store' + (floorData.store_count !== 1 ? 's' : '') + '</div></div>'
        + '<div class="cc-card"><div class="cc-lbl">Floored SKUs</div><div class="cc-val num">' + floorData.total_skus + '</div></div>'
        + '<div class="cc-card"><div class="cc-lbl">Floor Units</div><div class="cc-val num">' + floorData.total_floor_units + '</div></div>'
        + '<div class="cc-card"><div class="cc-lbl">Won Revenue</div><div class="cc-val num">' + money(floorData.total_sales) + '</div></div>'
        + '</div>';
      if (brandRows.length) {
        floorHtml += '<div style="margin-top:12px;overflow-x:auto"><table style="width:100%;border-collapse:collapse;font-size:13px">'
          + '<tr style="border-bottom:2px solid var(--line)"><th style="text-align:left;padding:6px 10px;font-size:11px;text-transform:uppercase;letter-spacing:.5px;color:var(--steel)">Brand</th><th style="padding:6px 10px;text-align:right;font-size:11px;text-transform:uppercase;color:var(--steel)">Floor %</th><th style="padding:6px 10px;text-align:right;font-size:11px;text-transform:uppercase;color:var(--steel)">Sales %</th><th style="padding:6px 10px;text-align:right;font-size:11px;text-transform:uppercase;color:var(--steel)">Delta</th></tr>';
        brandRows.forEach(r => {
          const deltaColor = r.delta > 1 ? 'var(--success)' : r.delta < -1 ? 'var(--danger,#dc2626)' : 'var(--steel)';
          const deltaSign = r.delta > 0 ? '+' : '';
          floorHtml += '<tr style="border-bottom:1px solid var(--line)"><td style="padding:6px 10px;font-weight:500">' + esc(r.name) + '</td>'
            + '<td style="padding:6px 10px;text-align:right">' + r.floor_pct.toFixed(1) + '%</td>'
            + '<td style="padding:6px 10px;text-align:right">' + r.sales_pct.toFixed(1) + '%</td>'
            + '<td style="padding:6px 10px;text-align:right;font-weight:600;color:' + deltaColor + '">' + deltaSign + r.delta.toFixed(1) + '%</td></tr>';
        });
        floorHtml += '</table></div>';
      }
      floorHtml += '</div>';
      mainEl.innerHTML += floorHtml;
    }
  } catch(e) { console.warn('Floor analytics:', e); }
"""

# Insert before trackEvent('page_view',{page:'dashboard'});
anchor = "trackEvent('page_view',{page:'dashboard'});"
if anchor in crm:
    if 'Floor Presence vs Sales' not in crm:
        crm = crm.replace(anchor, FLOOR_SECTION + '\n  ' + anchor)
        print('  ✅ Floor analytics section added to Command Centre')
    else:
        print('  ⚠️  Floor analytics already present, skipping')
else:
    print('  ❌ Could not find anchor point in CRM. Manual patch needed.')

with open(crm_path, 'w') as f:
    f.write(crm)


# ─── 2. PATCH IQ FIELD SIDEBAR ───
field_path = os.path.join(BASE, 'apps/iq-field/index.html')
print(f'Patching IQ Field: {field_path}')

with open(field_path, 'r') as f:
    field = f.read()

# Add Floor Plan nav item
old_nav = "{ id: 'v-history', icon: '📋', label: 'Visit History' },"
new_nav = "{ id: 'floor-plan', icon: '🏬', label: 'Floor Plan', href: 'floor-plan.html' },\n    { id: 'v-history', icon: '📋', label: 'Visit History' },"

if 'floor-plan' not in field:
    if old_nav in field:
        field = field.replace(old_nav, new_nav)
        print('  ✅ Floor Plan nav item added')
    else:
        print('  ❌ Could not find nav anchor in IQ Field')
else:
    print('  ⚠️  Floor Plan nav already present, skipping')

# Make the nav item clickable as a link
old_onclick = """onclick="navTo('${n.id}', this)\""""
new_onclick = """onclick="${n.href ? "window.location.href='" + n.href + "'" : "navTo('" + n.id + "', this)"}\""""

if 'n.href' not in field:
    if old_onclick in field:
        field = field.replace(old_onclick, new_onclick)
        print('  ✅ Nav onclick updated for href support')
    else:
        print('  ❌ Could not find onclick anchor in IQ Field')
else:
    print('  ⚠️  Href onclick already present, skipping')

with open(field_path, 'w') as f:
    f.write(field)

print('\n🎯 Done! Now run:')
print('  cd ~/ApplianceIQ && git add -A && git commit -m "Add floor analytics to Command Centre + IQ Field nav" && git push origin main')
