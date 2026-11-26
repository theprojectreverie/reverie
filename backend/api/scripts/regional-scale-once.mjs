// Operator-controlled local pilot. Dry-run unless explicitly requested.
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
import {createLocalScaler} from "./regional-scale-controller.mjs";
if(config.NODE_ENV==="production"||!["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname))throw Error("Local development only");
const execute=process.argv.includes("--execute");
const policy={regions:(process.env.REVERIE_SCALE_REGIONS??"").split(",").filter(Boolean),build:"0.1.0-dev",capacity:100,maxPerRegion:2,maxTotal:4,managedPrefix:"scale-local-",threshold:0.8};
const db=await pool.connect();
try{
 const q=await db.query("SELECT pg_try_advisory_lock(hashtextextended($1,0)) AS locked",["reverie:local-scaler"]);
 if(!q.rows[0].locked)throw Error("Another local scaling controller is active");
 const controller=createLocalScaler({db,api:process.env.REVERIE_SCALE_API??"http://127.0.0.1:8787",bootstrap:config.GAME_SERVER_BOOTSTRAP_SECRET,bin:process.env.REVERIE_GODOT_BIN,policy,execute});
 // Dry-run only for one-shot invocation. Live child ownership requires a supervised
 // operator process; never leave orphaned children on termination.
 if(execute)throw Error("Live execution is restricted to the isolated integration fixture until process supervision is configured");
 console.log(JSON.stringify(await controller.tick()));
}finally{await db.query("SELECT pg_advisory_unlock(hashtextextended($1,0))",["reverie:local-scaler"]);db.release();await pool.end();}
