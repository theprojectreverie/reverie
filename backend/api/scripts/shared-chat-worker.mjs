import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {chatRoutes} from '../src/routes/chat.ts';
assert.equal(config.NODE_ENV,'development');
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false});
await app.register(jwt,{secret:config.JWT_SECRET});
await app.register(chatRoutes,{prefix:'/v1/chat'});
await app.listen({host:'127.0.0.1',port:0});
console.log(JSON.stringify({ready:true,pid:process.pid,port:app.server.address().port}));
let closing=false;
async function close(){if(closing)return;closing=true;await app.close();await pool.end();process.exit(0);}
process.on('SIGTERM',close);process.on('SIGINT',close);
process.stdin.resume();
process.stdin.on('end',close);