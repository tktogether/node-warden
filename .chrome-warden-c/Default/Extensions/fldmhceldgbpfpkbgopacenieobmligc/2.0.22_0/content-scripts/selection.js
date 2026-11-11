var selection=(function(){function e(e){return e}var t=new Set([`ArrowLeft`,`ArrowRight`,`ArrowUp`,`ArrowDown`,`Home`,`End`,`Shift`]);function n(e){return t.has(e)}function r(e){return e?e.tagName===`INPUT`||e.tagName===`TEXTAREA`||e.isContentEditable===!0:!1}function i(e){let t=(e??``).trim();return t.length>0?t:null}var a=`sidepanel_language`;function o(e){return e===`zh-CN`||e===`en`?e:null}function s(){try{return chrome.i18n.getUILanguage().toLowerCase().startsWith(`zh`)?`zh-CN`:`en`}catch{return`en`}}async function c(){try{return o((await chrome.storage.local.get(a))[a])??s()}catch{return s()}}function l(e){let t=(t,n)=>{if(n!==`local`||!(a in t))return;let r=o(t[a].newValue);r&&e(r)};return chrome.storage.onChanged.addListener(t),()=>chrome.storage.onChanged.removeListener(t)}var u=`sidepanel_theme`;function d(e){return e===`dark`||e===`system`?e:`light`}function f(e){if(e!==`system`)return e;try{return typeof window<`u`&&window.matchMedia(`(prefers-color-scheme: dark)`).matches?`dark`:`light`}catch{return`light`}}async function p(){try{return d((await chrome.storage.local.get(u))[u])}catch{return`light`}}function m(e){let t=(t,n)=>{n!==`local`||!(u in t)||e(d(t[u].newValue))};return chrome.storage.onChanged.addListener(t),()=>chrome.storage.onChanged.removeListener(t)}var h={"zh-CN":`Kimi 一下`,en:`Kimi it`};function g(e){return Math.min(255,Math.max(0,Math.round(e)))}function _(e){if(e===void 0||e.trim()===``)return 1;let t=e.trim(),n=t.endsWith(`%`)?Number.parseFloat(t)/100:Number.parseFloat(t);return Number.isFinite(n)?n:1}function v(e){let t=e.trim(),n=t.endsWith(`%`)?Number.parseFloat(t)/100*255:Number.parseFloat(t);return Number.isFinite(n)?g(n):null}function y(e){if(!e)return null;let t=e.trim().toLowerCase();if(!t||t===`transparent`)return null;let n=t.match(/^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i);if(n){let e=n[1],t=e.length<=4?e.split(``).map(e=>`${e}${e}`).join(``):e;return t.length===8&&Number.parseInt(t.slice(6,8),16)<=2?null:{red:Number.parseInt(t.slice(0,2),16),green:Number.parseInt(t.slice(2,4),16),blue:Number.parseInt(t.slice(4,6),16)}}let r=t.match(/^rgba?\((.*)\)$/i);if(!r)return null;let[i,a]=r[1].split(`/`).map(e=>e.trim()),o=i.includes(`,`),s=i.split(o?`,`:/\s+/).map(e=>e.trim()).filter(Boolean);if(s.length<3||_(a??(o?s[3]:void 0))<=.01)return null;let c=s.slice(0,3).map(v);return c.some(e=>e===null)?null:{red:c[0],green:c[1],blue:c[2]}}function b(e){for(let t of e){let e=y(t);if(e)return e}return null}var x=`<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M11 2H13V3H11V2Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M10 3H11V4H10V3Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M9 4H10V6H9V4Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M8 6H9V8H8V6Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M11.5 7H12.5V14H11.5V7Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M11.5 16H12.5V18H11.5V16Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M11.5 16.5V17.5H11V16.5H11.5Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M13 16.5V17.5H12.5V16.5H13Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M7 8H8V10H7V8Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M6 10H7V12H6V10Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M5 12H6V14H5V12Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M18 12H19V14H18V12Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M19 14H20V16H19V14Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M4 14H5V16H4V14Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M3 16H4V18H3V16Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M2 18H3V19H2V18Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M3 19H4V20H3V19Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M20 19H21V20H20V19Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M21 18H22V19H21V18Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M4 20H20V21H4V20Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M20 16H21V18H20V16Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M14 4H15V6H14V4Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M15 6H16V8H15V6Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M16 8H17V10H16V8Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M17 10H18V12H17V10Z" fill="currentColor" fill-opacity="0.45"/>
<path d="M13 3H14V4H13V3Z" fill="currentColor" fill-opacity="0.45"/>
</svg>
`,S=`<svg width="48" height="48" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="ka-g0" x1="38.8001" y1="33.0086" x2="25.6404" y2="23.5806" gradientUnits="userSpaceOnUse">
      <stop stop-color="#9EF7FF" stop-opacity="0.2"/>
      <stop offset="1" stop-color="#79D4FF" stop-opacity="0.2"/>
    </linearGradient>
    <linearGradient id="ka-g1" x1="22.4984" y1="23.9939" x2="29.0903" y2="0.580508" gradientUnits="userSpaceOnUse">
      <stop stop-color="#8CBAFF" stop-opacity="0.2"/>
      <stop offset="1" stop-color="#C0A0FF" stop-opacity="0.2"/>
    </linearGradient>
    <linearGradient id="ka-g2" x1="19.0224" y1="23.7554" x2="41.1093" y2="8.99934" gradientUnits="userSpaceOnUse">
      <stop stop-color="white" stop-opacity="0.2"/>
      <stop offset="1" stop-color="#93B7FF" stop-opacity="0.2"/>
    </linearGradient>
    <linearGradient id="ka-g3" x1="1.80421e-06" y1="41.6" x2="37.6158" y2="-3.12" gradientUnits="userSpaceOnUse">
      <stop stop-color="#2389FF"/>
      <stop offset="0.511533" stop-color="#2389FF"/>
      <stop offset="1" stop-color="#2389FF"/>
    </linearGradient>
    <radialGradient id="ka-g4" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(19.24 16.8981) scale(19.4762)">
      <stop stop-color="#117DFB"/>
      <stop offset="0.759254" stop-color="#449BFF"/>
      <stop offset="1" stop-color="#77B6FF"/>
    </radialGradient>
  </defs>
  <!-- v0: cyan sheen, rotated -0.73deg about its box center -->
  <g transform="translate(26.2656 25.9656) rotate(-0.73) translate(-20.5682 -20.7999)">
    <path d="M20.5682 0C31.9277 0 41.1364 9.31244 41.1364 20.7999C41.1364 32.2874 31.9277 41.5999 20.5682 41.5999C9.20871 41.5999 0 32.2874 0 20.7999C0 9.31244 9.20871 0 20.5682 0Z" fill="url(#ka-g0)"/>
  </g>
  <!-- v1: violet sheen -->
  <g transform="translate(3.4896 1.392)">
    <path d="M21.255 0C32.9938 0 42.51 9.64714 42.51 21.5475C42.51 33.4479 32.9938 43.095 21.255 43.095C9.51619 43.095 0 33.4479 0 21.5475C0 9.64714 9.51619 0 21.255 0Z" fill="url(#ka-g1)"/>
  </g>
  <!-- v2: white-blue sheen, rotated 172.44deg about its box center -->
  <g transform="translate(23.772 25.0152) rotate(172.44) translate(-22.1649 -21.2874)">
    <path d="M22.1649 0C34.4063 0 44.3299 9.5307 44.3299 21.2874C44.3299 33.0442 34.4063 42.5749 22.1649 42.5749C9.92359 42.5749 0 33.0442 0 21.2874C0 9.5307 9.92359 0 22.1649 0Z" fill="url(#ka-g2)"/>
  </g>
  <!-- v3: flat base sphere -->
  <g transform="translate(5.3088 5.0928)">
    <path d="M19.24 0C29.866 0 38.48 8.61405 38.48 19.24C38.48 29.866 29.866 38.48 19.24 38.48C8.61405 38.48 0 29.866 0 19.24C0 8.61405 8.61405 0 19.24 0Z" fill="url(#ka-g3)"/>
  </g>
  <!-- v4: radial sphere -->
  <g transform="translate(5.3088 5.0928)">
    <path d="M19.24 0C29.866 0 38.48 8.61405 38.48 19.24C38.48 29.866 29.866 38.48 19.24 38.48C8.61405 38.48 0 29.866 0 19.24C0 8.61405 8.61405 0 19.24 0Z" fill="url(#ka-g4)"/>
  </g>
  <!-- v5: left eye, rotated -7.82deg -->
  <g transform="translate(24.8952 18.5064) rotate(-7.82) translate(-2.43444 -4.51751)" style="mix-blend-mode:luminosity">
    <path d="M0 2.45395C0 1.09867 1.08993 0 2.43444 0C3.77894 0 4.86887 1.09867 4.86887 2.45395V6.58106C4.86887 7.93633 3.77894 9.03501 2.43444 9.03501C1.08993 9.03501 0 7.93633 0 6.58106V2.45395Z" fill="white"/>
  </g>
  <!-- v6: right eye, rotated -7.82deg -->
  <g transform="translate(34.7616 17.1528) rotate(-7.82) translate(-2.191 -4.29165)" style="mix-blend-mode:luminosity">
    <path d="M0 2.33126C0 1.04374 0.980941 0 2.191 0C3.40106 0 4.382 1.04374 4.382 2.33126V6.25202C4.382 7.53955 3.40106 8.58329 2.191 8.58329C0.980941 8.58329 0 7.53955 0 6.25202V2.33126Z" fill="white"/>
  </g>
</svg>
`;function C(e,t,n){if(e>=t)return t;let r=420+(t-e)*1;return Math.min(t,e+Math.max(1,r*n/1e3))}function w(e,t){if(t<=0||t>=e.length)return t;let n=e.charCodeAt(t-1);return n>=55296&&n<=56319?t-1:t}function T(e){let t=0,n=null;return typeof requestAnimationFrame==`function`&&(t=requestAnimationFrame(r=>{t=0,n!==null&&(clearTimeout(n),n=null),e(r)})),n=setTimeout(()=>{n=null,t&&=(cancelAnimationFrame(t),0),e(performance.now())},250),()=>{t&&cancelAnimationFrame(t),n!==null&&clearTimeout(n)}}var E=x.replace(/>\s+</g,`><`).trim(),D=`data:image/svg+xml,${encodeURIComponent(S)}`,ee={light:{bg:`#ffffff`,line:`rgba(0, 0, 0, 0.13)`,text:`rgba(0, 0, 0, 0.9)`,mid:`rgba(0, 0, 0, 0.6)`,dim:`rgba(0, 0, 0, 0.45)`,"fill-1":`rgba(0, 0, 0, 0.03)`,"fill-2":`rgba(0, 0, 0, 0.05)`,accent:`rgba(0, 0, 0, 0.9)`,"accent-hover":`rgba(37, 37, 37, 1)`,"accent-ink":`#ffffff`,error:`#ff3849`,shadow:`0 4px 16.4px rgba(0, 0, 0, 0.1)`},dark:{bg:`#292929`,line:`rgba(255, 255, 255, 0.12)`,text:`rgba(255, 255, 255, 0.84)`,mid:`rgba(255, 255, 255, 0.56)`,dim:`rgba(255, 255, 255, 0.42)`,"fill-1":`rgba(255, 255, 255, 0.06)`,"fill-2":`rgba(255, 255, 255, 0.1)`,accent:`rgba(255, 255, 255, 0.84)`,"accent-hover":`#ffffff`,"accent-ink":`rgba(0, 0, 0, 0.9)`,error:`#ff4756`,shadow:`0 4px 16px rgba(0, 0, 0, 0.4)`}};function te(e){return Object.entries(e).map(([e,t])=>`--${e}: ${t};`).join(` `)}var ne=`"PingFang SC", -apple-system, BlinkMacSystemFont, "Segoe UI", "Hiragino Sans GB", "Microsoft YaHei", Helvetica, Arial, "Apple Color Emoji", "Segoe UI Emoji", sans-serif`,re=`0.2s`,O=`150ms`,k=480,A=20,j=20,M=24,N=8,P=12,F=44,I=16,ie=j+N*M+P+F+I,L=8,R=ie,z=j+M+P+F+I;function ae(e,t,n,r){let i=(e,t,n)=>Math.min(Math.max(e,t),Math.max(t,n));return{width:e===`s`?t.width:i(t.width+n.x,Math.min(240,t.width),r.width),height:e===`e`?t.height:i(t.height+n.y,Math.min(z,t.height),r.height)}}function oe(e,t,n){let r=(e,t,n)=>Math.max(Math.min(e,t),Math.min(n,e)),i=(e,t)=>Math.max(L,Math.min(e,t)),a=r(e.width,t.width-2*L,240),o=e.height===null?null:r(e.height,t.height-2*L,z),s=null,c=()=>o??(s??=n(a)),l=e.bottom==null?e.top:e.bottom-c();return{left:i(e.left,t.width-L-a),top:i(l,t.height-L-c()),width:a,height:o}}function se(){let e=document.compatMode===`CSS1Compat`?document.documentElement:null;return{width:e?.clientWidth||window.innerWidth,height:e?.clientHeight||window.innerHeight}}var ce=200,le={"zh-CN":{loading:`正在解释…`,failed:`这次没能解释出来，去侧边栏重试`,interrupted:`回答中断了，可以去侧边栏继续`,followUp:`继续追问`,send:`去侧边栏继续`,signedOut:`前往侧边栏登录，解锁划词解释`,signIn:`登录`,quota:`本周期额度已用完，可升级会员或待额度刷新后重试`,upgrade:`升级会员`},en:{loading:`Explaining…`,failed:`Couldn't explain this. Try again in the side panel`,interrupted:`The answer was cut off. Continue in the side panel`,followUp:`Ask a follow-up`,send:`Continue in side panel`,signedOut:`Log in from the side panel to explain your selection`,signIn:`Log in`,quota:`Kimi Member credits for this cycle are used up — upgrade or wait for the reset, then retry`,upgrade:`Upgrade`}};function ue(e){let t=document.createElement(`kimi-selection-explain`),n=t.attachShadow({mode:`closed`}),r=e.side===`above`,i=r?-10:10,a=document.createElement(`style`);a.textContent=`
    :host { all: initial; }
    /* The spec's popover: solid, a 0.5px hairline, radius.xl and a small lift. */
    .card {
      ${te(ee.light)}
      position: fixed;
      z-index: 2147483647;
      box-sizing: border-box;
      /* A narrow viewport narrows it through fitCard, not a max-width. */
      width: ${k}px;
      max-height: ${ie}px;
      display: flex;
      flex-flow: column;
      overflow: hidden;
      border: 0.5px solid var(--line);
      border-radius: 16px;
      background: var(--bg);
      box-shadow: var(--shadow);
      color: var(--text);
      font-family: ${ne};
      opacity: 0;
      transform: translateY(${i}px);
      transition: opacity ${re} ease, transform ${re} ease;
    }
    .card.dark { ${te(ee.dark)} color-scheme: dark; }
    .card.shown { opacity: 1; transform: translateY(0); }
    .card.hiding { opacity: 0; transform: translateY(${i}px); }
    .handle { height: ${j}px; flex-shrink: 0; cursor: grab; }
    .handle:active { cursor: grabbing; }
    /* The answer, cut where the box ends rather than scrolled: eight lines at
       rest, more once an edge is pulled, and a fade over the last of them
       while there is more below. */
    .body {
      position: relative;
      flex: 1;
      min-height: 0;
      overflow: hidden;
      margin: 0 ${A}px;
      font-size: 15px;
      line-height: ${M}px;
      color: var(--text);
      white-space: pre-wrap;
      overflow-wrap: anywhere;
    }
    .body.muted { color: var(--mid); }
    .body.clipped::after {
      content: '';
      position: absolute;
      left: 0;
      right: 0;
      bottom: 0;
      height: 40px;
      background: linear-gradient(transparent, var(--bg));
      pointer-events: none;
    }
    /* Resize grips: invisible, in the card's own edge margins — the right
       padding beside the answer, the padding under the launcher — so they sit
       on no control. */
    .grip { position: absolute; z-index: 10; }
    .grip-e { top: 12px; bottom: 12px; right: 0; width: 4px; cursor: ew-resize; }
    .grip-s { left: 12px; right: 12px; bottom: 0; height: 6px; cursor: ns-resize; }
    .grip-se { right: 0; bottom: 0; width: 8px; height: 8px; cursor: nwse-resize; }
    /* The spec's launcher: a filled field, no stroke, and a round send key. */
    .ask {
      display: flex;
      align-items: center;
      gap: 8px;
      flex-shrink: 0;
      box-sizing: border-box;
      height: ${F}px;
      margin: ${P}px ${A}px ${I}px;
      padding: 0 8px 0 14px;
      border-radius: 10px;
      background: var(--fill-1);
    }
    .ask input {
      flex: 1;
      min-width: 0;
      border: none;
      outline: none;
      background: transparent;
      font-family: inherit;
      font-size: 14px;
      line-height: 20px;
      padding: 0;
      color: var(--text);
    }
    .ask input::placeholder { color: var(--dim); }
    /* Idle as the spec draws it; with something typed it turns into the
       panel's primary send key, and so it does under the pointer — an empty
       launcher still acts (see launch). */
    button.send {
      flex-shrink: 0;
      width: 28px;
      height: 28px;
      padding: 0;
      border: none;
      border-radius: 50%;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      background: var(--fill-2);
      color: var(--dim);
      transition: background-color ${O} ease, color ${O} ease;
    }
    button.send.ready { background: var(--accent); color: var(--accent-ink); }
    button.send:hover,
    button.send:focus-visible {
      background: var(--accent-hover);
      color: var(--accent-ink);
      outline: none;
    }
    /* Signed out, or refused for spent credits, the launcher's slot holds the
       way forward instead, on the answer's left edge, 12 under the line it
       acts on. Signed out: the panel's primary button at its card-action size
       of 32. Quota: the panel's notice button (.wb-btn--26), as the
       sidepanel's quota notice draws its 升级会员. */
    .door { display: none; flex-shrink: 0; padding: ${P}px ${A}px ${I}px; }
    .card.signed-out .ask, .card.quota .ask { display: none; }
    .card.signed-out .door, .card.quota .door { display: flex; }
    button.small {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      box-sizing: border-box;
      min-width: 52px;
      height: 26px;
      padding: 4px 8px;
      border: none;
      border-radius: 8px;
      cursor: pointer;
      font-family: inherit;
      font-size: 12px;
      font-weight: 500;
      line-height: 18px;
      white-space: nowrap;
      transition: background-color ${O} ease;
    }
    button.small.primary-small { background: var(--accent); color: var(--accent-ink); }
    button.small.primary-small:hover,
    button.small.primary-small:focus-visible { background: var(--accent-hover); outline: none; }
    button.primary {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      box-sizing: border-box;
      min-width: 62px;
      height: 32px;
      padding: 6px 10px;
      border: none;
      border-radius: 10px;
      cursor: pointer;
      background: var(--accent);
      color: var(--accent-ink);
      font-family: inherit;
      font-size: 14px;
      font-weight: 500;
      line-height: 20px;
      white-space: nowrap;
      transition: background-color ${O} ease;
    }
    button.primary:hover,
    button.primary:focus-visible { background: var(--accent-hover); outline: none; }
    /* The run's tail, as the sidepanel keeps it: ONE row where the answer
       ends — its WorkingIndicator (mascot and a breathing label) while the
       answer is on its way, its error notice when it stopped short — never
       chrome on the answer itself. Before the first token that is the top of
       the box, where the answer will appear. Sticky to the bottom of the
       answer's box, so an answer cut at eight lines still shows it, the text
       fading out above it. 8px (spacing.sm) under the answer — nearer to it
       than the launcher is (12), so it reads as the answer's own status. */
    .tail {
      position: sticky;
      bottom: 0;
      z-index: 1;
      padding-top: 8px;
      background: linear-gradient(to bottom, transparent, var(--bg) 8px);
      white-space: normal;
    }
    .tail:empty { display: none; }
    /* With no answer yet — waiting on it, or failed before it came — the row
       IS the answer's place, so it starts where the answer would. */
    .card:not(.answered) .tail { padding-top: 0; background: var(--bg); }
    .working { display: inline-flex; align-items: center; gap: 8px; }
    .working img { width: 16px; height: 16px; flex: none; }
    .working span {
      color: var(--mid);
      font-size: 14px;
      line-height: 20px;
      animation: breathe 1.6s ease-in-out infinite;
    }
    @keyframes breathe { 0%, 100% { opacity: 1; } 50% { opacity: 0.45; } }
    /* A failed or cut-off answer, as the design system words feedback
       (kimi-design-skill Toast, type error): the semantic colour is the
       icon's alone — ErrorIcon in color.status.danger — and the line is plain
       typography.webUI.b2Regular in color.labels.secondary, with no frame and
       no tinted fill (Toast: only the icon colour changes by type). The
       Toast's floating dark frame is left out: this is in place, inside the
       card. Its metrics are the Toast's — a 20px icon, 8px to the text, the
       icon keeping to the first line when the line wraps. */
    .notice {
      display: flex;
      align-items: flex-start;
      gap: 8px;
      color: var(--mid);
      font-size: 14px;
      line-height: 20px;
    }
    .notice svg { flex: none; width: 20px; height: 20px; color: var(--error); }
    /* Motion off keeps the label still and readable, as the panel's does. */
    @media (prefers-reduced-motion: reduce) {
      .card { transition: none; }
      .working span { animation: none; }
    }
    @media print { :host { display: none; } }
  `;let o=document.createElement(`div`);o.className=e.theme===`dark`?`card dark`:`card`,o.setAttribute(`role`,`dialog`),o.setAttribute(`aria-label`,e.labels.loading);let s=document.createElement(`div`);s.className=`handle`;let c=[`e`,`s`,`se`].map(e=>{let t=document.createElement(`div`);return t.className=`grip grip-${e}`,{edge:e,grip:t}}),l=document.createElement(`div`);l.className=`body`;let u=document.createElement(`span`);u.setAttribute(`aria-live`,`polite`);let d=document.createElement(`div`);d.className=`tail`,l.append(u,d);let f=document.createElement(`div`);f.className=`working`,f.setAttribute(`role`,`status`),f.setAttribute(`aria-live`,`polite`);let p=document.createElement(`img`);p.src=D,p.alt=``,p.setAttribute(`aria-hidden`,`true`);let m=document.createElement(`span`);m.textContent=e.labels.loading,f.append(p,m);let h=e=>{let t=document.createElement(`div`);t.className=`notice`,t.setAttribute(`role`,`alert`),t.innerHTML=E,t.firstElementChild?.setAttribute(`aria-hidden`,`true`);let n=document.createElement(`span`);return n.textContent=e,t.append(n),t},g=e=>{d.replaceChildren(...e?[e]:[]),K()},_=document.createElement(`div`);_.className=`ask`;let v=document.createElement(`input`);v.type=`text`,v.placeholder=e.labels.followUp,v.setAttribute(`aria-label`,e.labels.followUp);let y=document.createElement(`button`);y.type=`button`,y.className=`send`,y.setAttribute(`aria-label`,e.labels.send),y.title=e.labels.send,y.innerHTML=`<svg width="16" height="16" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M5 12h14M12 5l7 7-7 7" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>`,v.addEventListener(`input`,()=>{y.classList.toggle(`ready`,v.value.trim().length>0)}),_.append(v,y);let b=document.createElement(`div`);b.className=`door`;let x=(e,t,n)=>{let r=document.createElement(`button`);return r.type=`button`,r.className=e,r.textContent=t,r.addEventListener(`click`,e=>{e.stopPropagation(),n()}),r};o.append(s,l,_,b,...c.map(e=>e.grip)),n.append(a,o);let S={left:e.x,top:e.y,width:k,height:null,bottom:r?e.y:null},N=!1,R=()=>{let e=oe(S,se(),e=>(o.style.width=`${e}px`,o.offsetHeight));return o.style.width=`${e.width}px`,e.height!==null&&(o.style.height=`${e.height}px`),o.style.left=`${e.left}px`,o.style.top=`${e.top}px`,e},z=()=>{let{left:e,top:t}=R();S=S.bottom==null?{...S,left:e,top:t}:{...S,left:e}},le=()=>{R()},ue=(t,n,r=0)=>{let i=document.createElement(`span`);i.style.cssText=`position:absolute;visibility:hidden;white-space:nowrap;font-size:${n}px;`,i.textContent=t,l.append(i);let a=i.getBoundingClientRect().width;i.remove(),S={...S,left:N?S.left:e.x,width:Math.max(240,Math.min(k,Math.ceil(a+r)+2*A+3))},z()},B=``,V=0,H=null,U=null,W=!1,G=()=>{if(H)return;let e=performance.now(),t=n=>{if(H=null,W)return;let r=Math.min(100,n-e);if(e=n,V=C(V,B.length,r),u.textContent=B.slice(0,w(B,Math.floor(V))),V<B.length){H=T(t);return}u.removeAttribute(`aria-busy`);let i=U;U=null,i?.()};H=T(t)},K=()=>{l.classList.toggle(`clipped`,l.scrollHeight>l.clientHeight+1)},q=typeof ResizeObserver>`u`?null:new ResizeObserver(()=>{K(),S.bottom!=null&&R()});q?.observe(l),q?.observe(u),q?.observe(o),g(f);let J=()=>{W||(W=!0,H?.(),q?.disconnect(),document.removeEventListener(`mousedown`,de,!0),document.removeEventListener(`keydown`,Y,!0),window.removeEventListener(`resize`,le),o.classList.add(`hiding`),setTimeout(()=>t.remove(),ce),e.onDismiss())},de=e=>{e.composedPath().includes(t)||J()},Y=e=>{e.key===`Escape`&&J()},fe=()=>{e.onFollowUp(v.value.trim())};s.addEventListener(`mousedown`,e=>{e.preventDefault();let t=o.getBoundingClientRect(),n=e.clientX-t.left,r=e.clientY-t.top,i=e=>{N=!0,S={...S,left:e.clientX-n,top:e.clientY-r,bottom:null},z()},a=()=>{document.removeEventListener(`mousemove`,i,!0),document.removeEventListener(`mouseup`,a,!0)};document.addEventListener(`mousemove`,i,!0),document.addEventListener(`mouseup`,a,!0)});for(let{edge:e,grip:t}of c)t.addEventListener(`mousedown`,t=>{t.preventDefault(),t.stopPropagation();let n=o.getBoundingClientRect(),r={width:n.width,height:n.height},i=se(),a={width:i.width-L-n.left,height:i.height-L-n.top},s=t.clientX,c=t.clientY;o.style.maxHeight=`none`,N=!0,S={...S,top:parseFloat(o.style.top),height:r.height,bottom:null},R();let l=t=>{let n=ae(e,r,{x:t.clientX-s,y:t.clientY-c},a);S={...S,...n},R()},u=()=>{document.removeEventListener(`mousemove`,l,!0),document.removeEventListener(`mouseup`,u,!0)};document.addEventListener(`mousemove`,l,!0),document.addEventListener(`mouseup`,u,!0)});return y.addEventListener(`click`,e=>{e.stopPropagation(),fe()}),v.addEventListener(`keydown`,e=>{e.stopPropagation(),e.key===`Enter`&&!e.isComposing&&(e.preventDefault(),fe())}),document.addEventListener(`mousedown`,de,!0),document.addEventListener(`keydown`,Y,!0),window.addEventListener(`resize`,le),(document.body??document.documentElement).appendChild(t),z(),requestAnimationFrame(()=>{o.classList.add(`shown`)}),{appendText(e){W||e.length===0||(B.length===0&&(o.classList.add(`answered`),u.setAttribute(`aria-busy`,`true`)),B+=e,G())},finish(t){if(!W){if(t===`signed-out`){g(null),o.classList.add(`signed-out`),o.setAttribute(`aria-label`,e.labels.signedOut),l.classList.add(`muted`),u.textContent=e.labels.signedOut,b.replaceChildren(x(`primary`,e.labels.signIn,e.onSignIn)),ue(e.labels.signedOut,15),K();return}if(t===`quota`){o.classList.add(`quota`),o.setAttribute(`aria-label`,e.labels.quota),g(h(e.labels.quota)),b.replaceChildren(x(`small primary-small`,e.labels.upgrade,e.onUpgrade)),ue(e.labels.quota,14,28);return}if(g(null),B.length>0){if(t===`failed`){let t=()=>g(h(e.labels.interrupted));V>=B.length?t():U=t}return}t===`failed`?g(h(e.labels.failed)):J()}},dismiss:J}}var B=`selection-explain`,V=2/3,H=2,U=1;function W(e){return e<128?e>=97&&e<=122||e>=65&&e<=90?.18:e===32||e===10||e===9||e===13?.35:e>=48&&e<=57?.7:.75:e===160?.35:e>=44032&&e<=55215||e>=4352&&e<=4607||e>=12592&&e<=12687||e>=12352&&e<=12543?1:e>=11904&&e<=40959||e>=63744&&e<=64255||e>=65072&&e<=65103||e>=65280&&e<=65519?.65:e>=3584&&e<=3839?.8:e>=1024&&e<=1327?.4:e>=1536&&e<=1791||e>=1872&&e<=1919||e>=64336&&e<=65023||e>=65136&&e<=65279?.5:e>=880&&e<=1023||e>=7936&&e<=8191||e>=1424&&e<=1535||e>=2304&&e<=3583?.62:e>=192&&e<=591||e>=7680&&e<=7935?1.7:1}function G(e){let t=0;for(let n=0;n<e.length;n++)t+=W(e.charCodeAt(n));return t}var K=/(?:[。！？!?．.…]["'”’」』）)\]]*|\n)\s*$/,q;function J(e){q===void 0&&(q=typeof Intl<`u`&&`Segmenter`in Intl?new Intl.Segmenter(void 0,{granularity:`sentence`}):null);let t=q?Array.from(q.segment(e),e=>e.segment):e.split(/(?<=[。！？!?\n])/),n=[];for(let e of t)n.length>0&&e.trim()===``?n[n.length-1]+=e:n.push(e);return n}function de(e,t,n){let r=0,i=0;for(;i<e.length;){let a=G(n===`end`?e[e.length-1-i]:e[i]);if(r+a>t)break;r+=a,i++}return n===`end`?e.slice(e.length-i):e.slice(0,i)}function Y(e,t,n,r,i,a,o){let s=J(e),c=i===`before`?s.map((e,t)=>s.length-1-t):s.map((e,t)=>t),l=``,u=0,d=0,f=!1;for(let[e,o]of c.entries()){let c=s[o],p=e===0&&a,m=G(c);if(u+m>t&&!p&&d>=r)break;if(u+m>n){let e=de(c,n-u,i===`before`?`end`:`start`);l=i===`before`?e+l:l+e,f=!0;break}l=i===`before`?c+l:l+c,u+=m,p||d++}let p=i===`before`?e.slice(0,e.length-l.length):e.slice(l.length);return{text:i===`before`?l.replace(/^\s+/,``):l.replace(/\s+$/,``),cut:f||o||p.trim().length>0}}function fe(e,t,n,r=800){let i=e.slice(t,n),a=e.slice(0,t),o=e.slice(n),s=r*V,c=r-s,l=G(a),u=G(o);l<s&&(c+=s-l,s=l),u<c&&(s+=c-u,c=u);let d=Math.ceil(r*8),f=a.length>d?a.slice(a.length-d):a,p=o.length>d?o.slice(0,d):o,m=J(f).at(-1)??``,h=Y(f,s,r,H,`before`,!K.test(m),f.length<a.length),g=Y(p,c,r,U,`after`,!K.test(i),p.length<o.length);return`${h.cut?`…`:``}${h.text}⟦${i}⟧${g.text}${g.cut?`…`:``}`}var pe=new Set([`inline`,`inline-block`,`inline-flex`,`inline-grid`,`contents`]),me={isInline:e=>pe.has(getComputedStyle(e).display),isVisible:e=>e.getClientRects().length>0||getComputedStyle(e).display===`contents`},he=[`#mw-content-text`,`.markdown-body`,`main article`,`article`,`[role="main"]`,`main`,`#content`],ge=[`nav`,`aside`,`header`,`footer`,`[role="navigation"]`,`[role="banner"]`,`[role="contentinfo"]`,`[role="complementary"]`,`[aria-hidden="true"]`,`.infobox`,`.hatnote`,`.ambox`,`.metadata`,`.noprint`,`.navbox`,`.mw-editsection`].join(`, `),_e=new Set([`script`,`style`,`noscript`,`template`,`svg`,`math`,`button`,`select`,`textarea`]),ve=`h1, h2, h3, h4, h5, h6`;function X(e,t){let n=e.replace(/\s+/g,` `).trim();return n.length>t?`${n.slice(0,t)}…`:n}function Z(e,t){let n=t.replace(/\s+/g,` `);return e===``||/\s$/.test(e)?n.replace(/^ /,``):n}function ye(e){return X((e.textContent??``).replace(/\[\s*(?:编辑|編輯|edit)\s*\]/gi,``),40)}function be(e,t){if(!t)return[];let n=[],r=7;for(let i=e.indexOf(t);i>=0;i--){let t=Number(e[i].localName[1]);if(t>=r)continue;let a=ye(e[i]);if(a&&n.unshift(a),r=t,t===1)break}return n.slice(-4)}function xe(e){if(!e.querySelector(`img, picture, svg, video, canvas`))return null;let t=e.querySelector(`figcaption`)?.textContent??``,n=e.querySelector(`img`)?.getAttribute(`alt`)??``,r=X(t||n,80);return r?`[Image: ${r}]`:`[Image]`}function Se(e,t=me){let n=e.startContainer.ownerDocument,r=e.commonAncestorContainer,i=r.nodeType===Node.ELEMENT_NODE?r:r.parentElement;if(!n||!i)return null;let a=n.body??n.documentElement;for(let e of he){let t=i.closest(e);if(t){a=t;break}}let o=Array.from(a.querySelectorAll(ve)).filter(n=>e.intersectsNode(n)||!n.closest(ge)&&t.isVisible(n)),s=null,c=null,l=null;for(let t of o){if(t.contains(e.startContainer)){s=t;continue}let n=e.comparePoint(t,0);if(n<0)c=t;else if(n>0){l=t;break}}let u=n.createRange();s?u.setStartBefore(s):c?u.setStartAfter(c):u.setStart(a,0),l?u.setEndBefore(l):u.setEnd(a,a.childNodes.length);let d=[],f=new Map,p=e=>{let n=f.get(e);if(n)return n;let r=e;for(;r!==a&&r.parentElement&&t.isInline(r);)r=r.parentElement;return f.set(e,r),r},m=e=>{let t=p(e);return d.length>0&&d[d.length-1].el===t||d.push({el:t,text:``}),d.length-1},h={start:null,end:null},g=!1,_=t=>{if(!t.parentElement||!t.data)return;let n=m(t.parentElement),r=d[n].text,i=Z(r,t.data);if(d[n].text=r+i,!g){if(!h.start)if(t===e.startContainer){if(!t.data.slice(e.startOffset).trim())return;h.start=[n,r.length+Z(r,t.data.slice(0,e.startOffset)).length]}else if(e.comparePoint(t,0)===0){if(!i.trim())return;h.start=[n,r.length]}else return;t===e.endContainer?(t.data.slice(0,e.endOffset).trim()&&(h.end=[n,r.length+Z(r,t.data.slice(0,e.endOffset)).length]),g=!0):e.comparePoint(t,t.length)===0?i.trim()&&(h.end=[n,r.length+i.length]):g=!0}},v=!s&&!c&&!l,y=e=>u.comparePoint(e,0)===0&&u.comparePoint(e,e.childNodes.length)===0,b=(n,r)=>{if(!r&&!u.intersectsNode(n))return;if(n.nodeType===Node.TEXT_NODE){_(n);return}if(n.nodeType!==Node.ELEMENT_NODE)return;let i=n,a=i.localName;if(_e.has(a))return;if(a===`br`){let e=m(i);d[e].text=`${d[e].text.replace(/ $/,``)}\n`;return}if(a===`img`){let e=X(i.getAttribute(`alt`)??``,80);if(e){let t=m(i);d[t].text+=Z(d[t].text,` [Image: ${e}] `)}return}if((a===`table`||a===`figure`||i.matches(ge)||!t.isVisible(i))&&!e.intersectsNode(i)){if(i.matches(ge)||!t.isVisible(i))return;if(a===`table`){let e=i.querySelector(`caption`)?.textContent??``;e.trim()&&d.push({el:i,text:`[Table: ${X(e,80)}]`});return}let e=xe(i);if(e){d.push({el:i,text:e});return}}let o=r||y(i);for(let e=i.firstChild;e;e=e.nextSibling)b(e,o)};if(b(a,v),!h.start||!h.end)return null;let[x,S]=h.start,[C,w]=h.end,T=``,E=-1,D=-1;return d.forEach((e,t)=>{let n=e.text.replace(/\s+$/,``);n&&(T&&(T+=`

`),t===x&&(E=T.length+Math.min(S,n.length)),t===C&&(D=T.length+Math.min(w,n.length)),T+=n)}),E<0||D<=E?null:{text:T,start:E,end:D,path:be(o,s??c)}}function Ce(e,t,n=800){let r=Se(e,t);if(!r)return;let i=fe(r.text,r.start,r.end,n);return(r.path.length>0?`[Section: ${r.path.join(` › `)}]\n`:``)+i}function we(e,t=window.getSelection(),n){if(!t||t.rangeCount===0||i(t.toString())!==e)return;let r=t.getRangeAt(0);try{let e=Ce(r,n);if(e)return e}catch{}return Te(r)}function Te(e){let t=e.commonAncestorContainer;for(;t&&t.nodeType!==Node.ELEMENT_NODE;)t=t.parentNode;let n=t;for(;n&&n!==document.body;){let e=getComputedStyle(n).display;if(e!==`inline`&&e!==`inline-block`)break;n=n.parentElement}let r=n?.innerText?.trim();return r&&r.length>0?r:void 0}var Ee=`data:image/png;base64,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`,Q=24,De=28,Oe=8,ke=110;function Ae(e){return{x:Math.max(e.x-De,Oe),y:Math.max(e.y-De,Oe)}}function je(e){let{focusNode:t,focusOffset:n}=e;if(!t)return null;let r=document.createRange();try{r.setStart(t,n)}catch{return null}r.collapse(!0);let i=r.getClientRects()[0];if(i)return{x:i.left,y:(i.top+i.bottom)/2};let a=e.rangeCount>0?e.getRangeAt(0).getClientRects():null,o=a&&a.length>0?a[a.length-1]:null;return o?{x:o.right,y:(o.top+o.bottom)/2}:null}function Me(e,t){let n=document.elementFromPoint(e+Q/2,t+Q/2);if(!n||n===document.body||n===document.documentElement)return!1;for(let e=n;e;e=e.parentElement){if(e===document.body||e===document.documentElement)return!1;let t=getComputedStyle(e);if(t.position===`fixed`||t.position===`sticky`||t.position===`absolute`&&t.zIndex!==`auto`)return!0}return!1}function Ne(e){let{x:t,y:n}=Ae(e.end);if(Me(t,n))return()=>{};let r=document.createElement(`kimi-selection-trigger`),i=r.attachShadow({mode:`closed`}),a=document.createElement(`style`);a.textContent=`
    :host { all: initial; }
    button {
      position: fixed;
      display: flex;
      align-items: center;
      justify-content: center;
      width: ${Q}px;
      height: ${Q}px;
      padding: 0;
      box-sizing: border-box;
      border: none;
      background: transparent;
      cursor: pointer;
      z-index: 2147483647;
      opacity: 0;
      transform: scale(0.95);
      /* Grows out of the corner nearest the pointer. */
      transform-origin: 100% 100%;
      transition:
        transform 150ms cubic-bezier(0.23, 1, 0.32, 1),
        opacity 150ms cubic-bezier(0.23, 1, 0.32, 1),
        background-color 150ms ease,
        box-shadow 150ms ease;
    }
    button.shown { opacity: 1; transform: scale(1); }
    button.shown:hover { transform: scale(1.06); }
    button.shown:active { transform: scale(0.98); }
    button.hiding {
      opacity: 0;
      transform: scale(0.97);
      transition-duration: ${ke}ms;
    }
    button:focus-visible {
      outline: 2px solid rgba(0, 0, 0, 0.9);
      outline-offset: 2px;
    }
    img { display: block; width: 100%; height: 100%; -webkit-user-drag: none; }
    @media (prefers-reduced-motion: reduce) { button { transition: none; } }
    @media print { :host { display: none; } }
  `;let o=document.createElement(`button`);o.type=`button`,o.setAttribute(`aria-label`,e.label),o.title=e.label;let s=document.createElement(`img`);s.src=Ee,s.alt=``,o.append(s),i.append(a,o),o.style.left=`${t}px`,o.style.top=`${n}px`;let c=!1,l=()=>{c||(c=!0,document.removeEventListener(`mousedown`,u,!0),document.removeEventListener(`keydown`,d,!0),document.removeEventListener(`scroll`,f,!0),o.classList.add(`hiding`),setTimeout(()=>r.remove(),ke))},u=e=>{e.composedPath().includes(r)||l()},d=e=>{e.key===`Escape`&&l()},f=()=>l();return o.addEventListener(`click`,t=>{t.stopPropagation(),e.onActivate()}),document.addEventListener(`mousedown`,u,!0),document.addEventListener(`keydown`,d,!0),document.addEventListener(`scroll`,f,!0),(document.body??document.documentElement).appendChild(r),requestAnimationFrame(()=>o.classList.add(`shown`)),l}var Pe=`selection_trigger_enabled`;async function Fe(){try{return(await chrome.storage.local.get(Pe))[Pe]!==!1}catch{return!0}}function Ie(e){let t=(t,n)=>{if(n!==`local`)return;let r=t[Pe];r&&e(r.newValue!==!1)};return chrome.storage.onChanged.addListener(t),()=>chrome.storage.onChanged.removeListener(t)}var Le=e({matches:[`<all_urls>`],allFrames:!1,runAt:`document_idle`,main(e){let t=()=>{let e=document.querySelector(`meta[name="theme-color"]`)?.content,t=document.elementFromPoint(Math.max(0,Math.round(window.innerWidth/2)),Math.max(0,Math.round(window.innerHeight/2))),n=document.querySelector(`header, nav, [role="banner"]`);return{tint:b([e,document.body?getComputedStyle(document.body).backgroundColor:null,getComputedStyle(document.documentElement).backgroundColor,t instanceof Element?getComputedStyle(t).backgroundColor:null,n instanceof Element?getComputedStyle(n).backgroundColor:null])}};chrome.runtime.onMessage.addListener((e,n,r)=>{if(e?.type===`SELECTION_CAPTURE_PING`){r(!0);return}e?.type===`WEBBRIDGE_SAMPLE_PAGE_TINT`&&r(t())});let a=null,o=null,s=`zh-CN`,u=d(void 0);c().then(e=>{s=e}),l(e=>{s=e}),p().then(e=>{u=e}),m(e=>{u=e});let g=()=>{let e=o,t=a;o=null,a=null;try{e?.disconnect()}catch{}t?.dismiss()},_=(e,t)=>{g();let n=le[s===`en`?`en`:`zh-CN`],r;try{r=chrome.runtime.connect({name:B})}catch{return}o=r;let i=t?t.bottom+8:window.innerHeight/2,c=i+R<=window.innerHeight-8,l=ue({x:t?t.left:window.innerWidth/2-480/2,y:c?i:(t?t.top:window.innerHeight/2)-8,side:c?`below`:`above`,labels:n,theme:f(u),onFollowUp:e=>{d({kind:`follow-up`,text:e}),e.length>0&&l.dismiss()},onSignIn:()=>{d({kind:`sign-in`}),l.dismiss()},onUpgrade:()=>{d({kind:`upgrade`}),l.dismiss()},onDismiss:g});a=l;let d=e=>{try{r.postMessage(e)}catch{}};r.onMessage.addListener(e=>{let t=e;!t||a!==l||(t.kind===`delta`?l.appendText(t.text):t.kind===`done`&&l.finish(t.reason))}),r.onDisconnect.addListener(()=>{a===l&&l.finish(`failed`)}),d({kind:`start`,text:e,excerpt:we(e),url:location.href,title:document.title})},v=e=>e?.composedPath().some(e=>{let t=e.tagName;return typeof t==`string`&&t.toLowerCase().startsWith(`kimi-`)})===!0,y=t=>{if(e.isInvalid||v(t)||r(document.activeElement))return;let n=i(window.getSelection()?.toString());if(n){try{chrome.runtime.sendMessage({type:`PAGE_SELECTION`,payload:{text:n,url:location.href,title:document.title}})?.catch(()=>{})}catch{}w(n,t instanceof MouseEvent?{x:t.clientX,y:t.clientY}:null)}},x=!0;Fe().then(e=>{x=e,e||C()}),Ie(e=>{x=e,e||C()});let S=null,C=()=>{},w=(e,t)=>{x&&(S!==null&&clearTimeout(S),S=setTimeout(()=>{S=null;let n=window.getSelection(),r=i(n?.toString());if(!r||r!==e)return;let a=(n?.getRangeAt(0))?.getBoundingClientRect();if(!n||!a||a.width===0&&a.height===0)return;let o=t??je(n);o&&(C(),C=Ne({end:o,label:h[s],onActivate:()=>{C(),_(e,a)}}))},150))};e.addEventListener(document,`mouseup`,y),e.addEventListener(document,`keyup`,e=>{n(e.key)&&y(e)});let T=!1;e.addEventListener(document,`selectionchange`,()=>{let e=document.activeElement;if(!(e&&e.tagName.toLowerCase().startsWith(`kimi-`))){if(!r(document.activeElement)&&i(window.getSelection()?.toString())){T=!0;return}if(T){T=!1;try{chrome.runtime.sendMessage({type:`PAGE_SELECTION_CLEARED`})?.catch(()=>{})}catch{}}}}),e.onInvalidated(()=>{S!==null&&clearTimeout(S),C(),a?.dismiss()})}}),Re={debug:(...e)=>([...e],void 0),log:(...e)=>([...e],void 0),warn:(...e)=>([...e],void 0),error:(...e)=>([...e],void 0)},ze=globalThis.browser?.runtime?.id?globalThis.browser:globalThis.chrome,Be=class e extends Event{static EVENT_NAME=$(`wxt:locationchange`);constructor(t,n){super(e.EVENT_NAME,{}),this.newUrl=t,this.oldUrl=n}};function $(e){return`${ze?.runtime?.id}:selection:${e}`}var Ve=typeof globalThis.navigation?.addEventListener==`function`;function He(e){let t,n=!1;return{run(){n||(n=!0,t=new URL(location.href),Ve?globalThis.navigation.addEventListener(`navigate`,e=>{let n=new URL(e.destination.url);n.href!==t.href&&(window.dispatchEvent(new Be(n,t)),t=n)},{signal:e.signal}):e.setInterval(()=>{let e=new URL(location.href);e.href!==t.href&&(window.dispatchEvent(new Be(e,t)),t=e)},1e3))}}}var Ue=class e{static SCRIPT_STARTED_MESSAGE_TYPE=$(`wxt:content-script-started`);id;abortController;locationWatcher=He(this);constructor(e,t){this.contentScriptName=e,this.options=t,this.id=Math.random().toString(36).slice(2),this.abortController=new AbortController,this.stopOldScripts(),this.listenForNewerScripts()}get signal(){return this.abortController.signal}abort(e){return this.abortController.abort(e)}get isInvalid(){return ze.runtime?.id??this.notifyInvalidated(),this.signal.aborted}get isValid(){return!this.isInvalid}onInvalidated(e){return this.signal.addEventListener(`abort`,e),()=>this.signal.removeEventListener(`abort`,e)}block(){return new Promise(()=>{})}setInterval(e,t){let n=setInterval(()=>{this.isValid&&e()},t);return this.onInvalidated(()=>clearInterval(n)),n}setTimeout(e,t){let n=setTimeout(()=>{this.isValid&&e()},t);return this.onInvalidated(()=>clearTimeout(n)),n}requestAnimationFrame(e){let t=requestAnimationFrame((...t)=>{this.isValid&&e(...t)});return this.onInvalidated(()=>cancelAnimationFrame(t)),t}requestIdleCallback(e,t){let n=requestIdleCallback((...t)=>{this.signal.aborted||e(...t)},t);return this.onInvalidated(()=>cancelIdleCallback(n)),n}addEventListener(e,t,n,r){t===`wxt:locationchange`&&this.isValid&&this.locationWatcher.run(),e.addEventListener?.(t.startsWith(`wxt:`)?$(t):t,n,{...r,signal:this.signal})}notifyInvalidated(){this.abort(`Content script context invalidated`),Re.debug(`Content script "${this.contentScriptName}" context invalidated`)}stopOldScripts(){document.dispatchEvent(new CustomEvent(e.SCRIPT_STARTED_MESSAGE_TYPE,{detail:{contentScriptName:this.contentScriptName,messageId:this.id}})),window.postMessage({type:e.SCRIPT_STARTED_MESSAGE_TYPE,contentScriptName:this.contentScriptName,messageId:this.id},`*`)}verifyScriptStartedEvent(e){let t=e.detail?.contentScriptName===this.contentScriptName,n=e.detail?.messageId===this.id;return t&&!n}listenForNewerScripts(){let t=e=>{!(e instanceof CustomEvent)||!this.verifyScriptStartedEvent(e)||this.notifyInvalidated()};document.addEventListener(e.SCRIPT_STARTED_MESSAGE_TYPE,t),this.onInvalidated(()=>document.removeEventListener(e.SCRIPT_STARTED_MESSAGE_TYPE,t))}},We={debug:(...e)=>([...e],void 0),log:(...e)=>([...e],void 0),warn:(...e)=>([...e],void 0),error:(...e)=>([...e],void 0)};return(async()=>{try{let{main:e,...t}=Le;return await e(new Ue(`selection`,t))}catch(e){throw We.error(`The content script "selection" crashed on startup!`,e),e}})()})();
selection;