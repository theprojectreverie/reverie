import {Pool} from 'pg';
const p=new Pool({connectionString:process.env.DATABASE_URL});
await p.query("delete from game_servers where server_key like 'reverie-e2e-%'");
await p.query("delete from accounts where email like 'reverie-e2e-%@example.test'");
const r=await p.query("select (select count(*)::int from game_servers where server_key like 'reverie-e2e-%') as test_servers,(select count(*)::int from accounts where email like 'reverie-e2e-%@example.test') as test_accounts");
console.log('CLEANUP',JSON.stringify(r.rows[0]));
await p.end();
