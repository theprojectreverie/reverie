export const compensationDashboardHtml=`<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"><title>Reverie | Compensation reviews</title>
<style>
:root{font-family:Inter,system-ui,Segoe UI,sans-serif;color:#eee7df;background:#111316;color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:radial-gradient(ellipse at 85% 0%,#3b293f 0,transparent 48%);min-height:100vh}.shell{max-width:1100px;margin:auto;padding:32px 24px 60px}header{display:flex;align-items:center;justify-content:space-between;gap:16px;margin-bottom:48px}.brand{font-size:13px;letter-spacing:.13em;color:#e5bd83;font-weight:700}.eyebrow{font-size:11px;text-transform:uppercase;letter-spacing:.12em;color:#a6a0a8}a{color:#e5bd83}h1{font-size:clamp(28px,5vw,46px);letter-spacing:-.04em;margin:12px 0}p{line-height:1.6;color:#b4aeb4}button,select,input{font:inherit;border:1px solid #51464c;border-radius:8px;background:#222126;color:#eee7df;padding:10px 13px}button{cursor:pointer}button:disabled{opacity:.55;cursor:default}button:not(:disabled):hover{background:#373037}.primary{background:#775747;border-color:#8b6653}.panel{background:#1b1d21;border:1px solid #343139;border-radius:16px;padding:22px;margin:18px 0}.signin{max-width:430px;margin:40px auto}.field{display:grid;gap:6px;margin:14px 0}.field label{font-size:13px;color:#c5bdba}.signin button{width:100%}.notice{border-left:3px solid #d1a06f;padding:12px 16px;background:#252124;border-radius:5px;color:#d8c8b9;font-size:14px;line-height:1.55}.toolbar{display:flex;align-items:center;gap:10px;flex-wrap:wrap}.toolbar select{flex:1;min-width:160px}.status{font-size:13px;color:#b4aeb4;line-height:1.5}.error{color:#e9a499}.hidden{display:none!important}.cards{display:grid;gap:12px;margin-top:20px}.review{border:1px solid #3d3741;border-radius:11px;background:#17181c;padding:16px;min-width:0}.review h3{font-size:17px;margin:0 0 7px;overflow-wrap:anywhere}.review .tag{display:inline-block;font-size:12px;border:1px solid #51464c;border-radius:5px;padding:3px 7px;color:#e1bd91}.review dl{display:grid;grid-template-columns:minmax(100px,160px) 1fr;gap:9px 15px;margin-bottom:0;font-size:13px}.review dt{color:#9f99a2}.review dd{margin:0;overflow-wrap:anywhere;white-space:pre-wrap}.review .unverified{color:#e5bd83}.foot{margin-top:24px;font-size:12px;color:#97929b}@media(max-width:560px){.shell{padding:22px 14px}.panel{padding:15px}header{margin-bottom:30px}.review dl{grid-template-columns:1fr;gap:5px}.review dd{margin-bottom:6px}}
</style></head><body><main class="shell"><header><div><div class="brand">REVERIE</div><div class="eyebrow">Support console</div></div><a href="/developer">Developer activity</a></header>
<section id="signin" class="panel signin"><div class="eyebrow">Restricted support access</div><h2>Sign in</h2><p>Only accounts explicitly authorized for compensation support can view these records.</p><form id="login"><div class="field"><label for="name">Player name</label><input id="name" autocomplete="username" required></div><div class="field"><label for="password">Password</label><input id="password" type="password" autocomplete="current-password" required></div><button id="submit" class="primary">Sign in</button><p id="error" class="status error" role="status"></p></form></section>
<section id="dashboard" class="hidden"><div class="eyebrow">Paid summon support</div><h1>Compensation reviews</h1><p>Inspect server-recorded claims, original rewards and past decisions.</p><div class="notice">Read-only review mode. Character delivery and decision controls are not enabled while the complete compensation workflow awaits verification. A suggested character is not proof of eligibility.</div>
<div class="panel"><div class="toolbar"><label for="filter">Status</label><select id="filter"><option value="pending_review">Pending review</option><option value="resolved">Resolved</option><option value="rejected">Rejected</option></select><button id="refresh">Refresh</button><button id="logout">Sign out</button></div><p id="status" class="status" role="status">No data loaded.</p><div id="reviews" class="cards"></div></div><div class="foot">Account and transaction identifiers are support records. Do not share them outside authorized support. Results are limited to the first 100 records per status.</div></section></main>
<script>
let token=null,generation=0;
const get=id=>document.getElementById(id),signin=get('signin'),dashboard=get('dashboard'),reviews=get('reviews'),status=get('status'),error=get('error');
const labels={pending_review:'Pending review',resolved:'Resolved',rejected:'Rejected'};
function text(tag,value,cls){const e=document.createElement(tag);e.textContent=value==null?'Not recorded':String(value);if(cls)e.className=cls;return e}
function pretty(value){return value==null?'Not recorded':String(value).replaceAll('_',' ')}
function date(value){if(!value)return 'Not recorded';const d=new Date(value);return Number.isNaN(d.getTime())?'Invalid timestamp':d.toISOString().replace('T',' ').slice(0,19)+' UTC'}
function clear(){generation++;token=null;reviews.replaceChildren();status.textContent='No data loaded.';dashboard.classList.add('hidden');signin.classList.remove('hidden');get('password').value=''}
function render(rows){
 reviews.replaceChildren();
 for(const row of rows){
  const card=text('article','', 'review');card.append(text('h3',pretty(row.banner_id)),text('span',labels[row.status]??'Unknown status','tag'));
  const dl=document.createElement('dl');
  function add(label,value,cls){dl.append(text('dt',label),text('dd',value,cls))}
  add('Requested',date(row.requested_at));add('Player reference',row.player_id);add('Summon reference',row.pull_id);add('Roll position',Number(row.roll_index)+1);add('Recorded reward',pretty(row.recorded_character));add('Featured flag',row.recorded_featured?'Yes':'No');add('Content version',row.content_version_id);
  add('Suggested character',row.suggestedCharacter?pretty(row.suggestedCharacter):'Original banner not verified',row.suggestedCharacter?'':'unverified');
  if(row.status!=='pending_review'){add('Decision time',date(row.decided_at));add('Decision note',row.decision_note);add('Delivered character',pretty(row.granted_character_id))}
  card.append(dl);reviews.append(card);
 }
}
async function refresh(){
 if(!token)return;
 const ticket=++generation,session=token,filter=get('filter').value;
 reviews.replaceChildren();status.textContent='Loading server reviews...';get('refresh').disabled=true;
 try{
  const r=await fetch('/v1/developer/compensation/reviews?status='+encodeURIComponent(filter),{headers:{Authorization:'Bearer '+session},cache:'no-store'});
  if(ticket!==generation||session!==token)return;
  if(r.status===401||r.status===403){clear();error.textContent=r.status===403?'This account does not have compensation support access.':'Session expired. Sign in again.';return}
  if(!r.ok)throw new Error('Could not load reviews.');
  const data=await r.json();if(ticket!==generation||session!==token)return;
  if(!Array.isArray(data.reviews))throw new Error('Invalid server response.');
  render(data.reviews);status.textContent=data.reviews.length===0?'No reviews in this status.':data.reviews.length+' review(s)'+(data.reviews.length===100?' (first 100)':'')+'.';
 }catch{if(ticket===generation)status.textContent='Connection unavailable. Refresh to retry.'}
 finally{if(ticket===generation)get('refresh').disabled=false}
}
get('login').addEventListener('submit',async e=>{
 e.preventDefault();error.textContent='';const button=get('submit');button.disabled=true;
 try{const r=await fetch('/v1/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({playerName:get('name').value,password:get('password').value})});
 get('password').value='';if(!r.ok)throw new Error('Sign in failed.');
 const d=await r.json();if(typeof d.accessToken!=='string')throw new Error('Sign in failed.');
 token=d.accessToken;signin.classList.add('hidden');dashboard.classList.remove('hidden');get('refresh').disabled=false;await refresh();
 }catch{clear();error.textContent='Sign in failed. Check credentials and connection.'}finally{button.disabled=false}
});
get('refresh').addEventListener('click',refresh);get('filter').addEventListener('change',refresh);
get('logout').addEventListener('click',()=>{clear();error.textContent=''});
</script></body></html>`;
