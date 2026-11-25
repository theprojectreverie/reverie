/** Whether retained event history can continuously advance a client cursor. */
export function canReplayFromCursor(cursor:number,oldestSequence:number|null,currentSequence:number,eventCount:number,maxEvents=200):boolean {
 if(!Number.isSafeInteger(cursor)||cursor<0||!Number.isSafeInteger(currentSequence)||currentSequence<0)return false;
 if(!Number.isSafeInteger(eventCount)||eventCount<0||eventCount>maxEvents)return false;
 if(cursor>currentSequence)return false;
 if(oldestSequence===null)return cursor===currentSequence;
 if(!Number.isSafeInteger(oldestSequence)||oldestSequence<1||oldestSequence>currentSequence)return false;
 return cursor>=oldestSequence-1;
}

/** Detect holes inside an otherwise retained replay window. */
export function hasContiguousEventSequences(cursor:number,currentSequence:number,sequences:number[]):boolean {
 if(!Number.isSafeInteger(cursor)||cursor<0||!Number.isSafeInteger(currentSequence)||currentSequence<cursor)return false;
 if(currentSequence===cursor)return sequences.length===0;
 if(sequences.length===0)return false;
 return sequences.every((sequence,index)=>Number.isSafeInteger(sequence)&&sequence===cursor+index+1)
  && sequences[sequences.length-1]===currentSequence;
}
