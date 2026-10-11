const ws = new WebSocket('ws://localhost:8080/ws?token=caraoke');
let n = 0, t0 = Date.now(), res = null, bytes = 0, frames = 0, firstFrameAt = null, lastFrameAt = null;
ws.binaryType = 'arraybuffer';
ws.onopen = () => { console.log('OPEN'); ws.send(JSON.stringify({type:'keyframe'})); };
ws.onmessage = (e) => {
  if (typeof e.data === 'string') {
    let j = null; try { j = JSON.parse(e.data); } catch {}
    if (j && (j.width || j.deviceName || j.sessionActive !== undefined || j.message)) console.log('CTRL', JSON.stringify(j).slice(0,300));
    return;
  }
  const b = new Uint8Array(e.data);
  const type = b[0]; const stream = b[1];
  if (type === 1 && !res) {
    const dv = new DataView(e.data);
    res = { stream, codec: b[2], w: dv.getUint32(3, true), h: dv.getUint32(7, true) };
    console.log('VIDEO-CONFIG', JSON.stringify(res), 'codecDataBytes', b.length - 11);
  } else if (type === 1) {
    const dv = new DataView(e.data);
    console.log('VIDEO-CONFIG(again) codec=' + b[2] + ' ' + dv.getUint32(3, true) + 'x' + dv.getUint32(7, true));
  }
  if (type === 2) { frames++; bytes += b.length; if (firstFrameAt === null) { firstFrameAt = Date.now() - t0;
      if (res) console.log('FIRST FRAME at +' + firstFrameAt + 'ms', 'keyframe=' + (b[2]&1)); }
    lastFrameAt = Date.now() - t0; }
  if (type === 3) { const dv = new DataView(e.data); const nameLen = b[8]; const name = new TextDecoder().decode(b.slice(9, 9+nameLen));
    console.log('AUDIO-CONFIG codec=' + b[2] + ' rate=' + dv.getUint32(3,true) + ' ch=' + b[7] + ' name=' + name); }
  if (type === 5) console.log('SCREEN-ACTIVE stream=' + stream + ' active=' + b[2]);
  if (type === 6) console.log('AUDIO-STOPPED');
};
setTimeout(() => {
  const dur = (Date.now() - t0)/1000;
  console.log(`SUMMARY frames=${frames} bytes=${bytes} dur=${dur.toFixed(1)}s fps=${(frames/dur).toFixed(1)} mbps=${(bytes*8/dur/1e6).toFixed(2)} lastFrameAt=${lastFrameAt}`);
  process.exit(0);
}, 8000);
ws.onerror = (e) => { console.log('ERR', e.message || e); process.exit(1); };
