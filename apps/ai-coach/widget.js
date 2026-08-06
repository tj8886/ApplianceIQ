/**
 * ApplianceIQ AI Coach Widget
 * 
 * Drop this into ANY ApplianceIQ app:
 *   <script src="https://ai-iq-coach.netlify.app/widget.js" data-app="crm"></script>
 * 
 * data-app values: crm, speciq, academy, up, command, field, pim, scraper, coach
 * 
 * One brain. One router. Six personas. Every app.
 * All conversations feed through ai-intelligence-router → shared memory → unified learning.
 */
(function(){
'use strict';

const SB_URL='https://fumwwhyozeouoqscolke.supabase.co';
const SB_ANON='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ1bXd3aHlvemVvdW9xc2NvbGtlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDMxMTkwNjEsImV4cCI6MjA1ODY5NTA2MX0.FgGW0BAb1AuMFaMBmOkqjVaOx1JxRvHASrzP3LNpMrg';
const ROUTER_URL=`${SB_URL}/functions/v1/ai-intelligence-router`;

const script=document.currentScript;
const appContext=script?.getAttribute('data-app')||'coach';
const position=script?.getAttribute('data-position')||'right';

const APP_LABELS={
  crm:'CRM & Sales',speciq:'Spec IQ',academy:'IQ Academy',up:'Up System',
  command:'Command Center',field:'IQ Field',pim:'Product IQ',scraper:'PIM Scraper',coach:'AI Coach'
};

let session=null,conversationId=null,history=[],isOpen=false,streaming=false;

// ── Supabase auth detection ──
async function getSession(){
  // Try to find existing Supabase client on the page
  if(window.__supabaseClient){
    const{data}=await window.__supabaseClient.auth.getSession();
    return data?.session||null;
  }
  // Try localStorage for sb session
  const keys=Object.keys(localStorage).filter(k=>k.startsWith('sb-')&&k.endsWith('-auth-token'));
  for(const key of keys){
    try{
      const stored=JSON.parse(localStorage.getItem(key));
      if(stored?.access_token)return stored;
    }catch{}
  }
  return null;
}

// ── Styles ──
const css=document.createElement('style');
css.textContent=`
.aiq-widget-fab{position:fixed;${position==='left'?'left':'right'}:20px;bottom:20px;z-index:99999;width:52px;height:52px;border-radius:50%;background:linear-gradient(135deg,#0f1f3d,#0d9488);color:#fff;border:none;cursor:pointer;box-shadow:0 4px 20px rgba(15,31,61,.35);display:flex;align-items:center;justify-content:center;transition:all .2s;font-family:'Inter',system-ui,sans-serif}
.aiq-widget-fab:hover{transform:scale(1.08);box-shadow:0 6px 28px rgba(15,31,61,.45)}
.aiq-widget-fab.open{transform:scale(0);pointer-events:none}
.aiq-widget-fab svg{width:24px;height:24px}
.aiq-widget-fab .fab-badge{position:absolute;top:-2px;right:-2px;width:14px;height:14px;border-radius:50%;background:#14b8a6;border:2px solid #fff;animation:aiq-pulse 2s infinite}
@keyframes aiq-pulse{0%,100%{opacity:1}50%{opacity:.5}}

.aiq-widget-panel{position:fixed;${position==='left'?'left':'right'}:20px;bottom:20px;z-index:99999;width:400px;height:600px;max-height:calc(100vh - 40px);background:#fff;border-radius:16px;box-shadow:0 12px 48px rgba(15,31,61,.2);display:flex;flex-direction:column;overflow:hidden;transform:scale(.92) translateY(20px);opacity:0;pointer-events:none;transition:all .25s cubic-bezier(.4,0,.2,1);font-family:'Inter',system-ui,-apple-system,sans-serif}
.aiq-widget-panel.open{transform:scale(1) translateY(0);opacity:1;pointer-events:all}
@media(max-width:480px){.aiq-widget-panel{width:calc(100vw - 16px);height:calc(100vh - 16px);left:8px;right:8px;bottom:8px;border-radius:12px}}

.aiq-w-header{background:#0f1f3d;padding:14px 16px;display:flex;align-items:center;gap:10px;flex-shrink:0}
.aiq-w-header .w-icon{width:30px;height:30px;border-radius:8px;background:#14b8a6;display:flex;align-items:center;justify-content:center;font-size:10px;font-weight:800;color:#0f1f3d;flex-shrink:0}
.aiq-w-header .w-title{flex:1}
.aiq-w-header .w-title h3{font-size:14px;font-weight:700;color:#fff;margin:0}
.aiq-w-header .w-title small{font-size:10px;color:rgba(255,255,255,.45);font-weight:500}
.aiq-w-header .w-tier{font-size:9px;padding:3px 7px;border-radius:8px;font-weight:600;flex-shrink:0}
.aiq-w-header .w-tier.fast{background:rgba(34,197,94,.15);color:#4ade80}
.aiq-w-header .w-tier.standard{background:rgba(59,130,246,.15);color:#60a5fa}
.aiq-w-header .w-tier.strong{background:rgba(168,85,247,.15);color:#c084fc}
.aiq-w-header .w-tier.det{background:rgba(245,158,11,.15);color:#fbbf24}
.aiq-w-header .w-close{background:none;border:none;color:rgba(255,255,255,.5);cursor:pointer;padding:4px;border-radius:4px;font-size:18px;line-height:1;transition:color .12s}
.aiq-w-header .w-close:hover{color:#fff}

.aiq-w-msgs{flex:1;overflow-y:auto;padding:16px;display:flex;flex-direction:column;gap:12px;background:#f4f6f9}
.aiq-w-msgs::-webkit-scrollbar{width:4px}
.aiq-w-msgs::-webkit-scrollbar-thumb{background:#ddd;border-radius:4px}

.aiq-w-welcome{text-align:center;padding:24px 12px}
.aiq-w-welcome .w-emoji{font-size:36px;margin-bottom:12px}
.aiq-w-welcome h4{font-size:15px;font-weight:700;color:#0f1f3d;margin-bottom:4px}
.aiq-w-welcome p{font-size:12px;color:#5a6a85;line-height:1.5;margin-bottom:16px}
.aiq-w-welcome .w-chips{display:flex;flex-wrap:wrap;gap:6px;justify-content:center}
.aiq-w-welcome .w-chip{font-size:11px;padding:6px 12px;border-radius:16px;background:#fff;border:1px solid #e2e7ef;color:#0f1f3d;cursor:pointer;font-weight:500;transition:all .12s;font-family:inherit}
.aiq-w-welcome .w-chip:hover{border-color:#14b8a6;color:#0d9488;background:rgba(20,184,166,.05)}

.aiq-wm{display:flex;gap:8px;max-width:88%;animation:aiq-fadeUp .2s ease}
@keyframes aiq-fadeUp{from{opacity:0;transform:translateY(4px)}to{opacity:1;transform:none}}
.aiq-wm.user{margin-left:auto;flex-direction:row-reverse}
.aiq-wm-av{width:24px;height:24px;border-radius:50%;flex-shrink:0;display:flex;align-items:center;justify-content:center;font-size:9px;font-weight:700;color:#fff;margin-top:2px}
.aiq-wm.user .aiq-wm-av{background:#0f1f3d}
.aiq-wm-body{border-radius:12px;padding:10px 13px;font-size:13px;line-height:1.55;color:#0f1f3d}
.aiq-wm.user .aiq-wm-body{background:#0f1f3d;color:#fff;border-bottom-right-radius:4px}
.aiq-wm.assistant .aiq-wm-body{background:#fff;border:1px solid #e2e7ef;border-bottom-left-radius:4px}
.aiq-wm.assistant .aiq-wm-body strong{font-weight:600}
.aiq-wm.assistant .aiq-wm-body code{background:#f4f6f9;padding:1px 4px;border-radius:3px;font-size:12px}
.aiq-wm.assistant .aiq-wm-body ul,.aiq-wm.assistant .aiq-wm-body ol{margin:4px 0;padding-left:16px}
.aiq-wm.assistant .aiq-wm-body li{margin:2px 0}
.aiq-wm.assistant .aiq-wm-body p{margin:4px 0}
.aiq-wm.assistant .aiq-wm-body p:first-child{margin-top:0}
.aiq-wm.assistant .aiq-wm-body p:last-child{margin-bottom:0}
.aiq-wm-meta{font-size:9px;color:#8896aa;margin-top:3px;display:flex;gap:6px}
.aiq-wm-meta span{padding:1px 5px;border-radius:4px;background:#f4f6f9}

.aiq-w-typing{display:flex;gap:3px;padding:4px 0}
.aiq-w-typing span{width:4px;height:4px;border-radius:50%;background:#14b8a6;animation:aiq-blink 1.4s infinite both}
.aiq-w-typing span:nth-child(2){animation-delay:.2s}
.aiq-w-typing span:nth-child(3){animation-delay:.4s}
@keyframes aiq-blink{0%,80%,100%{opacity:.2;transform:scale(.8)}40%{opacity:1;transform:scale(1)}}

.aiq-w-input{padding:12px;border-top:1px solid #e2e7ef;background:#fff;flex-shrink:0}
.aiq-w-input-row{display:flex;gap:6px;align-items:flex-end}
.aiq-w-input-wrap{flex:1;background:#f4f6f9;border:1.5px solid #e2e7ef;border-radius:10px;padding:3px 3px 3px 12px;display:flex;align-items:flex-end;transition:border-color .15s}
.aiq-w-input-wrap:focus-within{border-color:#14b8a6}
.aiq-w-input-wrap textarea{flex:1;border:none;background:none;resize:none;font-size:13px;line-height:1.4;color:#0f1f3d;padding:6px 0;max-height:80px;outline:none;font-family:inherit}
.aiq-w-input-wrap textarea::placeholder{color:#8896aa}
.aiq-w-send{width:30px;height:30px;border-radius:7px;background:#0f1f3d;color:#fff;border:none;cursor:pointer;display:flex;align-items:center;justify-content:center;transition:background .12s;flex-shrink:0}
.aiq-w-send:hover{background:#0d9488}
.aiq-w-send:disabled{opacity:.3;cursor:default}
.aiq-w-send svg{width:14px;height:14px}
`;
document.head.appendChild(css);

// ── Build DOM ──
const fab=document.createElement('button');
fab.className='aiq-widget-fab';
fab.innerHTML='<svg fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"><path d="M8.625 12a.375.375 0 11-.75 0 .375.375 0 01.75 0zm0 0H8.25m4.125 0a.375.375 0 11-.75 0 .375.375 0 01.75 0zm0 0H12m4.125 0a.375.375 0 11-.75 0 .375.375 0 01.75 0zm0 0h-.375M21 12c0 4.556-4.03 8.25-9 8.25a9.764 9.764 0 01-2.555-.337A5.972 5.972 0 015.41 20.97a5.969 5.969 0 01-.474-.065 4.48 4.48 0 00.978-2.025c.09-.457-.133-.901-.467-1.226C3.93 16.178 3 14.189 3 12c0-4.556 4.03-8.25 9-8.25s9 3.694 9 8.25z"/></svg><span class="fab-badge"></span>';
fab.onclick=()=>toggle();

const panel=document.createElement('div');
panel.className='aiq-widget-panel';

const contextChips={
  crm:['My stale deals','Draft follow-up email','Objection: cheaper online'],
  speciq:['Quote status','Build kitchen package','Compare two models'],
  academy:['My training progress','Quiz me on Bosch','Roleplay a close'],
  up:["Who's up next?",'Missed ups today','Shift coverage check'],
  command:['Sales this month','Top rep leaderboard','Budget vs actual'],
  field:['Latest store walk','Open action items','Repeat issues'],
  pim:['Bosch warranty','LG recall check','Sub-Zero specs'],
  coach:['Help me close a deal','Compare brands','Installation requirements'],
  scraper:['Product lookup','Brand specs','Check a model']
};
const chips=contextChips[appContext]||contextChips.coach;

panel.innerHTML=`
<div class="aiq-w-header">
  <div class="w-icon">IQ</div>
  <div class="w-title"><h3>AI Coach</h3><small>${APP_LABELS[appContext]||'ApplianceIQ'}</small></div>
  <span class="w-tier" id="aiqTier" style="display:none"></span>
  <button class="w-close" onclick="this.closest('.aiq-widget-panel').classList.remove('open');document.querySelector('.aiq-widget-fab').classList.remove('open')">✕</button>
</div>
<div class="aiq-w-msgs" id="aiqMsgs">
  <div class="aiq-w-welcome" id="aiqWelcome">
    <div class="w-emoji">🧠</div>
    <h4>ApplianceIQ Intelligence</h4>
    <p>One brain across every app. I learn from every conversation, route to the right coach, and use the cheapest model that gets the job done.</p>
    <div class="w-chips">${chips.map(c=>`<button class="w-chip" onclick="window.__aiqSend('${c.replace(/'/g,"\\'")}')">${c}</button>`).join('')}</div>
  </div>
</div>
<div class="aiq-w-input">
  <div class="aiq-w-input-row">
    <div class="aiq-w-input-wrap">
      <textarea id="aiqInp" rows="1" placeholder="Ask anything…" onkeydown="if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();window.__aiqSend()}" oninput="this.style.height='auto';this.style.height=Math.min(this.scrollHeight,80)+'px'"></textarea>
    </div>
    <button class="aiq-w-send" id="aiqSendBtn" onclick="window.__aiqSend()"><svg fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M6 12L3.269 3.126A59.768 59.768 0 0121.485 12 59.77 59.77 0 013.27 20.876L5.999 12zm0 0h7.5"/></svg></button>
  </div>
</div>`;

document.body.appendChild(fab);
document.body.appendChild(panel);

function toggle(){
  isOpen=!isOpen;
  panel.classList.toggle('open',isOpen);
  fab.classList.toggle('open',isOpen);
  if(isOpen)document.getElementById('aiqInp')?.focus();
}

// ── Send ──
window.__aiqSend=async function(text){
  const inp=document.getElementById('aiqInp');
  if(!text){text=inp?.value?.trim();if(!text)return;inp.value='';inp.style.height='auto'}
  if(streaming)return;

  // Hide welcome
  const wel=document.getElementById('aiqWelcome');
  if(wel)wel.style.display='none';

  session=await getSession();
  if(!session){
    addWidgetMsg('assistant','Please sign in to ApplianceIQ first. The AI Coach needs authentication to access your data securely.',{persona:'System'});
    return;
  }

  addWidgetMsg('user',text);
  showWidgetTyping();
  streaming=true;
  const btn=document.getElementById('aiqSendBtn');
  if(btn)btn.disabled=true;

  try{
    const res=await fetch(ROUTER_URL,{
      method:'POST',
      headers:{'Content-Type':'application/json','Authorization':`Bearer ${session.access_token}`,'apikey':SB_ANON},
      body:JSON.stringify({
        message:text,
        conversation_id:conversationId||undefined,
        history:history.slice(-10),
        max_specialists:3,
        metadata:{source_app:appContext,app_label:APP_LABELS[appContext]}
      })
    });
    const data=await res.json();
    removeWidgetTyping();

    if(!data.ok){
      addWidgetMsg('assistant','⚠️ '+(data.detail||'Router error'),{persona:'System'});
    }else{
      conversationId=data.conversation_id;
      const answer=data.answer||'No response.';
      const persona=data.primary_persona||'IQ';
      const tier=data.complexity?.tier||'auto';
      const mode=data.mode||'auto';

      // Update tier badge
      const tierEl=document.getElementById('aiqTier');
      if(tierEl){
        tierEl.style.display='';
        tierEl.className='w-tier '+(mode==='deterministic'?'det':tier==='fast'?'fast':tier==='standard'?'standard':'strong');
        tierEl.textContent=mode==='deterministic'?'DB':tier==='fast'?'Fast':tier.charAt(0).toUpperCase()+tier.slice(1);
      }

      addWidgetMsg('assistant',answer,{persona,tier:mode==='deterministic'?'deterministic':tier,cost:data.cost_estimate_usd});
      history.push({role:'user',text});
      history.push({role:'assistant',text:answer,metadata:{tier,persona}});
    }
  }catch(e){
    removeWidgetTyping();
    addWidgetMsg('assistant','⚠️ '+e.message,{persona:'System'});
  }
  streaming=false;
  if(btn)btn.disabled=false;
  document.getElementById('aiqInp')?.focus();
};

function addWidgetMsg(role,content,meta){
  const area=document.getElementById('aiqMsgs');
  const isU=role==='user';
  const p=meta?.persona||'IQ';
  const av=isU?'<div class="aiq-wm-av" style="background:#0f1f3d">You</div>':'<div class="aiq-wm-av" style="background:#14b8a6">'+p.slice(0,2)+'</div>';
  let metaHtml='';
  if(!isU&&meta&&meta.persona!=='System'){
    const tags=[];
    if(meta.persona)tags.push('<span>'+meta.persona+'</span>');
    if(meta.tier)tags.push('<span>'+meta.tier+'</span>');
    if(meta.cost!=null)tags.push('<span>~$'+meta.cost.toFixed(4)+'</span>');
    if(tags.length)metaHtml='<div class="aiq-wm-meta">'+tags.join('')+'</div>';
  }
  area.innerHTML+=`<div class="aiq-wm ${role}">${av}<div><div class="aiq-wm-body">${isU?esc(content):fmtMd(content)}</div>${metaHtml}</div></div>`;
  area.scrollTop=1e9;
}
function showWidgetTyping(){
  document.getElementById('aiqMsgs').innerHTML+='<div class="aiq-wm assistant" id="aiqTyp"><div class="aiq-wm-av" style="background:#14b8a6">IQ</div><div class="aiq-wm-body"><div class="aiq-w-typing"><span></span><span></span><span></span></div></div></div>';
  document.getElementById('aiqMsgs').scrollTop=1e9;
}
function removeWidgetTyping(){document.getElementById('aiqTyp')?.remove()}
function esc(s){const d=document.createElement('div');d.textContent=s;return d.innerHTML}
function fmtMd(t){
  return t.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
    .replace(/\*\*(.+?)\*\*/g,'<strong>$1</strong>')
    .replace(/`([^`]+)`/g,'<code>$1</code>')
    .replace(/\[([^\]]+)\]\((https?:\/\/[^)]+)\)/g,'<a href="$2" target="_blank" style="color:#0d9488;font-weight:600;text-decoration:none">$1 ↗</a>')
    .replace(/^[-*•] (.+)$/gm,'<li>$1</li>')
    .replace(/(<li>[\s\S]*?<\/li>)/g,m=>m.startsWith('<ul>')?m:'<ul>'+m+'</ul>')
    .replace(/<\/ul>\s*<ul>/g,'')
    .replace(/\n{2,}/g,'</p><p>').replace(/\n/g,'<br>')
    .replace(/^/,'<p>').replace(/$/,'</p>')
    .replace(/<p><\/p>/g,'');
}
})();
