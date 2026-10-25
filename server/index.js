const express=require('express'),http=require('http'),cors=require('cors'),jwt=require('jsonwebtoken'),fs=require('fs');
const {Server}=require('socket.io');const {AccessToken}=require('livekit-server-sdk');
const SECRET=process.env.JWT_SECRET||'change-me';
const DB='db.json';
const db=fs.existsSync(DB)?JSON.parse(fs.readFileSync(DB)):{};
db.users||={};db.messages||=[];db.calls||=[];db.groups||={};db.reports||=[];db.oldNumbers||={};db.sessions||={};db.requests||=[];db.stories||=[];db.revoked||={};
const save=()=>fs.writeFileSync(DB,JSON.stringify(db));
const otps={},emailCodes={};
const crypto=require('crypto');
const B32='ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const b32enc=buf=>{let bits='',out='';for(const b of buf)bits+=b.toString(2).padStart(8,'0');for(let i=0;i<bits.length;i+=5)out+=B32[parseInt(bits.slice(i,i+5).padEnd(5,'0'),2)];return out};
const b32dec=s=>{let bits='';for(const c of s)bits+=B32.indexOf(c).toString(2).padStart(5,'0');const a=[];for(let i=0;i+8<=bits.length;i+=8)a.push(parseInt(bits.slice(i,i+8),2));return Buffer.from(a)};
const hotp=(secret,ctr)=>{const b=Buffer.alloc(8);b.writeBigUInt64BE(BigInt(ctr));const h=crypto.createHmac('sha1',b32dec(secret)).update(b).digest();const o=h[19]&15;return String((h.readUInt32BE(o)&0x7fffffff)%1000000).padStart(6,'0')};
const totpOk=(secret,code)=>{const c=Math.floor(Date.now()/30000);return [-1,0,1].some(d=>hotp(secret,c+d)===String(code||'').trim())};
Object.keys(db.revoked).forEach(k=>{if(Date.now()-db.revoked[k]>100*864e5)delete db.revoked[k]});
const sha=t=>crypto.createHash('sha1').update(t).digest('hex').slice(0,16);
const genId=()=>{let id;do{id=String(Math.floor(10000000+Math.random()*90000000))}while(Object.values(db.users).some(u=>u.userId===id));return id};
const DEF={privacyChat:false,chatTimer:86400000,blockCallShot:false,whoCanCall:'everyone',lastSeen:'everyone',typing:true,readReceipts:true,blockProfileShot:false,lockProfile:false,whoSeeProfile:'everyone',addByPhone:true,addById:true,requireApproval:false,whoStory:'contacts'};
const P=u=>({...DEF,...(u?.privacy||{})});
const allowed=(lvl,t,v)=>lvl==='everyone'||(lvl==='contacts'&&(t.contacts||[]).includes(v.phone));
const pres=(t,v)=>allowed(P(t).lastSeen,t,v)?{online:(io.sockets.adapter.rooms.get(t.phone)?.size||0)>0,last:t.lastSeenAt||0}:{hidden:true};
function notifyPresence(phone,online){
  const u=db.users[phone];if(!u)return;
  (u.contacts||[]).forEach(c=>{const v=db.users[c];if(v&&allowed(P(u).lastSeen,u,v))io.to(c).emit('presence',{phone,online,last:u.lastSeenAt||Date.now()})});
}
const safe=u=>{const {totp,...r}=u;return {...r,totpEnabled:!!totp?.enabled,privacy:P(u)}};
Object.values(db.users).forEach(u=>{u.userId||=genId();u.contacts||=[]});
const app=express();app.use(cors(),express.json({limit:'8mb'}));
const server=http.createServer(app);
const io=new Server(server,{cors:{origin:'*'}});
const UP='uploads';fs.mkdirSync(UP,{recursive:true});
app.use('/uploads',express.static(UP,{maxAge:'7d'}));
const auth=(req,res,next)=>{
  try{
    const tok=(req.headers.authorization||'').slice(7),p=jwt.verify(tok,SECRET);
    if(!db.users[p.phone]||db.users[p.phone].blocked)return res.sendStatus(401);
    const sid=sha(tok);
    if(db.revoked[sid])return res.sendStatus(401);
    const now=Date.now();
    const ss=db.sessions[sid]||(db.sessions[sid]={id:sid,phone:p.phone,device:'',created:(p.iat||0)*1000||now,last:0});
    const dev=String(req.headers['x-device']||'').slice(0,80);
    if(dev&&ss.device!==dev){ss.device=dev;ss.last=0}
    if(now-ss.last>60000){ss.last=now;save()}
    req.user=p;req.sid=sid;next();
  }catch(e){res.sendStatus(401)}
};
const dmId=(a,b)=>[a,b].sort().join('_');
const members=c=>c.startsWith('g')?(db.groups[c.slice(1)]?.members||[]):c.split('_');
const blocked=(a,b)=>!!(db.users[a]?.blocks?.includes(b)||db.users[b]?.blocks?.includes(a));

app.post('/auth/request-otp',(req,res)=>{
  const phone=String(req.body.phone||'').trim();
  if(!/^\+?\d{10,15}$/.test(phone))return res.status(400).json({error:'ফোন নম্বর সঠিক নয়'});
  const otp=String(Math.floor(100000+Math.random()*900000));
  otps[phone]={otp,exp:Date.now()+300000};
  console.log('OTP',phone,otp); // TODO: SMS provider (ধাপ ৮)
  res.json({ok:true,devOtp:process.env.DEV_OTP==='1'?otp:undefined});
});
app.post('/auth/verify',(req,res)=>{
  const {phone,otp,name,totp}=req.body,r=otps[phone];
  if(!r||r.otp!==otp||r.exp<Date.now())return res.status(400).json({error:'OTP ভুল'});
  const u0=db.users[phone];
  if(u0?.totp?.enabled&&!totpOk(u0.totp.secret,totp))return res.status(401).json({need2fa:true,error:totp?'Wrong code':undefined});
  delete otps[phone];
  const u=u0||(db.users[phone]={phone,name:name||phone,bio:'',userId:genId(),blocked:false,blocks:[],contacts:[],created:Date.now()});
  if(!u0)delete db.oldNumbers[phone];
  save();
  if(u.blocked)return res.status(403).json({error:'অ্যাকাউন্ট ব্লকড'});
  res.json({token:jwt.sign({phone},SECRET,{expiresIn:'90d'}),user:safe(u)});
});
app.get('/me',auth,(req,res)=>res.json(safe(db.users[req.user.phone])));
app.post('/me',auth,(req,res)=>{
  const u=db.users[req.user.phone],{name,bio,nationality,birthdate,userId}=req.body;
  if(userId!==undefined&&userId!==u.userId){
    if(!/^[A-Za-z0-9_]{4,20}$/.test(userId))return res.status(400).json({error:'User ID: 4-20 letters/numbers/_'});
    if(Object.values(db.users).some(x=>x.userId?.toLowerCase()===userId.toLowerCase()))return res.status(400).json({error:'User ID taken'});
    u.userId=userId;
  }
  if(name!==undefined)u.name=String(name).slice(0,60)||u.name;
  if(bio!==undefined)u.bio=String(bio).slice(0,200);
  if(nationality!==undefined)u.nationality=String(nationality).slice(0,60);
  if(birthdate!==undefined)u.birthdate=String(birthdate).slice(0,10);
  save();res.json(safe(u));
});
const changeOtps={};
function migratePhone(oldP,newP){
  const sw=p=>p===oldP?newP:p;
  const u=db.users[oldP];delete db.users[oldP];u.phone=newP;db.users[newP]=u;
  Object.values(db.users).forEach(x=>{x.contacts=(x.contacts||[]).map(sw);x.blocks=(x.blocks||[]).map(sw)});
  Object.values(db.groups).forEach(g=>{g.members=g.members.map(sw);g.owner=sw(g.owner)});
  db.messages.forEach(m=>{m.from=sw(m.from);if(!m.chat.startsWith('g')){const ps=m.chat.split('_');if(ps.includes(oldP))m.chat=dmId(...ps.map(sw))}});
  db.calls.forEach(c=>{c.from=sw(c.from);c.to=c.to.map(sw);c.joined=c.joined.map(sw)});
  db.reports.forEach(r=>{r.from=sw(r.from);r.phone=sw(r.phone)});
  db.requests.forEach(r=>{r.from=sw(r.from);r.to=sw(r.to)});
  db.stories.forEach(st=>{st.phone=sw(st.phone);const v={};Object.entries(st.views||{}).forEach(([k,t])=>{v[sw(k)]=t});st.views=v});
  delete db.oldNumbers[newP];db.oldNumbers[oldP]={ts:Date.now()};
  Object.keys(db.sessions).forEach(k=>{if(db.sessions[k].phone===oldP){delete db.sessions[k];db.revoked[k]=Date.now()}});
  save();
}
app.post('/me/phone/request',auth,(req,res)=>{
  const np=String(req.body.phone||'').trim();
  if(!/^\+\d{10,15}$/.test(np)||np===req.user.phone)return res.status(400).json({error:'bad_phone'});
  if(db.users[np])return res.status(400).json({error:'number_taken'});
  const otp=String(Math.floor(100000+Math.random()*900000));
  changeOtps[req.user.phone]={phone:np,otp,exp:Date.now()+300000};
  console.log('CHANGE-NUMBER OTP',np,otp); // TODO: SMS provider
  res.json({ok:true,devOtp:process.env.DEV_OTP==='1'?otp:undefined});
});
app.post('/me/phone/confirm',auth,(req,res)=>{
  const old=req.user.phone,r=changeOtps[old],u=db.users[old];
  if(!r||r.exp<Date.now()||r.otp!==String(req.body.otp||'').trim())return res.status(400).json({error:'wrong_code'});
  if(u.totp?.enabled&&!totpOk(u.totp.secret,req.body.totp))return res.status(401).json({need2fa:true});
  if(db.users[r.phone])return res.status(400).json({error:'number_taken'});
  delete changeOtps[old];
  migratePhone(old,r.phone);
  res.json({token:jwt.sign({phone:r.phone},SECRET,{expiresIn:'90d'}),user:safe(db.users[r.phone])});
});
const card=({phone,name,bio,avatar,cover,userId})=>({phone,name,bio,avatar,cover,userId});
app.post('/me/photo',auth,(req,res)=>{
  const {kind,data}=req.body;
  if(!['avatar','cover'].includes(kind)||!data)return res.status(400).json({error:'bad request'});
  const buf=Buffer.from(String(data),'base64');
  if(buf.length<100||buf.length>4*1024*1024)return res.status(400).json({error:'bad image size'});
  const jpg=buf[0]===0xFF&&buf[1]===0xD8,png=buf[0]===0x89&&buf[1]===0x50;
  if(!jpg&&!png)return res.status(400).json({error:'JPG/PNG only'});
  const u=db.users[req.user.phone],name=`${String(u.userId).replace(/\W/g,'')}_${kind}_${Date.now()}.${png?'png':'jpg'}`;
  fs.writeFileSync(`${UP}/${name}`,buf);
  const old=u[kind];if(old&&old.startsWith('/uploads/'))fs.unlink(`${UP}/${old.slice(9)}`,()=>{});
  u[kind]=`/uploads/${name}`;save();res.json({url:u[kind]});
});
app.get('/users/search',auth,(req,res)=>{
  const q=String(req.query.q||'').toLowerCase(),me=db.users[req.user.phone];
  res.json((me.contacts||[]).map(p=>db.users[p]).filter(u=>u&&!u.blocked&&!blocked(me.phone,u.phone)&&(u.name.toLowerCase().includes(q)||u.phone.includes(q))).map(u=>({...card(u),...pres(u,me)})));
});
app.post('/contacts/add',auth,(req,res)=>{
  const {type,value}=req.body,v=String(value||'').trim().toLowerCase(),me=db.users[req.user.phone];
  const u=Object.values(db.users).find(x=>type==='phone'?x.phone===String(value).trim():type==='email'?(x.emailVerified&&x.email?.toLowerCase()===v):x.userId?.toLowerCase()===v);
  if(type==='phone'&&!u&&db.oldNumbers[String(value).trim()])return res.status(410).json({error:'number_changed'});
  const tp=u?P(u):null;
  if(!u||u.phone===me.phone||u.blocked||blocked(me.phone,u.phone)||(type==='phone'&&!tp.addByPhone)||(type==='id'&&!tp.addById))return res.status(404).json({error:'not found'});
  if(tp.requireApproval&&!(me.contacts||[]).includes(u.phone)){
    if(!db.requests.some(r=>r.from===me.phone&&r.to===u.phone)){db.requests.push({from:me.phone,to:u.phone,ts:Date.now()});save();io.to(u.phone).emit('request',{})}
    return res.json({pending:true,user:card(u)});
  }
  [[me,u],[u,me]].forEach(([a,b])=>{a.contacts||=[];if(!a.contacts.includes(b.phone))a.contacts.push(b.phone)});
  save();res.json({user:card(u)});
});
app.get('/requests',auth,(req,res)=>res.json(db.requests.filter(r=>r.to===req.user.phone&&db.users[r.from]).map(r=>({...card(db.users[r.from]),ts:r.ts}))));
app.post('/requests/accept',auth,(req,res)=>{
  const me=db.users[req.user.phone],from=String(req.body.phone||'');
  const i=db.requests.findIndex(r=>r.from===from&&r.to===me.phone);
  if(i<0||!db.users[from])return res.sendStatus(404);
  db.requests.splice(i,1);const u=db.users[from];
  [[me,u],[u,me]].forEach(([a,b])=>{a.contacts||=[];if(!a.contacts.includes(b.phone))a.contacts.push(b.phone)});
  save();io.to(from).emit('request',{});res.json({ok:true});
});
app.post('/requests/decline',auth,(req,res)=>{
  db.requests=db.requests.filter(r=>!(r.from===String(req.body.phone||'')&&r.to===req.user.phone));save();res.json({ok:true});
});
const LV=['everyone','contacts','nobody'];
app.post('/privacy',auth,(req,res)=>{
  const u=db.users[req.user.phone];u.privacy=u.privacy||{};
  const rules={privacyChat:'b',blockCallShot:'b',whoCanCall:'l',lastSeen:'l',typing:'b',readReceipts:'b',blockProfileShot:'b',lockProfile:'b',whoSeeProfile:'l',addByPhone:'b',addById:'b',requireApproval:'b',chatTimer:'t',whoStory:'l'};
  for(const [k,v] of Object.entries(req.body||{})){
    const r=rules[k];
    if(r==='b'&&typeof v==='boolean')u.privacy[k]=v;
    else if(r==='l'&&LV.includes(v))u.privacy[k]=v;
    else if(r==='t'&&[3600000,86400000,604800000].includes(v))u.privacy[k]=v;
  }
  save();res.json(P(u));
});
app.get('/presence',auth,(req,res)=>{
  const t=db.users[String(req.query.phone||'')],v=db.users[req.user.phone];
  if(!t)return res.sendStatus(404);
  if(!(t.phone===v.phone||allowed(P(t).lastSeen,t,v)))return res.json({hidden:true});
  res.json({online:(io.sockets.adapter.rooms.get(t.phone)?.size||0)>0,last:t.lastSeenAt||0});
});
app.get('/profile',auth,(req,res)=>{
  const u=db.users[String(req.query.phone||'')],v=db.users[req.user.phone];
  if(!u)return res.sendStatus(404);
  const pr=P(u);let lvl=pr.whoSeeProfile;if(pr.lockProfile&&lvl==='everyone')lvl='contacts';
  const full=u.phone===v.phone||allowed(lvl,u,v);
  if(!full)return res.json({phone:u.phone,name:u.name,avatar:u.avatar,blockShot:pr.blockProfileShot,locked:true});
  res.json({...card(u),nationality:u.nationality,birthdate:u.birthdate,email:u.emailVerified?u.email:undefined,blockShot:pr.blockProfileShot,locked:false});
});
app.post('/email/request',auth,(req,res)=>{
  const email=String(req.body.email||'').trim().toLowerCase();
  if(!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email))return res.status(400).json({error:'Invalid email'});
  if(Object.values(db.users).some(x=>x.emailVerified&&x.email?.toLowerCase()===email&&x.phone!==req.user.phone))return res.status(400).json({error:'Email already used'});
  const code=String(Math.floor(100000+Math.random()*900000));
  emailCodes[req.user.phone]={email,code,exp:Date.now()+600000};
  console.log('EMAIL CODE',email,code); // TODO: SMTP/email service
  res.json({ok:true,devCode:process.env.DEV_OTP==='1'?code:undefined});
});
app.post('/email/verify',auth,(req,res)=>{
  const r=emailCodes[req.user.phone],u=db.users[req.user.phone];
  if(!r||r.exp<Date.now()||r.code!==String(req.body.code||'').trim())return res.status(400).json({error:'Wrong code'});
  u.email=r.email;u.emailVerified=true;delete emailCodes[req.user.phone];save();res.json({ok:true});
});
app.post('/security/totp/setup',auth,(req,res)=>{
  const u=db.users[req.user.phone];
  if(u.totp?.enabled)return res.status(400).json({error:'Already enabled'});
  const secret=b32enc(crypto.randomBytes(20));u.totp={secret,enabled:false};save();
  res.json({secret,uri:`otpauth://totp/Noor%20Video%20Calls:${encodeURIComponent(u.phone)}?secret=${secret}&issuer=Noor%20Video%20Calls`});
});
app.post('/security/totp/enable',auth,(req,res)=>{
  const u=db.users[req.user.phone];
  if(!u.totp||!totpOk(u.totp.secret,req.body.code))return res.status(400).json({error:'Wrong code'});
  u.totp.enabled=true;save();res.json({ok:true});
});
app.post('/security/totp/disable',auth,(req,res)=>{
  const u=db.users[req.user.phone];
  if(!u.totp?.enabled||!totpOk(u.totp.secret,req.body.code))return res.status(400).json({error:'Wrong code'});
  delete u.totp;save();res.json({ok:true});
});
app.get('/sessions',auth,(req,res)=>{
  res.json(Object.values(db.sessions).filter(x=>x.phone===req.user.phone).sort((a,b)=>b.last-a.last)
    .map(x=>({id:x.id,device:x.device||'Unknown device',last:x.last,created:x.created,current:x.id===req.sid})));
});
const kill=sid=>{delete db.sessions[sid];db.revoked[sid]=Date.now();io.sockets.sockets.forEach(k=>{if(k.sid===sid)k.disconnect(true)})};
app.post('/sessions/revoke',auth,(req,res)=>{
  const x=db.sessions[req.body.id];if(!x||x.phone!==req.user.phone)return res.sendStatus(404);
  kill(x.id);save();res.json({ok:true});
});
app.post('/sessions/revoke-others',auth,(req,res)=>{
  Object.values(db.sessions).filter(x=>x.phone===req.user.phone&&x.id!==req.sid).forEach(x=>kill(x.id));save();res.json({ok:true});
});
app.get('/blocked',auth,(req,res)=>{
  const u=db.users[req.user.phone];res.json((u.blocks||[]).map(p=>db.users[p]).filter(Boolean).map(card));
});
const STORY_MS=24*3600*1000;
app.post('/stories',auth,(req,res)=>{
  const me=db.users[req.user.phone],{kind,text,bg,caption,data}=req.body;
  const st={id:Date.now()+Math.random().toString(36).slice(2,6),phone:me.phone,kind:kind==='text'?'text':'image',ts:Date.now(),views:{}};
  st.exp=st.ts+STORY_MS;
  if(st.kind==='text'){
    st.text=String(text||'').trim().slice(0,400);st.bg=Number(bg)||0;
    if(!st.text)return res.status(400).json({error:'empty'});
  }else{
    const buf=Buffer.from(String(data||''),'base64');
    if(buf.length<100||buf.length>5*1024*1024)return res.status(400).json({error:'bad image size'});
    const jpg=buf[0]===0xFF&&buf[1]===0xD8,png=buf[0]===0x89&&buf[1]===0x50;
    if(!jpg&&!png)return res.status(400).json({error:'JPG/PNG only'});
    const name=`story_${String(me.userId).replace(/\W/g,'')}_${Date.now()}.${png?'png':'jpg'}`;
    fs.writeFileSync(`${UP}/${name}`,buf);
    st.url=`/uploads/${name}`;st.caption=String(caption||'').trim().slice(0,200);
  }
  db.stories.push(st);save();
  (me.contacts||[]).forEach(c=>io.to(c).emit('story',{}));
  res.json({id:st.id});
});
app.get('/stories',auth,(req,res)=>{
  const me=db.users[req.user.phone],n=Date.now(),groups={};
  db.stories.filter(x=>x.exp>n).forEach(x=>{
    const o=db.users[x.phone];if(!o)return;
    if(o.phone!==me.phone&&(!(me.contacts||[]).includes(o.phone)||blocked(me.phone,o.phone)||!allowed(P(o).whoStory,o,me)))return;
    const g=groups[o.phone]||(groups[o.phone]={phone:o.phone,name:o.name,avatar:o.avatar,mine:o.phone===me.phone,items:[]});
    g.items.push({id:x.id,kind:x.kind,url:x.url,text:x.text,bg:x.bg,caption:x.caption,ts:x.ts,exp:x.exp,seen:o.phone===me.phone||!!x.views[me.phone],views:o.phone===me.phone?Object.keys(x.views).length:undefined});
  });
  const list=Object.values(groups);
  list.forEach(g=>{g.items.sort((a,b)=>a.ts-b.ts);g.unseen=g.items.some(i=>!i.seen);g.last=g.items[g.items.length-1].ts});
  list.sort((a,b)=>(b.mine-a.mine)||(b.unseen-a.unseen)||(b.last-a.last));
  res.json(list);
});
app.post('/stories/:id/view',auth,(req,res)=>{
  const x=db.stories.find(y=>y.id===req.params.id);
  if(!x||x.phone===req.user.phone)return res.json({ok:true});
  const me=db.users[req.user.phone],o=db.users[x.phone];
  if(!o||!(me.contacts||[]).includes(o.phone)||blocked(me.phone,o.phone)||!allowed(P(o).whoStory,o,me))return res.sendStatus(403);
  if(!x.views[me.phone]){x.views[me.phone]=Date.now();save()}
  res.json({ok:true});
});
app.get('/stories/:id/viewers',auth,(req,res)=>{
  const x=db.stories.find(y=>y.id===req.params.id);
  if(!x||x.phone!==req.user.phone)return res.sendStatus(404);
  res.json(Object.entries(x.views).sort((a,b)=>b[1]-a[1]).map(([p,t])=>({...card(db.users[p]||{phone:p,name:p}),ts:t})));
});
app.post('/stories/:id/delete',auth,(req,res)=>{
  const i=db.stories.findIndex(y=>y.id===req.params.id);
  if(i<0||db.stories[i].phone!==req.user.phone)return res.sendStatus(404);
  const x=db.stories.splice(i,1)[0];if(x.url)fs.unlink(`${UP}/${x.url.slice(9)}`,()=>{});
  save();res.json({ok:true});
});
setInterval(()=>{
  const n=Date.now(),keep=[];
  db.stories.forEach(x=>{if(x.exp>n)keep.push(x);else if(x.url)fs.unlink(`${UP}/${x.url.slice(9)}`,()=>{})});
  if(keep.length!==db.stories.length){db.stories=keep;save()}
},60000);
app.post('/block',auth,(req,res)=>{
  const u=db.users[req.user.phone];u.blocks||=[];
  const i=u.blocks.indexOf(req.body.phone);
  if(req.body.on&&i<0)u.blocks.push(req.body.phone);if(!req.body.on&&i>=0)u.blocks.splice(i,1);
  save();res.json({ok:true});
});
app.post('/report',auth,(req,res)=>{
  db.reports.push({from:req.user.phone,phone:req.body.phone,reason:String(req.body.reason||'').slice(0,300),ts:Date.now()});save();res.json({ok:true});
});
app.post('/groups',auth,(req,res)=>{
  const id=String(Date.now()),me=req.user.phone;
  const m=[me,...(req.body.members||[]).filter(p=>db.users[p]&&p!==me)];
  db.groups[id]={id,name:String(req.body.name||'Group').slice(0,60),members:m,owner:me};save();
  res.json({chat:'g'+id});
});
app.post('/messages',auth,(req,res)=>{
  const me=req.user.phone,chat=String(req.body.chat||''),m=members(chat);
  const text=String(req.body.text||'').trim().slice(0,4000);
  if(!text||!m.includes(me))return res.sendStatus(400);
  if(!chat.startsWith('g')&&blocked(m[0],m[1]))return res.sendStatus(403);
  const pr=P(db.users[me]);
  const msg={id:Date.now()+Math.random().toString(36).slice(2,6),chat,from:me,text,ts:Date.now(),read:{}};
  if(pr.privacyChat)msg.exp=Date.now()+pr.chatTimer;
  db.messages.push(msg);save();
  m.forEach(p=>io.to(p).emit('message',{chat,from:me}));res.json({id:msg.id});
});
setInterval(()=>{const n=Date.now(),l=db.messages.length;db.messages=db.messages.filter(m=>!m.exp||m.exp>n);if(db.messages.length!==l)save()},30000);
app.get('/messages',auth,(req,res)=>{
  const me=req.user.phone,chat=String(req.query.chat||'');
  if(!members(chat).includes(me))return res.sendStatus(403);
  const n=Date.now(),vr=P(db.users[me]).readReceipts;
  res.json(db.messages.filter(x=>x.chat===chat&&(!x.exp||x.exp>n)).slice(-200)
    .map(x=>({id:x.id,chat:x.chat,from:x.from,text:x.text,ts:x.ts,exp:x.exp,seen:x.from===me&&vr&&Object.values(x.read||{}).some(t=>t>0)})));
});
app.post('/messages/read',auth,(req,res)=>{
  const me=req.user.phone,chat=String(req.body.chat||'');
  if(!members(chat).includes(me))return res.sendStatus(403);
  const on=P(db.users[me]).readReceipts;let ch=false;
  db.messages.forEach(m=>{if(m.chat===chat&&m.from!==me&&!(m.read&&me in m.read)){m.read=m.read||{};m.read[me]=on?Date.now():0;ch=true}});
  if(ch){save();members(chat).filter(p=>p!==me).forEach(p=>io.to(p).emit('message',{chat,read:true}))}
  res.json({ok:true});
});
app.get('/chats',auth,(req,res)=>{
  const me=req.user.phone,map={};
  Object.values(db.groups).filter(g=>g.members.includes(me)).forEach(g=>map['g'+g.id]={chat:'g'+g.id,title:g.name,members:g.members,ts:+g.id});
  db.messages.forEach(x=>{
    if(!members(x.chat).includes(me))return;
    const c=map[x.chat]||(map[x.chat]={chat:x.chat});
    if(!x.chat.startsWith('g')){c.peer=members(x.chat).find(p=>p!==me);c.title=db.users[c.peer]?.name||c.peer;c.avatar=db.users[c.peer]?.avatar}
    c.last=x.text;c.ts=x.ts;
  });
  res.json(Object.values(map).sort((a,b)=>(b.ts||0)-(a.ts||0)));
});
async function tokenFor(room,u){
  const at=new AccessToken(process.env.LIVEKIT_API_KEY,process.env.LIVEKIT_API_SECRET,{identity:u.phone,name:u.name});
  at.addGrant({roomJoin:true,room});
  return {room,token:await at.toJwt(),url:process.env.LIVEKIT_URL};
}
app.post('/call/start',auth,async(req,res)=>{
  const me=db.users[req.user.phone],room='r'+Date.now();
  const to=(req.body.to||[]).filter(p=>db.users[p]&&!blocked(me.phone,p)&&allowed(P(db.users[p]).whoCanCall,db.users[p],me));
  if(!to.length)return res.status(403).json({error:'call_not_allowed'});
  db.calls.push({room,from:me.phone,to,video:!!req.body.video,ts:Date.now(),joined:[]});save();
  to.forEach(p=>io.to(p).emit('incoming-call',{room,from:me.name,video:!!req.body.video}));
  res.json(await tokenFor(room,me));
});
app.post('/call/join',auth,async(req,res)=>{
  const c=db.calls.find(x=>x.room===req.body.room);
  if(c&&!c.joined.includes(req.user.phone)){c.joined.push(req.user.phone);save()}
  res.json(await tokenFor(req.body.room,db.users[req.user.phone]));
});
app.get('/calls',auth,(req,res)=>{
  const me=req.user.phone;
  res.json(db.calls.filter(c=>c.from===me||c.to.includes(me)).slice(-100).reverse().map(c=>{
    const out=c.from===me,other=out?c.to[0]:c.from;
    return {name:(out&&c.to.length>1)?`${db.users[c.to[0]]?.name||c.to[0]} +${c.to.length-1}`:(db.users[other]?.name||other),
      video:c.video,ts:c.ts,dir:out?'out':'in',missed:!out&&!c.joined.includes(me)};
  }));
});
io.use((s,next)=>{try{const tk=String(s.handshake.auth.token||'');s.phone=jwt.verify(tk,SECRET).phone;s.sid=sha(tk);if(db.revoked[s.sid])throw 0;next()}catch(e){next(new Error('auth'))}});
io.on('connection',s=>{
  s.join(s.phone);
  if((io.sockets.adapter.rooms.get(s.phone)?.size||0)===1)notifyPresence(s.phone,true);
  s.on('typing',chat=>{
    chat=String(chat||'');const m=members(chat);
    if(!m.includes(s.phone)||!P(db.users[s.phone]).typing)return;
    if(!chat.startsWith('g')&&blocked(m[0],m[1]))return;
    m.filter(p=>p!==s.phone).forEach(p=>io.to(p).emit('typing',{chat,from:s.phone}));
  });
  s.on('disconnect',()=>{
    const u=db.users[s.phone];
    if(u&&!(io.sockets.adapter.rooms.get(s.phone)?.size)){u.lastSeenAt=Date.now();save();notifyPresence(s.phone,false)}
  });
});
server.listen(3000,()=>console.log('server :3000'));
