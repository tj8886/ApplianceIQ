// ApplianceIQ Command Center management navigation
// Keeps the existing Command Center as the single manager-facing product.
(() => {
  const links = [
    ['Operating Dashboard','./'],
    ['AI Manager','./manager.html'],
    ['My Work','./my-work.html'],
    ['Decision Intelligence','./decisions.html'],
    ['Predictive Intelligence','./predictions.html'],
    ['Executive Intelligence','./executive.html'],
    ['Executive Briefs','./briefs.html']
  ];
  const current = location.pathname.split('/').pop() || 'index.html';
  const bar = document.createElement('nav');
  bar.id = 'aiqManagerNav';
  bar.setAttribute('aria-label','Command Center management');
  bar.innerHTML = links.map(([label,href]) => {
    const target = href === './' ? 'index.html' : href.split('/').pop();
    const active = current === target;
    return `<a href="${href}" ${active?'aria-current="page"':''}>${label}</a>`;
  }).join('');
  const style = document.createElement('style');
  style.textContent = `#aiqManagerNav{position:sticky;top:0;z-index:999;display:flex;gap:7px;overflow:auto;padding:9px 14px;background:#0f1f3d;border-bottom:1px solid #263858;font-family:Inter,system-ui,sans-serif}#aiqManagerNav a{white-space:nowrap;color:#cbd5e1;text-decoration:none;font-size:12px;font-weight:750;padding:7px 10px;border-radius:8px}#aiqManagerNav a:hover,#aiqManagerNav a[aria-current=page]{background:#fff;color:#0f1f3d}`;
  document.head.appendChild(style);
  document.body.prepend(bar);
})();