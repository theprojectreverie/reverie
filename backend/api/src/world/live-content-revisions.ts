import {z} from "zod";
const bps=z.number().int().min(0).max(10000);
export const economicsSchema=z.object({ratesBps:z.object({common:bps,rare:bps,epic:bps,legendary:bps.min(100).max(1500),mythic:bps.min(10).max(500)}).strict(),featuredBps:bps.min(1000).max(10000),single:z.number().int().min(1).max(1200),ten:z.number().int().min(1).max(12000)}).strict().refine(e=>Object.values(e.ratesBps).reduce((a,b)=>a+b,0)===10000&&e.ten>=e.single&&e.ten<=10*e.single,"invalid_economics");
export type Economics=z.infer<typeof economicsSchema>;
const snapshot=z.object({cancelled:z.boolean(),economics:economicsSchema.optional()}).strict();
export const revisionHistory=z.array(z.object({action:z.enum(["cancel","rollback","economics"]),actor:z.string().uuid(),at:z.string().datetime(),reason:z.string().trim().min(8).max(240),state:snapshot,rollbackTo:z.number().int().nonnegative().optional()}).strict()).max(50);
export type RevisionHistory=z.infer<typeof revisionHistory>;
export type RevisionState=z.infer<typeof snapshot>;
export const initialState:RevisionState={cancelled:false};
export function currentState(history?:RevisionHistory):RevisionState{return history?.at(-1)?.state??initialState;}
export const controlSchema=z.discriminatedUnion("action",[
 z.object({action:z.literal("cancel"),expected:z.number().int().nonnegative(),reason:z.string().trim().min(8).max(240)}).strict(),
 z.object({action:z.literal("rollback"),expected:z.number().int().nonnegative(),target:z.number().int().nonnegative(),reason:z.string().trim().min(8).max(240)}).strict(),
 z.object({action:z.literal("economics"),expected:z.number().int().nonnegative(),reason:z.string().trim().min(8).max(240),economics:economicsSchema}).strict()
]);
export type Control=z.infer<typeof controlSchema>;
export function nextHistory(history:RevisionHistory|undefined,action:Control,actor:string,kind:"banner"|"event"):RevisionHistory{
 const old=history??[];if(old.length!==action.expected)throw Error("revision_conflict");if(old.length>=50)throw Error("revision_limit");const current=currentState(old);let state:RevisionState;
 if(action.action==="cancel"){if(current.cancelled)throw Error("already_cancelled");state={...current,cancelled:true};}
 else if(action.action==="economics"){if(kind!=="banner")throw Error("banner_economics_only");state={...current,economics:action.economics};}
 else{if(action.target>=old.length)throw Error("invalid_rollback_target");state=action.target===0?initialState:old[action.target-1]!.state;}
 return revisionHistory.parse([...old,{action:action.action,actor,at:new Date().toISOString(),reason:action.reason,state,...(action.action==="rollback"?{rollbackTo:action.target}:{})}]);
}
