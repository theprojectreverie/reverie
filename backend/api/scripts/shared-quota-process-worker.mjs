import Fastify from "fastify";
import rateLimit from "@fastify/rate-limit";
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
import {createSharedRateLimitStore} from "../src/world/shared-rate-limit.ts";
const ns=process.env.REVERIE_QUOTA_QA_NAMESPACE;
if(!/^process_qa_[a-f0-9]{12}$/.test(ns??"")||config.NODE_ENV==="production"||!["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname))throw Error("Disposable local worker only");
const app=Fastify({logger:false});
await app.register(rateLimit,{max:100,timeWindow:60000,store:createSharedRateLimitStore(pool,ns,config.JWT_SECRET),skipOnError:false});
app.get("/probe/:id",{config:{rateLimit:{max:300,timeWindow:60000}}},async()=>({ok:true}));
app.get("/independent",{config:{rateLimit:{max:5,timeWindow:60000}}},async()=>({ok:true}));
await app.listen({host:"127.0.0.1",port:0});
process.send({port:app.server.address().port});
let closing=false;
async function shutdown(){if(closing)return;closing=true;await app.close();await pool.end();process.disconnect?.();}
process.on("message",m=>{if(m==="stop")void shutdown();});
process.on("disconnect",()=>{void shutdown();});
