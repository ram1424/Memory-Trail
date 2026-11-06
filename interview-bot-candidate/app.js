(function(){
const LIB=window.INTERVIEW_ROLE_LIBRARY;
const P=new URLSearchParams(location.search);
const sessionId=P.get('session')||((crypto&&crypto.randomUUID)?crypto.randomUUID():String(Date.now()));
const role=P.get('role')||'IT Operations Specialist';
const profile=LIB.resolveRole(role);
const questions=profile.questions;
const $=id=>document.getElementById(id);
let stream=null,detector=null,faceOk=false,faceAt=0,faceDetectorHealthy=false,faceFallbackAccepted=false,faceHealthTimer=null,faceFailures=0,recognition=null,phase='idle',index=0,buffer='',silence=null,session=null,noFaceSince=0,currentTranscript='',probeIndex=0;
$('roleTitle').textContent=role;
$('guideTitle').textContent=profile.name+' · '+questions.length+' role-specific questions and scenarios';
$('sessionReceipt').textContent=sessionId;

function show(id){document.querySelectorAll('.screen').forEach(x=>x.classList.toggle('active',x.id===id))}
function toast(t){const x=$('toast');x.textContent=t;x.classList.add('show');setTimeout(()=>x.classList.remove('show'),1600)}
$('candidateName').addEventListener('input',readyWelcome);
$('consent').addEventListener('change',readyWelcome);
function readyWelcome(){$('continueBtn').disabled=!($('candidateName').value.trim()&&$('consent').checked)}

$('continueBtn').onclick=async()=>{
  session={id:sessionId,candidate:$('candidateName').value.trim(),role,profileId:profile.id,profileName:profile.name,date:new Date().toISOString(),answers:[],status:'in-progress'};
  show('preflight');await initMedia()
};
$('backBtn').onclick=()=>{if(stream)stream.getTracks().forEach(t=>t.stop());show('welcome')};

function ok(prefix,text){$(prefix+'Dot').classList.add('ok');$(prefix+'Text').textContent=text}
async function initMedia(){
  try{
    stream=await navigator.mediaDevices.getUserMedia({video:{width:{ideal:1280},height:{ideal:720},facingMode:'user'},audio:{echoCancellation:true,noiseSuppression:true,autoGainControl:true}});
    $('video').srcObject=stream;$('selfVideo').srcObject=stream;ok('cam','Camera active');ok('mic','Microphone active');await initFace();initSpeech()
  }catch(e){$('camText').textContent='Camera/microphone permission is required';$('micText').textContent='Permission denied or unavailable'}
}
function faceUnavailable(message){
  faceDetectorHealthy=false;faceOk=false;faceAt=0;
  $('faceDot').classList.remove('ok');
  $('faceText').textContent=message||'Automatic face check unavailable';
  $('videoBadge').textContent='Camera active · confirm preview';
  $('retryFace').hidden=false;$('faceFallbackWrap').hidden=false;
  updateReady();
}
async function initFace(){
  clearTimeout(faceHealthTimer);faceFailures=0;faceDetectorHealthy=false;faceFallbackAccepted=false;
  $('retryFace').hidden=true;$('faceFallbackWrap').hidden=true;$('faceFallback').checked=false;
  try{
    const C=window.FaceDetection&&(window.FaceDetection.FaceDetection||window.FaceDetection);
    if(!C)throw new Error('MediaPipe face detector did not load');
    const v=$('video');
    if(v.readyState<2)await new Promise(resolve=>v.addEventListener('loadeddata',resolve,{once:true}));
    detector=new C({locateFile:f=>'https://cdn.jsdelivr.net/npm/@mediapipe/face_detection@0.4.1646425229/'+f});
    detector.setOptions({model:'short',selfieMode:true,minDetectionConfidence:.45});
    detector.onResults(r=>{
      faceDetectorHealthy=true;clearTimeout(faceHealthTimer);$('retryFace').hidden=true;$('faceFallbackWrap').hidden=true;
      const n=(r.detections||[]).length;faceOk=n===1;
      if(faceOk){
        if(!faceAt)faceAt=Date.now();
        $('faceDot').classList.add('ok');$('faceText').textContent='One face visible';
        $('videoBadge').textContent='Ready · one face visible';$('videoBadge').style.background='rgba(39,144,100,.82)'
      }else{
        faceAt=0;$('faceDot').classList.remove('ok');
        $('faceText').textContent=n>1?'Please keep only the interviewee on camera':'Center your face in the camera and move a little closer';
        $('videoBadge').textContent=n>1?'Multiple faces':'Looking for your face';$('videoBadge').style.background='rgba(17,26,48,.78)'
      }
      updateReady()
    });
    faceHealthTimer=setTimeout(()=>{if(!faceDetectorHealthy)faceUnavailable('Automatic face detection did not start. You can retry or confirm the camera preview below.')},7000);
    setInterval(async()=>{
      if(!detector||$('video').readyState<2)return;
      try{await detector.send({image:$('video')});faceFailures=0}
      catch(e){faceFailures++;if(faceFailures>=3)faceUnavailable('Automatic face detection stopped responding. Retry it or confirm the camera preview below.')}
    },600)
  }catch(e){faceUnavailable('Automatic face detection could not start. Retry it or confirm the camera preview below.')}
}
$('retryFace').onclick=()=>initFace();
$('faceFallback').onchange=function(){faceFallbackAccepted=this.checked;updateReady()};
function initSpeech(){
  const SR=window.SpeechRecognition||window.webkitSpeechRecognition;
  if(!SR){$('speechText').textContent='Speech recognition is not supported in this browser';return}
  recognition=new SR();recognition.lang='en-US';recognition.continuous=true;recognition.interimResults=true;recognition.maxAlternatives=1;
  recognition.onresult=e=>{
    let interim='';
    for(let i=e.resultIndex;i<e.results.length;i++){
      const t=e.results[i][0].transcript;
      if(e.results[i].isFinal)buffer+=(buffer?' ':'')+t.trim();else interim+=t
    }
    renderTranscript((currentTranscript+(currentTranscript&&buffer?' ':'')+buffer+(interim?' '+interim:'')).trim());
    resetSilence()
  };
  recognition.onerror=e=>{if(e.error!=='no-speech')$('listenStatus').textContent='Voice capture: '+e.error};
  recognition.onend=()=>{if(['answer','probe','confirm'].includes(phase))try{recognition.start()}catch(e){}};
  ok('speech','Voice transcription ready');updateReady()
}
function updateReady(){const automaticFaceReady=faceDetectorHealthy&&faceOk&&faceAt&&Date.now()-faceAt>700;const faceReady=automaticFaceReady||faceFallbackAccepted;$('beginBtn').disabled=!(stream&&recognition&&faceReady)}
$('beginBtn').onclick=()=>{if(!faceOk)return;show('interview');startInterview()};

function chooseVoice(){
  const vs=speechSynthesis.getVoices().filter(v=>/^en(-|_)/i.test(v.lang));
  for(const n of ['Ava','Samantha','Allison','Zoe','Serena','Enhanced','Premium']){const v=vs.find(x=>x.name.toLowerCase().includes(n.toLowerCase()));if(v)return v}
  return vs[0]
}
function say(text,after){
  phase='speaking';stopListening();$('humanAvatar').classList.add('speaking');$('caption').textContent=text;
  const u=new SpeechSynthesisUtterance(text);u.rate=.96;u.pitch=1.01;const v=chooseVoice();if(v)u.voice=v;
  u.onend=()=>{$('humanAvatar').classList.remove('speaking');if(after)setTimeout(after,350)};
  speechSynthesis.cancel();speechSynthesis.speak(u)
}
function startInterview(){
  const intro='Hi '+session.candidate+'. I’m Maya, your virtual interviewer. You’re interviewing for the '+session.role+' role. I’ll ask '+questions.length+' questions and realistic job scenarios tailored to this type of work. Please answer naturally and explain your own actions, decisions, and results. Before I move on each time, I’ll make sure you have nothing else to add. Let’s begin.';
  $('qMeta').textContent='INTRODUCTION · '+profile.name.toUpperCase();$('qText').textContent='Welcome to your interview';$('autoState').textContent='Maya is introducing the role-specific interview.';
  say(intro,()=>askQuestion(0))
}
function askQuestion(i){
  index=i;buffer='';currentTranscript='';probeIndex=0;
  const q=questions[i];
  $('qMeta').textContent='QUESTION '+(i+1)+' OF '+questions.length+' · '+q.kind.toUpperCase()+' · '+q.competency.toUpperCase();
  $('qText').textContent=q.prompt;$('progress').style.width=(i/questions.length*100)+'%';
  $('autoState').textContent=q.kind==='Scenario'?'Think through the scenario and explain what you would do.':'Use a specific example where possible.';
  renderTranscript('');
  say(LIB.spoken(q),()=>listen('answer'))
}
function listen(mode){
  phase=mode;buffer='';
  $('listenPill').textContent='Listening';$('listenPill').classList.add('on');
  $('listenStatus').textContent=mode==='confirm'?'Listening for anything else you want to add…':mode==='probe'?'Listening to your follow-up answer…':'Listening to your answer…';
  try{recognition.start()}catch(e){}
  resetSilence()
}
function stopListening(){
  $('listenPill').textContent='Waiting';$('listenPill').classList.remove('on');clearTimeout(silence);
  if(recognition)try{recognition.stop()}catch(e){}
}
function resetSilence(){
  clearTimeout(silence);
  silence=setTimeout(()=>{if(phase==='answer'||phase==='probe')finishAnswerSegment();else if(phase==='confirm')finishConfirm()},2500)
}
function renderTranscript(t){$('transcript').textContent=t||'Listening…'}
function finishAnswerSegment(){
  stopListening();
  const segment=buffer.trim();
  if(segment)currentTranscript+=(currentTranscript?' ':'')+segment;
  const words=currentTranscript.split(/\s+/).filter(Boolean);
  const q=questions[index];
  if(words.length<28&&probeIndex<q.probes.length){
    const probe=q.probes[probeIndex++];
    say(probe,()=>listen('probe'));return
  }
  session.answers[index]={kind:q.kind,competency:q.competency,question:q.prompt,transcript:currentTranscript.trim(),probesUsed:probeIndex};
  askAnythingElse()
}
function askAnythingElse(){say('Before we move on, is there anything else you would like to add to that answer?',()=>listen('confirm'))}
function finishConfirm(){
  stopListening();const t=buffer.trim();
  const no=/^(no|nope|nothing|nothing else|that's all|that is all|i'm good|im good|no thank you|no thanks)[.! ]*$/i.test(t);
  if(t&&!no&&t.split(/\s+/).length>2){
    session.answers[index].transcript+=(session.answers[index].transcript?' ':'')+t;currentTranscript=session.answers[index].transcript;renderTranscript(currentTranscript);
    say('Thank you. I’ve added that.',()=>askAnythingElse());return
  }
  advance()
}
function advance(){
  if(index<questions.length-1)say('Thank you. Let’s move to the next question.',()=>askQuestion(index+1));
  else complete()
}
function complete(){
  phase='complete';stopListening();$('progress').style.width='100%';
  say('Thank you, '+session.candidate+'. That completes your interview for the '+session.role+' role. We appreciate your time today.',()=>{
    session.status='complete';session.completed=new Date().toISOString();localStorage.setItem('interview-session-'+sessionId,JSON.stringify(session));show('complete')
  })
}
setInterval(()=>{
  if($('interview').classList.contains('active')){
    if(faceDetectorHealthy&&!faceOk){
      if(!noFaceSince)noFaceSince=Date.now();
      if(Date.now()-noFaceSince>4500&&phase!=='camera-pause'&&phase!=='speaking'){
        const prev=phase;phase='camera-pause';stopListening();
        say('I can’t see you clearly on camera. Please return to camera view and we’ll continue.',()=>{
          const w=setInterval(()=>{if(faceOk){clearInterval(w);noFaceSince=0;say('Thank you. We can continue.',()=>listen(prev==='confirm'?'confirm':prev==='probe'?'probe':'answer'))}},700)
        })
      }
    }else noFaceSince=0
  }
},900);
$('downloadBtn').onclick=()=>{
  if(!session)return;const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify(session,null,2)],{type:'application/json'}));
  a.download='interview-'+sessionId+'.json';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),500)
};
})();