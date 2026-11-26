import type {PvpUnit} from "./pvp.js";
// Transparent approximation, not Elo. It includes saved equipment stats.
export function guildPartyPower(units:Pick<PvpUnit,"maxHp"|"atk"|"defense"|"speed">[]):number{
 return Math.max(1,Math.round(units.reduce((n,u)=>n+u.maxHp+u.atk*8+u.defense*5+u.speed*2,0)));
}
export const GUILD_DUEL_REMATCH_MINUTES=15;
export function guildPowerCompatible(first:number,second:number,waitingSeconds:number):boolean{
 if(!Number.isFinite(first)||!Number.isFinite(second)||first<=0||second<=0)return false;
 return Math.max(first,second)<=Math.min(first,second)*(waitingSeconds>=90?2:1.5);
}