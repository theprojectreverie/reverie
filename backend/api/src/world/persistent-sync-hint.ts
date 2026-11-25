/** Decide whether a client cursor is behind the durable server event cursor. */
export function shouldSendWorldSyncHint(clientSequence:number,currentSequence:number):boolean{
 if(!Number.isSafeInteger(clientSequence)||clientSequence<0)return false;
 if(!Number.isSafeInteger(currentSequence)||currentSequence<0)return false;
 return currentSequence>clientSequence;
}
