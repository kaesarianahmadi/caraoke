const [,,action,delayMs] = process.argv;
const K = {left:{x:-127},right:{x:127},up:{y:-127},down:{y:127},select:{select:true},home:{home:true},back:{back:true}};
const MEDIA = {playpause:3,next:4,prev:5};
const msg = K[action] ? {type:'knob',knob:{select:false,home:false,back:false,x:0,y:0,wheel:0,...K[action]}}
          : MEDIA[action] !== undefined ? {type:'media',media:MEDIA[action]} : null;
if(!msg){console.error('unknown action '+action);process.exit(2);}
const fire=()=>{const ws=new WebSocket('ws://localhost:8080/ws?token=caraoke');
 ws.onopen=()=>{ws.send(JSON.stringify(msg));
  if(action==='select'||action==='home'||action==='back'){setTimeout(()=>ws.send(JSON.stringify({type:'knob',knob:{select:false,home:false,back:false,x:0,y:0,wheel:0}})),120);}
  setTimeout(()=>{ws.close();process.exit(0);},500);};
 ws.onerror=e=>{console.error('ws error',e.message||e);process.exit(1);};};
if(delayMs){setTimeout(fire,Number(delayMs));}else{fire();}
