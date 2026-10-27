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
// ---- mobile-number validity per country: dial code | min | max | allowed start of the national number
const PHONE_RULES={};
`880|10|10|1[3-9]
91|10|10|[6-9]
92|10|10|3
94|9|9|7
977|10|10|9
975|8|8|[17]7
960|7|7|[79]
93|9|9|7
966|9|9|5
971|9|9|5
974|8|8|[3567]
965|8|8|[569]
968|8|8|[79]
973|8|8|3
962|9|9|7
961|7|8|[0-9]
964|10|10|7
98|10|10|9
90|10|10|5
20|10|10|1
212|9|9|[67]
213|9|9|[567]
216|8|8|[2459]
218|9|9|9
249|9|9|[19]
234|10|10|[789]
27|9|9|[678]
254|9|9|[17]
251|9|9|[97]
233|9|9|[25]
60|9|10|1
65|8|8|[89]
62|9|12|8
66|9|9|[689]
84|9|9|[35789]
63|10|10|9
86|11|11|1
81|10|10|[789]0
82|9|10|1
852|8|8|[569]
61|9|9|4
64|8|10|2
44|10|10|7
353|9|9|8
33|9|9|[67]
49|10|11|1[567]
39|9|10|3
34|9|9|[67]
351|9|9|9
31|9|9|6
46|9|9|7
47|8|8|[49]
41|9|9|7
7|10|10|9
380|9|9|[35679]
1|10|10|[2-9]
52|10|10|[1-9]
55|11|11|[1-9]
54|10|11|[1-9]`.split('\n').forEach(l=>{const [d,a,b,r]=l.split('|');PHONE_RULES[d]={min:+a,max:+b,re:new RegExp('^'+r)}});
function validPhone(p){
  p=String(p||'');if(!/^\+\d{8,15}$/.test(p))return {ok:false};
  const digits=p.slice(1);
  for(const n of [3,2,1]){
    const rule=PHONE_RULES[digits.slice(0,n)];
    if(rule){const nat=digits.slice(n);return {ok:nat.length>=rule.min&&nat.length<=rule.max&&rule.re.test(nat)}}
  }
  return {ok:digits.length>=9&&digits.length<=15};
}
const genId=()=>{let id;do{id=String(Math.floor(10000000+Math.random()*90000000))}while(Object.values(db.users).some(u=>u.userId===id));return id};
const DEF={privacyChat:false,chatTimer:86400000,blockCallShot:false,whoCanCall:'everyone',lastSeen:'everyone',typing:true,readReceipts:true,blockProfileShot:false,lockProfile:false,whoSeeProfile:'everyone',addByPhone:true,addById:true,requireApproval:false,whoStory:'contacts'};
const P=u=>({...DEF,...(u?.privacy||{})});
const allowed=(lvl,t,v)=>lvl==='everyone'||(lvl==='contacts'&&(t.contacts||[]).includes(v.phone));
const pres=(t,v)=>allowed(P(t).lastSeen,t,v)?{online:(io.sockets.adapter.rooms.get(t.phone)?.size||0)>0,last:t.lastSeenAt||0}:{hidden:true};
function notifyPresence(phone,online){
  const u=db.users[phone];if(!u)return;
  (u.contacts||[]).forEach(c=>{const v=db.users[c];if(v&&allowed(P(u).lastSeen,u,v))io.to(c).emit('presence',{phone,online,last:u.lastSeenAt||Date.now()})});
}
const safe=u=>{const {totp,face,devices,...r}=u;return {...r,totpEnabled:!!totp?.enabled,faceEnrolled:!!face,privacy:P(u)}};
Object.values(db.users).forEach(u=>{u.userId||=genId();u.contacts||=[]});
const app=express();app.use(cors(),express.json({limit:'8mb'}));
const server=http.createServer(app);
const io=new Server(server,{cors:{origin:'*'}});
const UP='uploads';fs.mkdirSync(UP,{recursive:true});
app.use('/uploads',express.static(UP,{maxAge:'7d'}));
const auth=(req,res,next)=>{
  try{
    const tok=(req.headers.authorization||'').slice(7),p=jwt.verify(tok,SECRET);
    if(p.purpose)return res.sendStatus(401);
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

// ================= registration, login, face verification =================
const OTP_TTL=90000;
const regs={},faceSteps={};
const FACE={key:process.env.FACEPP_KEY,secret:process.env.FACEPP_SECRET,url:process.env.FACEPP_URL||'https://api-us.faceplusplus.com/facepp/v3'};
const faceDemo=!FACE.key||!FACE.secret;
if(faceDemo)console.log('WARNING: face verification is in DEMO mode (FACEPP_KEY / FACEPP_SECRET not set). Photos are stored but NOT compared.');
fs.mkdirSync('faces',{recursive:true});
const rnd6=()=>String(Math.floor(100000+Math.random()*900000));
const devId=req=>String(req.headers['x-device-id']||'').slice(0,64);
function trustDevice(u,req){const d=devId(req);if(d){u.devices=u.devices||{};u.devices[d]={name:String(req.headers['x-device']||'').slice(0,80),since:Date.now()}}}
const sessionFor=u=>({token:jwt.sign({phone:u.phone},SECRET,{expiresIn:'90d'}),user:safe(u)});
function saveFaceRef(u,st){
  const ext=b=>b[0]===0x89?'png':'jpg',id=crypto.randomBytes(8).toString('hex');
  const f=`${u.userId}_${id}_front.${ext(st.front)}`,t=`${u.userId}_${id}_turn.${ext(st.turn)}`;
  fs.writeFileSync(`faces/${f}`,st.front);fs.writeFileSync(`faces/${t}`,st.turn);
  u.face={front:f,turn:t,at:Date.now(),mode:faceDemo?'demo':'facepp'};
}
async function facepp(path,fields){
  const fd=new FormData();fd.append('api_key',FACE.key);fd.append('api_secret',FACE.secret);
  for(const [k,v] of Object.entries(fields))fd.append(k,v);
  return (await fetch(FACE.url+path,{method:'POST',body:fd})).json();
}
async function checkFace(buf,step){
  if(faceDemo)return {ok:true};
  const j=await facepp('/detect',{image_base64:buf.toString('base64'),return_attributes:'headpose,blur,facequality'});
  if(j.error_message)return {error:j.error_message};
  const f=j.faces||[];
  if(!f.length)return {ok:false,reason:'no_face'};
  if(f.length>1)return {ok:false,reason:'multiple_faces'};
  const a=f[0].attributes||{},bl=a.blurness||a.blur?.blurness,fq=a.facequality;
  if(bl&&bl.value>bl.threshold)return {ok:false,reason:'blurry'};
  if(fq&&fq.value<fq.threshold)return {ok:false,reason:'low_quality'};
  const yaw=Math.abs(a.headpose?.yaw_angle??0);
  if(step==='front'&&yaw>15)return {ok:false,reason:'wrong_pose'};
  if(step==='turn'&&yaw<18)return {ok:false,reason:'wrong_pose'};
  return {ok:true};
}
async function compareFace(ref,now){
  if(faceDemo)return {ok:true};
  const j=await facepp('/compare',{image_base64_1:ref.toString('base64'),image_base64_2:now.toString('base64')});
  if(j.error_message)return {error:j.error_message};
  const th=j.thresholds?.['1e-4']??70;
  return {ok:(j.confidence||0)>=th};
}
const faceAuth=purposes=>(req,res,next)=>{
  try{const p=jwt.verify((req.headers.authorization||'').slice(7),SECRET);if(!purposes.includes(p.purpose))throw 0;req.fp=p;next()}
  catch(e){res.sendStatus(401)}
};

app.post('/register/start',(req,res)=>{
  const b=req.body||{},name=String(b.name||'').trim(),nat=String(b.nationality||'').trim(),birth=String(b.birthdate||'').trim();
  const phone=String(b.phone||'').trim(),email=String(b.email||'').trim().toLowerCase();
  if(name.length<2||name.length>60)return res.status(400).json({error:'invalid_name'});
  if(!nat||nat.length>60)return res.status(400).json({error:'invalid_nat'});
  const bd=new Date(birth+'T00:00:00Z');
  if(!/^\d{4}-\d{2}-\d{2}$/.test(birth)||isNaN(bd)||bd>new Date()||bd.getUTCFullYear()<1900)return res.status(400).json({error:'invalid_birth'});
  if(!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email))return res.status(400).json({error:'invalid_email'});
  if(!validPhone(phone).ok)return res.status(400).json({error:'invalid_number'});
  if(db.users[phone])return res.status(409).json({error:'phone_registered'});
  if(Object.values(db.users).some(x=>x.emailVerified&&x.email?.toLowerCase()===email))return res.status(409).json({error:'email_taken'});
  const old=regs[phone];if(old&&Date.now()-old.sent<20000)return res.status(429).json({error:'too_fast'});
  const otp=rnd6();
  regs[phone]={data:{name,nationality:nat,birthdate:birth,email},otp,exp:Date.now()+OTP_TTL,sent:Date.now(),tries:0,verified:false};
  console.log('REGISTER OTP',phone,otp); // TODO: SMS provider
  res.json({ok:true,ttl:OTP_TTL/1000,devOtp:process.env.DEV_OTP==='1'?otp:undefined});
});
app.post('/register/verify',(req,res)=>{
  const phone=String(req.body.phone||''),g=regs[phone];
  if(!g||g.exp<Date.now())return res.status(400).json({error:'expired'});
  if(++g.tries>6){delete regs[phone];return res.status(429).json({error:'too_fast'})}
  if(g.otp!==String(req.body.otp||'').trim())return res.status(400).json({error:'otp_wrong'});
  g.verified=true;g.exp=Date.now()+30*60000;
  res.json({ok:true,regToken:jwt.sign({phone,purpose:'reg'},SECRET,{expiresIn:'30m'})});
});
app.post('/face/check',faceAuth(['reg','face']),async(req,res)=>{
  const phone=req.fp.phone,st=faceSteps[phone]||(faceSteps[phone]={fails:0,lock:0});
  if(st.lock>Date.now())return res.status(429).json({error:'locked'});
  const step=req.body.step==='turn'?'turn':'front';
  const buf=Buffer.from(String(req.body.image||''),'base64');
  const img=buf.length>2000&&buf.length<5*1024*1024&&((buf[0]===0xFF&&buf[1]===0xD8)||(buf[0]===0x89&&buf[1]===0x50));
  if(!img)return res.status(400).json({ok:false,reason:'low_quality'});
  let r;try{r=await checkFace(buf,step)}catch(e){return res.status(503).json({error:'face_service'})}
  if(r.error){console.log('FACE API:',r.error);return res.status(503).json({error:'face_service'})}
  if(!r.ok){if(++st.fails>=8){st.lock=Date.now()+15*60000;st.fails=0}return res.json({ok:false,reason:r.reason})}
  st[step]=buf;res.json({ok:true,done:!!(st.front&&st.turn)});
});
app.post('/register/complete',faceAuth(['reg']),(req,res)=>{
  const phone=req.fp.phone,g=regs[phone],st=faceSteps[phone];
  if(!g||!g.verified||!st?.front||!st?.turn)return res.status(400).json({error:'expired'});
  if(req.body.consent!==true)return res.status(400).json({error:'consent'});
  if(db.users[phone])return res.status(409).json({error:'phone_registered'});
  const d=g.data;
  const u=db.users[phone]={phone,name:d.name,nationality:d.nationality,birthdate:d.birthdate,email:d.email,emailVerified:false,bio:'',userId:genId(),blocked:false,blocks:[],contacts:[],devices:{},created:Date.now()};
  saveFaceRef(u,st);trustDevice(u,req);
  delete regs[phone];delete faceSteps[phone];delete db.oldNumbers[phone];save();
  res.json(sessionFor(u));
});

app.post('/auth/request-otp',(req,res)=>{
  const phone=String(req.body.phone||'').trim();
  if(!validPhone(phone).ok)return res.status(400).json({error:'invalid_number'});
  if(!db.users[phone])return res.status(404).json({error:'not_registered'});
  const old=otps[phone];if(old&&Date.now()-old.sent<20000)return res.status(429).json({error:'too_fast'});
  const otp=rnd6();otps[phone]={otp,exp:Date.now()+OTP_TTL,sent:Date.now(),tries:0};
  console.log('LOGIN OTP',phone,otp); // TODO: SMS provider
  res.json({ok:true,ttl:OTP_TTL/1000,devOtp:process.env.DEV_OTP==='1'?otp:undefined});
});
app.post('/auth/verify',(req,res)=>{
  const {phone,otp,totp}=req.body,r=otps[phone];
  if(!r||r.exp<Date.now())return res.status(400).json({error:'expired'});
  if(++r.tries>6){delete otps[phone];return res.status(429).json({error:'too_fast'})}
  if(r.otp!==String(otp||'').trim())return res.status(400).json({error:'otp_wrong'});
  const u=db.users[phone];if(!u)return res.status(404).json({error:'not_registered'});
  if(u.totp?.enabled&&!totpOk(u.totp.secret,totp))return res.status(401).json({need2fa:true,error:totp?'totp_wrong':undefined});
  delete otps[phone];
  if(u.blocked)return res.status(403).json({error:'blocked'});
  const d=devId(req);
  // known phone + face already enrolled => OTP is enough; new phone / reinstall / old account => face check is mandatory
  if(u.face&&d&&u.devices?.[d])return res.json(sessionFor(u));
  res.json({needFace:true,mode:u.face?'verify':'enroll',faceToken:jwt.sign({phone,purpose:'face'},SECRET,{expiresIn:'15m'})});
});
app.post('/auth/face-login',faceAuth(['face']),async(req,res)=>{
  const phone=req.fp.phone,u=db.users[phone],st=faceSteps[phone];
  if(!u||!st?.front||!st?.turn)return res.status(400).json({error:'expired'});
  if(st.lock>Date.now())return res.status(429).json({error:'locked'});
  if(!u.face){
    if(req.body.consent!==true)return res.status(400).json({error:'consent'});
    saveFaceRef(u,st);
  }else{
    let c;try{c=await compareFace(fs.readFileSync(`faces/${u.face.front}`),st.front)}catch(e){return res.status(503).json({error:'face_service'})}
    if(c.error){console.log('FACE API:',c.error);return res.status(503).json({error:'face_service'})}
    if(!c.ok){if(++st.fails>=5){st.lock=Date.now()+15*60000;st.fails=0}st.front=st.turn=null;return res.status(403).json({error:'face_mismatch'})}
  }
  trustDevice(u,req);delete faceSteps[phone];save();
  res.json(sessionFor(u));
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
  if(np===req.user.phone||!validPhone(np).ok)return res.status(400).json({error:'invalid_number'});
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
  if(type==='phone'&&!validPhone(String(value||'').trim()).ok)return res.status(400).json({error:'invalid_number'});
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
  m.forEach(p=>io.to(p).emit('message',{chat,from:me,id:msg.id,type:'text',ts:msg.ts}));res.json({id:msg.id});
});
setInterval(()=>{
  const n=Date.now(),keep=[];
  db.messages.forEach(m=>{if(!m.exp||m.exp>n)keep.push(m);else if(m.url)fs.unlink(`${UP}/${m.url.slice(9)}`,()=>{})});
  if(keep.length!==db.messages.length){db.messages=keep;save()}
},30000);
// photos & videos in chats: raw binary body (no extra npm package), details in headers
app.post('/messages/media',auth,express.raw({type:'application/octet-stream',limit:'60mb'}),(req,res)=>{
  const me=req.user.phone,chat=String(req.headers['x-chat']||''),want=['video','voice'].includes(req.headers['x-kind'])?req.headers['x-kind']:'image';
  const m=members(chat),b=req.body;
  if(!m.includes(me))return res.status(403).json({error:'not a member'});
  if(!chat.startsWith('g')&&blocked(m[0],m[1]))return res.status(403).json({error:'blocked'});
  if(!Buffer.isBuffer(b)||b.length<100)return res.status(400).json({error:'empty file'});
  let ext=null;
  if(b[0]===0xFF&&b[1]===0xD8)ext='jpg';
  else if(b[0]===0x89&&b[1]===0x50)ext='png';
  else if(b.slice(0,4).toString()==='RIFF'&&b.slice(8,12).toString()==='WEBP')ext='webp';
  else if(b.slice(4,8).toString()==='ftyp')ext='mp4';
  else if(b[0]===0x1A&&b[1]===0x45&&b[2]===0xDF&&b[3]===0xA3)ext='webm';
  if(!ext)return res.status(400).json({error:'unsupported file type'});
  let kind=['mp4','webm'].includes(ext)?'video':'image';
  if(want==='voice'){if(ext!=='mp4')return res.status(400).json({error:'unsupported voice format'});kind='voice';ext='m4a'}
  if(kind!==want)return res.status(400).json({error:'file type mismatch'});
  if(kind==='image'&&b.length>10*1024*1024)return res.status(400).json({error:'image too large'});
  if(kind==='voice'&&b.length>10*1024*1024)return res.status(400).json({error:'voice message too large'});
  if(kind==='video'&&b.length>50*1024*1024)return res.status(400).json({error:'video too large (max 50 MB)'});
  const name=`m_${crypto.randomBytes(12).toString('hex')}.${ext}`;
  fs.writeFileSync(`${UP}/${name}`,b);
  let caption='';try{caption=decodeURIComponent(String(req.headers['x-caption']||'')).slice(0,300)}catch(e){}
  const pr=P(db.users[me]);
  const msg={id:Date.now()+Math.random().toString(36).slice(2,6),chat,from:me,type:kind,url:`/uploads/${name}`,text:caption,ts:Date.now(),read:{}};
  if(kind==='voice'){msg.dur=Math.min(Number(req.headers['x-dur'])||0,600000);const w=String(req.headers['x-wave']||'');msg.wave=/^[0-9,]{0,250}$/.test(w)?w:''}
  if(pr.privacyChat)msg.exp=Date.now()+pr.chatTimer;
  db.messages.push(msg);save();
  m.forEach(p=>io.to(p).emit('message',{chat,from:me,id:msg.id,type:kind,url:msg.url,ts:msg.ts}));
  res.json({id:msg.id,url:msg.url});
});
app.get('/messages',auth,(req,res)=>{
  const me=req.user.phone,chat=String(req.query.chat||'');
  if(!members(chat).includes(me))return res.sendStatus(403);
  const n=Date.now(),vr=P(db.users[me]).readReceipts;
  res.json(db.messages.filter(x=>x.chat===chat&&(!x.exp||x.exp>n)).slice(-200)
    .map(x=>({id:x.id,chat:x.chat,from:x.from,text:x.text,type:x.type||'text',url:x.url,dur:x.dur,wave:x.wave,ts:x.ts,exp:x.exp,seen:x.from===me&&vr&&Object.values(x.read||{}).some(t=>t>0)})));
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
    c.last=x.type==='image'?'📷 '+(x.text||'Photo'):x.type==='video'?'🎥 '+(x.text||'Video'):x.type==='voice'?'🎤 Voice message':x.text;c.ts=x.ts;
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
io.use((s,next)=>{try{const tk=String(s.handshake.auth.token||''),pl=jwt.verify(tk,SECRET);if(pl.purpose)throw 0;s.phone=pl.phone;s.sid=sha(tk);if(db.revoked[s.sid])throw 0;next()}catch(e){next(new Error('auth'))}});
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
