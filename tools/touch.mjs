// touch.mjs <x0> <y0> <x1> <y1> <ms>  — normalized 0..1 swipe
const [,,x0,y0,x1,y1,ms] = process.argv.map(Number);
const ws = new WebSocket('ws://localhost:8080/ws?token=caraoke');
const send = (o) => ws.send(JSON.stringify(o));
ws.onopen = () => {
  send({type:'touch',contacts:[{id:0,x:x0,y:y0,down:true}]});
  const steps = Math.max(6, Math.round(ms/16));
  let i = 1;
  const t = setInterval(() => {
    const p = i/steps;
    const x = x0 + (x1-x0)*p, y = y0 + (y1-y0)*p;
    send({type:'touch',contacts:[{id:0,x,y,down:true}]});
    if (++i > steps) { clearInterval(t); send({type:'touch',contacts:[{id:0,x:x1,y:y1,down:false}]}); setTimeout(()=>{ws.close();process.exit(0);},300); }
  }, 16);
};
ws.onerror = e => { console.error('ERR', e.message||e); process.exit(1); };
