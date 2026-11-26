import type {Pool,PoolClient} from "pg";
import {PAID_MILESTONE} from "./summon.js";

type Db=Pick<Pool|PoolClient,"query">;
export async function auditPaidGuarantees(db:Db,playerId:string){
 // Ledger IDs preserve the order of serialized paid transactions. A missing or
 // mismatching debit makes the cumulative milestone position uncertain.
 const q=await db.query(`WITH paid AS (
  SELECT p.id,p.banner_id,p.created_at,p.pull_count,p.cost,
   d.ledger_id,d.debit_count,d.debit_amount,
   COALESCE((SELECT jsonb_agg(jsonb_build_object('index',r.roll_index,'characterId',r.character_id,'rarity',r.rarity,'featured',r.featured,'kind',r.reward_kind,'marked',COALESCE(r.reward_items->'paid_guaranteed','false'::jsonb),'reviewStatus',v.status,'grantedCharacter',v.granted_character_id,'decidedAt',v.decided_at) ORDER BY r.roll_index)
   FROM gacha_pull_results r LEFT JOIN paid_guarantee_reviews v ON v.pull_id=r.pull_id AND v.roll_index=r.roll_index WHERE r.pull_id=p.id),'[]'::jsonb) AS results
  FROM gacha_pulls p LEFT JOIN LATERAL (
   SELECT min(id) AS ledger_id,count(*)::int AS debit_count,COALESCE(sum(delta),0) AS debit_amount FROM currency_ledger
   WHERE player_id=p.player_id AND currency_id='paid_moonstones' AND reason='gacha_pull' AND ref_type='gacha_pull' AND ref_id=p.id::text
  ) d ON true WHERE p.player_id=$1 AND p.currency_id='paid_moonstones'
 ) SELECT *, (debit_count=1 AND debit_amount=-cost) AS verified FROM paid ORDER BY ledger_id NULLS LAST,id`,[playerId]);
 const historyComplete=q.rows.every(r=>r.verified&&r.results.length===r.pull_count&&r.results.every((v:any,i:number)=>v.index===i));
 let total=0;
 const cases:Array<{pullId:string;bannerId:string;createdAt:string;rollIndex:number;milestone:number|null;characterId:string|null;status:string;reviewStatus:string|null;grantedCharacter:string|null;decidedAt:string|null}>=[];
 for(const p of q.rows){
  const previous=total;total+=p.pull_count;
  const expected=historyComplete&&Math.floor(total/PAID_MILESTONE)>Math.floor(previous/PAID_MILESTONE)?PAID_MILESTONE-(previous%PAID_MILESTONE)-1:-1;
  for(const r of p.results){
   if(r.marked!==true&&r.index!==expected)continue;
   const fulfilled=r.featured===true&&r.kind==="character"&&["legendary","mythic"].includes(r.rarity);
   const status=fulfilled&&p.verified?"fulfilled":r.marked===true&&p.verified?"missed_featured":"needs_review";
   cases.push({pullId:p.id,bannerId:p.banner_id,createdAt:p.created_at,rollIndex:r.index,milestone:historyComplete&&r.index===expected?previous+r.index+1:null,characterId:r.characterId,status,reviewStatus:r.reviewStatus??null,grantedCharacter:r.grantedCharacter??null,decidedAt:r.decidedAt??null});
  }
 }
 return {totalPaidPulls:total,historyComplete,expectedMilestones:Math.floor(total/PAID_MILESTONE),cases};
}
