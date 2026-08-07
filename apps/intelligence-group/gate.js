/* ============================================================
   ApplianceIQ Entitlement Gate v1
   Drop into any ecosystem app:
     <script src="https://applianceiq-intelligence-group.netlify.app/gate.js" data-app="crm"></script>
   Valid data-app keys: crm, spec_iq, iq_academy, iq_up_system,
     iq_field, product_iq, ai_coach, command_center, pim_scraper, analytics

   Behavior:
   - Reads the Supabase session (standard supabase-js localStorage key,
     or #aiq_relay= token relay hash, or igcc_token from Admin Dashboard)
   - Calls check_app_access(app_key)
   - allowed  -> exposes window.AIQ_ACCESS = {role_level, permissions, ...}
                 and fires 'aiq:access' event; app can gate features by level
   - denied   -> full-screen overlay (suspended / no entitlement / not signed in)
   Fails OPEN on network errors so an outage never bricks customer apps.
   ============================================================ */
(function () {
  var SB_URL = "https://fumwwhyozeouoqscolke.supabase.co";
  var SB_KEY = "sb_publishable_wiP3ouBdS_Qub9EMIYJK7w_eiltZHKV";
  var HUB = "https://applianceiq-intelligence-group.netlify.app/admin.html";

  var script = document.currentScript || (function () {
    var s = document.getElementsByTagName("script"); return s[s.length - 1];
  })();
  var APP = (script && script.getAttribute("data-app")) || "";
  if (!APP) return console.warn("[AIQ gate] missing data-app attribute");

  function getToken() {
    // 1. Token relay hash (cross-app SSO)
    var m = location.hash.match(/aiq_relay=([^&]+)/);
    if (m) try { return decodeURIComponent(m[1]); } catch (e) {}
    // 2. Standard supabase-js v2 session key
    try {
      var key = "sb-fumwwhyozeouoqscolke-auth-token";
      var raw = localStorage.getItem(key);
      if (raw) {
        var parsed = JSON.parse(raw);
        var tok = parsed.access_token || (parsed.currentSession && parsed.currentSession.access_token);
        if (tok) return tok;
      }
    } catch (e) {}
    // 3. Admin Dashboard token
    try { var t = localStorage.getItem("igcc_token"); if (t) return t; } catch (e) {}
    return null;
  }

  function overlay(title, msg, showSignIn) {
    var d = document.createElement("div");
    d.id = "aiq-gate-overlay";
    d.setAttribute("style",
      "position:fixed;inset:0;z-index:2147483647;background:rgba(15,31,61,.97);display:flex;align-items:center;justify-content:center;font-family:Inter,system-ui,sans-serif");
    d.innerHTML =
      '<div style="max-width:420px;background:#fff;border-radius:18px;padding:36px;text-align:center;margin:20px">' +
      '<div style="display:inline-block;width:44px;height:44px;line-height:44px;border-radius:12px;background:linear-gradient(135deg,#2563eb,#06b6d4);color:#fff;font-weight:800;font-size:17px;margin-bottom:14px">IQ</div>' +
      '<h2 style="font-size:19px;color:#0f1f3d;margin:0 0 8px">' + title + "</h2>" +
      '<p style="font-size:14px;color:#64748b;line-height:1.5;margin:0 0 22px">' + msg + "</p>" +
      (showSignIn
        ? '<a href="' + HUB + '" style="display:inline-block;background:#1a9e56;color:#fff;text-decoration:none;font-weight:600;font-size:14px;padding:12px 28px;border-radius:10px">Sign In</a>'
        : '<a href="' + HUB + '" style="font-size:13px;color:#2563eb;text-decoration:none">Contact your administrator →</a>') +
      "</div>";
    function mount() { document.body.appendChild(d); }
    if (document.body) mount(); else document.addEventListener("DOMContentLoaded", mount);
  }

  var token = getToken();
  var headers = { apikey: SB_KEY, "Content-Type": "application/json" };
  if (token) headers.Authorization = "Bearer " + token;

  fetch(SB_URL + "/rest/v1/rpc/check_app_access", {
    method: "POST", headers: headers, body: JSON.stringify({ p_app: APP })
  })
    .then(function (r) { return r.json(); })
    .then(function (res) {
      window.AIQ_ACCESS = res || {};
      document.dispatchEvent(new CustomEvent("aiq:access", { detail: res }));
      if (res && res.allowed) return;
      var reason = (res && res.reason) || "unknown";
      if (reason === "not_authenticated") {
        overlay("Sign in required", "You need an ApplianceIQ account to use this app.", true);
      } else if (reason === "suspended") {
        overlay("Access suspended", (res.organization_name || "Your organization") + "'s subscription to this app is suspended. Billing may need attention.", false);
      } else if (reason === "trial_expired") {
        overlay("Trial ended", (res.organization_name || "Your organization") + "'s trial of this app has ended.", false);
      } else if (reason === "canceled") {
        overlay("Subscription canceled", "This app is no longer part of your organization's plan.", false);
      } else if (reason === "no_entitlement") {
        overlay("Not included in your plan", "Your organization doesn't have this app yet. Ask your administrator to add it in the Admin Dashboard.", false);
      }
      // any other reason (network weirdness): fail open, no overlay
    })
    .catch(function () { /* fail open */ });
})();
