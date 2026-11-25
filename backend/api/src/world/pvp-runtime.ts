import type {PvpState} from "./pvp.js";

export type SequencedPvpEvent={sequence:number;event:Record<string,unknown>};

export function validatePersistedPvpState(value:unknown,matchId:string,sequence:number):value is PvpState {
 if(!value||typeof value!=="object"||Array.isArray(value)||!Number.isSafeInteger(sequence)||sequence<0)return false;
 const state=value as Partial<PvpState>;
 return state.matchId===matchId&&state.status==="active"&&state.sequence===sequence&&
  Number.isSafeInteger(state.sequence)&&Number.isSafeInteger(state.turn)&&state.turn!>0&&
  typeof state.turnPlayerId==="string"&&state.turnPlayerId.length>0&&
  (state.skillbook===undefined||(!!state.skillbook&&typeof state.skillbook==="object"&&!Array.isArray(state.skillbook)))&&
  Number.isSafeInteger(state.seed)&&Array.isArray(state.units)&&state.units.length>=2;
}

export function sequencePvpEvents(firstSequence:number,events:Record<string,unknown>[]):{events:SequencedPvpEvent[];nextSequence:number}|null {
 if(!Number.isSafeInteger(firstSequence)||firstSequence<1||!Array.isArray(events))return null;
 if(events.length===0)return {events:[],nextSequence:firstSequence};
 const last=firstSequence+events.length-1;
 if(!Number.isSafeInteger(last)||last<firstSequence||!Number.isSafeInteger(last+1))return null;
 if(!events.every(event=>!!event&&typeof event==="object"&&!Array.isArray(event)))return null;
 return {events:events.map((event,index)=>({sequence:firstSequence+index,event})),nextSequence:last+1};
}
