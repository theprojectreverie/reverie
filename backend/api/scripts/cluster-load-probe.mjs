import {performance,monitorEventLoopDelay} from "node:perf_hooks";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
const run=promisify(execFile);
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const pct=(a,q)=>a.length?Math.round(a[Math.max(0,Math.ceil(a.length*q)-1)]*10)/10:null;
export function findSequenceWindow(ranges,sequence){
  let lo=0,hi=ranges.length-1;
  while(lo<=hi){
    const mid=(lo+hi)>>1,w=ranges[mid];
    if(sequence<w[0])hi=mid-1;
    else if(sequence>w[1])lo=mid+1;
    else return w;
  }
  return null;
}
export function verifiedWindowSupersession(window,missingSample,senderSamples,receivedInWindow){
  if(!window||!missingSample||missingSample.sequence<window[0]||missingSample.sequence>window[1])return false;
  return senderSamples.some(sample=>sample.round>missingSample.round&&sample.sequence>missingSample.sequence&&sample.sequence<=window[1]&&receivedInWindow(sample,window[1]));
}

export async function runClusterProbe({clients,playerRows,pool,serverId,mode,serverPid}){
  if(!["legacy","interest"].includes(mode))throw new Error("invalid cluster mode");
  const interested=mode==="interest";
  if(!clients.every(c=>Boolean(c.admission.interestWindows)===interested))throw new Error("wrong negotiated mode");
  const n=clients.length, rounds=Number(process.env.REVERIE_E2E_CLUSTER_ROUNDS??60), size=Number(process.env.REVERIE_E2E_CLUSTER_SIZE??8), spacing=400;
  const checkpointMs=Number(process.env.REVERIE_SERVER_POSITION_CHECKPOINT_MS??0);
  const checkpointMode=Number.isFinite(checkpointMs)&&checkpointMs>0;
  if(!Number.isInteger(rounds)||rounds<1||rounds>1500||!Number.isInteger(size)||size<1||size>100)throw new Error("invalid cluster probe rounds or size");
  const mixed=process.env.REVERIE_E2E_CLUSTER_MIXED==="1";
  if(mixed&&(!interested||rounds>300))throw new Error("mixed load requires negotiated interest mode and at most 300 rounds");
  const ids=playerRows.map(p=>p.id), index=new Map(ids.map((id,i)=>[id,i]));
  const point=(i,r)=>({x:20+Math.floor(i/size)*spacing+r,y:30+i%size});
  // Move legally from the common starting area into separated groups.
  const steps=Math.max(1,Math.ceil(Math.floor((n-1)/size)*spacing/75),Math.ceil((Math.min(n,size)-1)/75));
  const setupInterval=Number(process.env.REVERIE_E2E_CLUSTER_SETUP_MS??150);
  if(!Number.isInteger(setupInterval)||setupInterval<150||setupInterval>1000)throw new Error("invalid setup interval");
  console.log("CLUSTER_SETUP "+JSON.stringify({players:n,steps,intervalMs:setupInterval}));
  for(let step=1;step<=steps;step++){
    await sleep(setupInterval);
    for(let i=0;i<n;i++){
      if(clients[i].socket.readyState!==1)throw new Error("cluster setup socket closed at step "+step+"; open="+clients.filter(c=>c.socket.readyState===1).length);
      clients[i].socket.send(JSON.stringify({type:"position",x:20+Math.min(Math.floor(i/size)*spacing,step*75),y:30+Math.min(i%size,step*75)}));
    }
  }
  const waitState=async r=>{
    for(let attempt=0;attempt<300;attempt++){
      const q=await pool.query("select player_id,x,y from game_server_player_state where server_id=$1",[serverId]);
      if(ids.every((id,i)=>q.rows.some(row=>row.player_id===id&&Number(row.x)===point(i,r).x&&Number(row.y)===point(i,r).y)))return;
      await sleep(50);
    }
    const final=(await pool.query("select player_id,x,y from game_server_player_state where server_id=$1",[serverId])).rows;
    const matches=ids.filter((id,i)=>final.some(row=>row.player_id===id&&Number(row.x)===point(i,r).x&&Number(row.y)===point(i,r).y)).length;
    const open=clients.filter(c=>c.socket.readyState===1).length;
    const committed=(await pool.query("select count(*)::int AS n from game_server_world_events where server_id=$1 AND event_type='position'",[serverId])).rows[0].n;
    throw new Error("cluster positions not committed: "+JSON.stringify({round:r,matchingPlayers:matches,totalPlayers:n,openSockets:open,committedPositionEvents:committed}));
  };
   if(!checkpointMode){await waitState(0);await sleep(300);}
  // Isolated fixture only: count actual row bytes, not a production table-wide scan.
  const eventStorage=async()=>{
    const q=await pool.query("select count(*)::int as events,coalesce(sum(pg_column_size(e)),0)::bigint as row_bytes,max(sequence)::text as last_sequence from game_server_world_events e where server_id=$1",[serverId]);
    const row=q.rows[0];
    return {events:Number(row.events),rowBytes:Number(row.row_bytes),lastSequence:Number(row.last_sequence??0)};
  };
  const storageBefore=await eventStorage();

  let bytes=0,packets=0,clientSentBytes=0,memberRecords=0,rejected=0,foreign=0,sequenceGaps=0;
  const foreignExamples=[];
  let emoteDeliveries=0,pingSent=0,pongReceived=0,syncHints=0,mixedBytes=0,invalidEmotes=0;
  const expectedEmotes=new Uint16Array(n),seenEmotes=new Uint16Array(n*n),expectedPings=new Uint16Array(n),seenPongs=new Uint16Array(n);
  const closes=[],rejections={};
   const expectedPerRound=ids.reduce((sum,_,i)=>sum+Math.min(size,n-Math.floor(i/size)*size)-1,0);
   const expected=expectedPerRound*rounds;
  // Fixed-size arrays remain bounded even for 100 players for five minutes.
  if((rounds+1)*n*n>15010000)throw new Error("cluster probe memory budget exceeded");
  // Compact fixed-size accounting: the test harness must not accumulate millions of strings.
  const receipts=new Uint8Array((rounds+1)*n*n),sent=new Float64Array((rounds+1)*n),latency=new Float32Array(expected),lastCursor=Array(n).fill(null);
  let receivedCount=0, finalDeliveries=0;
   const finalExpected=expectedPerRound;
  // Store the actual window endpoint for each observed sample. This allows
  // checking intentional supersession against the exact transmitted range.
  const receiptWindowEnd=new Uint32Array((rounds+1)*n*n);
  const windows=Array.from({length:n},()=>[]);
  const batchSize=Number(process.env.REVERIE_SERVER_EVENT_BATCH_SIZE??32);
  let shortSendIntervals=0, minimumSendInterval=Infinity;
  const memorySamples=[];
  const sampleMemory=async()=>{
    if(!serverPid||process.platform!=="win32")return;
    try{
      // Godot's Windows console executable launches the real engine as a child.
      // Measure the full dedicated-server process tree, not just the launcher.
       const command="$root="+Number(serverPid)+"; $ids=@($root); for($i=0;$i -lt $ids.Count;$i++){ $child=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId = '+$ids[$i]) | Select-Object -ExpandProperty ProcessId); $ids+=@($child | Where-Object {$_ -notin $ids}) }; $ps=@(Get-Process -Id $ids -ErrorAction SilentlyContinue); @($ps | ForEach-Object {[pscustomobject]@{Id=$_.Id;ProcessName=$_.ProcessName;WorkingSet64=$_.WorkingSet64;PrivateMemorySize64=$_.PrivateMemorySize64;CpuSeconds=$_.TotalProcessorTime.TotalSeconds}}) | ConvertTo-Json -Compress";
      const {stdout}=await run("powershell.exe",["-NoProfile","-Command",command],{timeout:8000,windowsHide:true});
      const parsed=JSON.parse(stdout.trim());
      const processes=Array.isArray(parsed)?parsed:[parsed];
       if(processes.length&&processes.every(p=>Number.isFinite(p.WorkingSet64)&&Number.isFinite(p.PrivateMemorySize64)&&Number.isFinite(p.CpuSeconds)))memorySamples.push({sampledAt:performance.now(),workingSet:processes.reduce((sum,p)=>sum+p.WorkingSet64,0),privateBytes:processes.reduce((sum,p)=>sum+p.PrivateMemorySize64,0),cpuSeconds:processes.reduce((sum,p)=>sum+p.CpuSeconds,0),processes:processes.map(p=>({pid:p.Id,name:p.ProcessName}))});
    }catch{}
  };
  const listeners=clients.map((c,receiver)=>{
    const listener=raw=>{
      let m;try{m=JSON.parse(String(raw));}catch{return;}
      if(m.type==="rejected"){rejected++;rejections[m.reason??"unknown"]=(rejections[m.reason??"unknown"]??0)+1;return;}
      if(mixed&&["pong","world_sync_hint","emote"].includes(m.type)){
        mixedBytes+=Buffer.byteLength(raw);
        if(m.type==="pong"){pongReceived++;seenPongs[receiver]++;return;}
        if(m.type==="world_sync_hint"){syncHints++;return;}
        const sender=index.get(m.playerId);
        if(sender===undefined||m.emoteId!=="wave"||!Number.isSafeInteger(m.sequence)){invalidEmotes++;return;}
        if(lastCursor[receiver]!==null&&m.sequence!==lastCursor[receiver]+1)sequenceGaps++;
        lastCursor[receiver]=m.sequence;
        seenEmotes[sender*n+receiver]++;emoteDeliveries++;
        return;
      }
      if(interested?m.type!=="world_position_window":m.type!=="position")return;
      bytes+=Buffer.byteLength(raw);packets++;
      if(interested){
        if(lastCursor[receiver]!==null&&m.fromSequence!==lastCursor[receiver]+1)sequenceGaps++;
        if(!Number.isSafeInteger(m.fromSequence)||!Number.isSafeInteger(m.sequence)||m.fromSequence>m.sequence)sequenceGaps++;
        lastCursor[receiver]=m.sequence;
        windows[receiver].push([m.fromSequence,m.sequence]);
      }
      const members=interested?m.members:[m];
      memberRecords+=members.length;
      for(const member of members){
        const i=index.get(member.playerId);if(i===undefined||i===receiver)continue;
        const same=Math.floor(i/size)===Math.floor(receiver/size);
        if(interested&&!same){foreign++;if(foreignExamples.length<12)foreignExamples.push({receiver,member:i,receiverGroup:Math.floor(receiver/size),memberGroup:Math.floor(i/size),memberX:member.x,memberY:member.y});continue;}
         if(!same){if(foreignExamples.length<12)foreignExamples.push({receiver,member:i,receiverGroup:Math.floor(receiver/size),memberGroup:Math.floor(i/size),memberX:member.x,memberY:member.y});continue;}
        const r=member.x-point(i,0).x;
        if(r<1||r>rounds||member.y!==point(i,0).y)continue;
        const key=r*n+i;
        if(!sent[key])continue;
        const receipt=key*n+receiver;
        if(receipts[receipt])continue;
        receipts[receipt]=1;
        if(interested)receiptWindowEnd[receipt]=m.sequence-storageBefore.lastSequence;
        if(r===rounds)finalDeliveries++;
        latency[receivedCount++]=performance.now()-sent[key];
      }
    };
    c.socket.on("message",listener);return listener;
  });
  const closeListeners=clients.map((c,i)=>{const handler=(code,reason)=>closes.push({client:i,code,reason:String(reason)});c.socket.on("close",handler);return handler;});
  let memoryTimer;
  let memoryPending=Promise.resolve();
  const loopDelay=monitorEventLoopDelay({resolution:10});
  loopDelay.enable();
  try{
    await sampleMemory();
    memoryTimer=setInterval(()=>{memoryPending=sampleMemory();},10000);
    const start=performance.now();
    let previousProgressCount=0;
    for(let r=1;r<=rounds;r++){
      await sleep(Math.max(0,start+r*200-performance.now()));
      for(let i=0;i<n;i++){
        const now=performance.now();
        if(r>1){const interval=now-sent[(r-1)*n+i];minimumSendInterval=Math.min(minimumSendInterval,interval);if(interval<40)shortSendIntervals++;}
        if(clients[i].socket.readyState!==1)throw new Error("cluster movement socket closed at round "+r);
        const positionPayload=JSON.stringify({type:"position",...point(i,r)});
        sent[r*n+i]=now;clientSentBytes+=Buffer.byteLength(positionPayload);clients[i].socket.send(positionPayload);
        // Stagger auxiliary traffic instead of deliberately synchronizing every
        // heartbeat and emote across 100 clients in the same frame.
        if(mixed&&r<rounds&&(r+i)%50===0){
          const emotePayload=JSON.stringify({type:"emote",emoteId:"wave"});const pingPayload=JSON.stringify({type:"ping",lastSequence:lastCursor[i]??storageBefore.lastSequence});
          clientSentBytes+=Buffer.byteLength(emotePayload)+Buffer.byteLength(pingPayload);clients[i].socket.send(emotePayload);expectedEmotes[i]++;
          clients[i].socket.send(pingPayload);expectedPings[i]++;pingSent++;
        }
      }
      if(r%150===0){
        console.log("CLUSTER_PROGRESS "+JSON.stringify({round:r,rounds,elapsedSeconds:Math.round((performance.now()-start)/1000),openSockets:clients.filter(c=>c.socket.readyState===1).length,nearbyDeliveries:receivedCount,deliveriesSinceLastSample:receivedCount-previousProgressCount,sequenceGaps,rejected}));
        previousProgressCount=receivedCount;
      }
     }
     if(checkpointMode){
       await sleep(checkpointMs+50);
       for(let i=0;i<n;i++){
         if(clients[i].socket.readyState!==1)throw new Error("cluster checkpoint socket closed");
         const finalPayload=JSON.stringify({type:"position",...point(i,rounds)});
         sent[rounds*n+i]=performance.now();clientSentBytes+=Buffer.byteLength(finalPayload);clients[i].socket.send(finalPayload);
       }
       await sleep(checkpointMs+100);
     }
     try{await waitState(rounds);}catch(error){
      console.log("CLUSTER_LOAD_DIAGNOSTIC "+JSON.stringify({mode,players:n,rounds,groupSize:size,packets,payloadBytes:bytes,nearbyDeliveries:receivedCount,expectedNearby:expected,rejected,rejections,closes,sequenceGaps}));
      throw error;
    }
    const until=performance.now()+10000;
    const latestStorage=await eventStorage();
    const expectedEmoteDeliveries=expectedEmotes.reduce((sum,count)=>sum+count,0)*n;
    while((finalDeliveries<finalExpected||(interested&&lastCursor.some(cursor=>cursor===null||cursor<latestStorage.lastSequence))||(mixed&&(emoteDeliveries<expectedEmoteDeliveries||pongReceived<pingSent)))&&performance.now()<until)await sleep(50);
    clearInterval(memoryTimer);await memoryPending;await sampleMemory();
     const measured=latency.subarray(0,receivedCount);measured.sort();
     const harnessEventLoopMs={p50:loopDelay.percentile(50)/1e6,p95:loopDelay.percentile(95)/1e6,p99:loopDelay.percentile(99)/1e6,max:loopDelay.max/1e6};
     const cpuFirst=memorySamples[0],cpuLast=memorySamples[memorySamples.length-1];
     const serverCpuPercent=cpuFirst&&cpuLast&&cpuLast.sampledAt>cpuFirst.sampledAt?((cpuLast.cpuSeconds-cpuFirst.cpuSeconds)/(cpuLast.sampledAt-cpuFirst.sampledAt))*100000:null;
    if(memorySamples.length)console.log("SERVER_MEMORY_SAMPLES "+JSON.stringify(memorySamples));
    // Verify all proposals reached durable storage. For a missing intermediate
    // sample, require proof of a later sample in the SAME received sequence
    // window, for the SAME sender and receiver. Never excuse a missing final
    // state, a missing durable proposal, or a genuine cursor gap.
    const durable=await pool.query("select sequence::text,player_id,payload from game_server_world_events where server_id=$1 and sequence>$2 and event_type='position' order by sequence",[serverId,storageBefore.lastSequence]);
    const committed=new Map(),bySender=Array.from({length:n},()=>[]);
    for(const e of durable.rows){
      const i=index.get(e.player_id);if(i===undefined)continue;
      const r=Number(e.payload.x)-point(i,0).x;
      if(!Number.isInteger(r)||r<1||r>rounds||Number(e.payload.y)!==point(i,0).y)continue;
      const sample={sequence:Number(e.sequence),round:r};
      committed.set(r*n+i,sample);bySender[i].push(sample);
    }
    const windowFor=(receiver,sequence)=>findSequenceWindow(windows[receiver],sequence);
     const missing={uncommittedProposals:0,verifiedSupersededDeliveries:0,unexplainedCommittedDeliveries:0,missingFinalDeliveries:0,examples:[]};
     for(let r=1;r<=rounds;r++)for(let i=0;i<n;i++){
       const key=r*n+i,e=committed.get(key);
       if(checkpointMode&&r<rounds)continue;
      for(let receiver=Math.floor(i/size)*size;receiver<Math.min(n,(Math.floor(i/size)+1)*size);receiver++){
        if(receiver===i||receipts[key*n+receiver])continue;
        const window=e&&interested?windowFor(receiver,e.sequence):null;
        const later=verifiedWindowSupersession(window,e,bySender[i],(sample,end)=>receiptWindowEnd[(sample.round*n+i)*n+receiver]===end-storageBefore.lastSequence);
        const category=!e?"uncommittedProposals":later&&r<rounds?"verifiedSupersededDeliveries":"unexplainedCommittedDeliveries";
        missing[category]++;
        if(r===rounds)missing.missingFinalDeliveries++;
        if(missing.examples.length<12)missing.examples.push({round:r,sender:i,receiver,category,sequence:e?.sequence??null,window});
      }
    }
    const finalCursorMatch=!interested||lastCursor.every(cursor=>cursor===latestStorage.lastSequence);
    let mixedMatch=true;
    if(mixed){
      const emoteRows=await pool.query("select player_id,count(*)::int as n from game_server_world_events where server_id=$1 and sequence>$2 and event_type='emote' group by player_id",[serverId,storageBefore.lastSequence]);
      const committedEmotes=new Map(emoteRows.rows.map(row=>[row.player_id,Number(row.n)]));
      mixedMatch=ids.every((id,i)=>(committedEmotes.get(id)??0)===expectedEmotes[i]&&seenPongs[i]===expectedPings[i]&&ids.every((_,receiver)=>seenEmotes[i*n+receiver]===expectedEmotes[i]))&&invalidEmotes===0;
      console.log("MIXED_LOAD_RESULT "+JSON.stringify({emoteProposals:expectedEmoteDeliveries/n,expectedEmoteDeliveries,emoteDeliveries,pingSent,pongReceived,syncHints,mixedBytes,invalidEmotes,mixedMatch}));
    }
    console.log("CLUSTER_DELIVERY_AUDIT "+JSON.stringify({committedUniqueSamples:committed.size,proposedSamples:n*rounds,shortSendIntervals,minimumSendIntervalMs:Math.round(minimumSendInterval*10)/10,finalDeliveries,finalExpected,finalCursorMatch,missing}));
    const storageAfter=await eventStorage();
    console.log("WORLD_EVENT_STORAGE "+JSON.stringify({before:storageBefore,after:storageAfter,addedRows:storageAfter.events-storageBefore.events,addedRowBytes:storageAfter.rowBytes-storageBefore.rowBytes}));

     const requiredCommitted=checkpointMode?n:n*rounds;
     const finalCommits=checkpointMode?ids.filter((_,i)=>committed.has(rounds*n+i)).length:committed.size;
     const deliveryComplete=checkpointMode?finalDeliveries===finalExpected:receivedCount+missing.verifiedSupersededDeliveries===expected;
     console.log("CLUSTER_LOAD_RESULT "+JSON.stringify({mode,players:n,rounds,groupSize:size,batchSize,checkpointMs,proposals:n*rounds,packets,payloadBytes:bytes,clientSentBytes,memberRecords,nearbyDeliveries:receivedCount,expectedNearby:checkpointMode?null:expected,requiredCommitted,finalCommits,finalDeliveries,finalExpected,p50Ms:pct(measured,.5),p95Ms:pct(measured,.95),p99Ms:pct(measured,.99),maxMs:pct(measured,1),harnessEventLoopMs,serverCpuPercent,foreign,foreignExamples,sequenceGaps,rejected,unexpectedCloses:closes.length}));
     if(finalCommits!==requiredCommitted||!deliveryComplete||missing.uncommittedProposals||missing.unexplainedCommittedDeliveries||missing.missingFinalDeliveries||finalDeliveries!==finalExpected||!finalCursorMatch||!mixedMatch||foreign||sequenceGaps||rejected||closes.length)throw new Error("cluster delivery invariant failed");
  }finally{clearInterval(memoryTimer);loopDelay.disable();clients.forEach((c,i)=>{c.socket.off("message",listeners[i]);c.socket.off("close",closeListeners[i]);});}
}
