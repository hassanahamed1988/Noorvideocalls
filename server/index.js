const express=require('express'),http=require('http'),cors=require('cors'),jwt=require('jsonwebtoken'),fs=require('fs');
const {Server}=require('socket.io');const {AccessToken}=require('livekit-server-sdk');
const SECRET=process.env.JWT_SECRET||'change-me';
const DB='db.json';
const db=fs.existsSync(DB)?JSON.parse(fs.readFileSync(DB)):{};
db.users||={};db.messages||=[];db.calls||=[];db.groups||={};db.reports||=[];
const save=()=>fs.writeFileSync(DB,JSON.stringify(db));
const otps={},emailCodes={};
const crypto=require('crypto');
const B32='ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const b32enc=buf=>{let bits='',out='';for(const b of buf)bits+=b.toString(2).padStart(8,'0');for(let i=0;i<bits.length;i+=5)out+=B32[parseInt(bits.slice(i,i+5).padEnd(5,'0'),2)];return out};
const b32dec=s=>{let bits='';for(const c of s)bits+=B32.indexOf(c).toString(2).padStart(5,'0');const a=[];for(let i=0;i+8<=bits.length;i+=8)a.push(parseInt(bits.slice(i,i+8),2));return Buffer.from(a)};
const hotp=(secret,ctr)=>{const b=Buffer.alloc(8);b.writeBigUInt64BE(BigInt(ctr));const h=crypto.createHmac('sha1',b32dec(secret)).update(b).digest();const o=h[19]&15;return String((h.readUInt32BE(o)&0x7fffffff)%1000000).padStart(6,'0')};
const totpOk=(secret,code)=>{const c=Math.floor(Date.now()/30000);return [-1,0,1].some(d=>hotp(secret,c+d)===String(code||'').trim())};
const genId=()=>String(Math.floor(10000000+Math.random()*90000000));
const safe=u=>{const {totp,...r}=u;return {...r,totpEnabled:!!totp?.enabled}};
Object.values(db.users).forEach(u=>{u.userId||=genId();u.contacts||=[]});
const app=express();app.use(cors(),express.json({limit:'1mb'}));
const server=http.createServer(app);
const io=new Server(server,{cors:{origin:'*'}});
const auth=(req,res,next)=>{try{req.user=jwt.verify((req.headers.authorization||'').slice(7),SECRET);if(!db.users[req.user.phone]||db.users[req.user.phone].blocked)return res.sendStatus(401);next()}catch(e){res.sendStatus(401)}};
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
  save();
  if(u.blocked)return res.status(403).json({error:'অ্যাকাউন্ট ব্লকড'});
  res.json({token:jwt.sign({phone},SECRET,{expiresIn:'90d'}),user:safe(u)});
});
app.get('/me',auth,(req,res)=>res.json(safe(db.users[req.user.phone])));
app.post('/me',auth,(req,res)=>{
  const u=db.users[req.user.phone],{name,bio,nationality,birthdate,userId,avatar}=req.body;
  if(userId!==undefined&&userId!==u.userId){
    if(!/^[A-Za-z0-9_]{4,20}$/.test(userId))return res.status(400).json({error:'User ID: 4-20 letters/numbers/_'});
    if(Object.values(db.users).some(x=>x.userId?.toLowerCase()===userId.toLowerCase()))return res.status(400).json({error:'User ID taken'});
    u.userId=userId;
  }
  if(name!==undefined)u.name=String(name).slice(0,60)||u.name;
  if(bio!==undefined)u.bio=String(bio).slice(0,200);
  if(nationality!==undefined)u.nationality=String(nationality).slice(0,60);
  if(birthdate!==undefined)u.birthdate=String(birthdate).slice(0,10);
  if(avatar!==undefined&&String(avatar).length<300000)u.avatar=avatar;
  save();res.json(safe(u));
});
const card=({phone,name,bio,avatar,userId})=>({phone,name,bio,avatar,userId});
app.get('/users/search',auth,(req,res)=>{
  const q=String(req.query.q||'').toLowerCase(),me=db.users[req.user.phone];
  res.json((me.contacts||[]).map(p=>db.users[p]).filter(u=>u&&!u.blocked&&!blocked(me.phone,u.phone)&&(u.name.toLowerCase().includes(q)||u.phone.includes(q))).map(card));
});
app.post('/contacts/add',auth,(req,res)=>{
  const {type,value}=req.body,v=String(value||'').trim().toLowerCase(),me=db.users[req.user.phone];
  const u=Object.values(db.users).find(x=>type==='phone'?x.phone===String(value).trim():type==='email'?(x.emailVerified&&x.email?.toLowerCase()===v):x.userId?.toLowerCase()===v);
  if(!u||u.phone===me.phone||u.blocked)return res.status(404).json({error:'not found'});
  [[me,u],[u,me]].forEach(([a,b])=>{a.contacts||=[];if(!a.contacts.includes(b.phone))a.contacts.push(b.phone)});
  save();res.json({user:card(u)});
});
app.get('/profile',auth,(req,res)=>{
  const u=db.users[String(req.query.phone||'')];if(!u)return res.sendStatus(404);
  res.json({...card(u),nationality:u.nationality,birthdate:u.birthdate,email:u.emailVerified?u.email:undefined});
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
  const msg={id:Date.now()+Math.random().toString(36).slice(2,6),chat,from:me,text,ts:Date.now()};
  db.messages.push(msg);save();
  m.forEach(p=>io.to(p).emit('message',msg));res.json(msg);
});
app.get('/messages',auth,(req,res)=>{
  const chat=String(req.query.chat||'');
  if(!members(chat).includes(req.user.phone))return res.sendStatus(403);
  res.json(db.messages.filter(x=>x.chat===chat).slice(-200));
});
app.get('/chats',auth,(req,res)=>{
  const me=req.user.phone,map={};
  Object.values(db.groups).filter(g=>g.members.includes(me)).forEach(g=>map['g'+g.id]={chat:'g'+g.id,title:g.name,members:g.members,ts:+g.id});
  db.messages.forEach(x=>{
    if(!members(x.chat).includes(me))return;
    const c=map[x.chat]||(map[x.chat]={chat:x.chat});
    if(!x.chat.startsWith('g')){c.peer=members(x.chat).find(p=>p!==me);c.title=db.users[c.peer]?.name||c.peer}
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
  const to=(req.body.to||[]).filter(p=>db.users[p]&&!blocked(me.phone,p));
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
io.use((s,next)=>{try{s.phone=jwt.verify(s.handshake.auth.token,SECRET).phone;next()}catch(e){next(new Error('auth'))}});
io.on('connection',s=>s.join(s.phone));
server.listen(3000,()=>console.log('server :3000'));
