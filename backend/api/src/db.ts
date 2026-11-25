import pg from "pg";
import {config} from "./config.js";
export const pool=new pg.Pool({connectionString:config.DATABASE_URL,max:12,idleTimeoutMillis:30000,connectionTimeoutMillis:5000,ssl:config.NODE_ENV==="production"?{rejectUnauthorized:true}:undefined});
pool.on("error",e=>console.error({event:"postgres_pool_error",message:e.message}));
