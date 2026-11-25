import { Pool } from 'pg';
const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 1 });
const client = await pool.connect();
client.on('notification', message => {
 if (message.channel === 'reverie_world_events' && message.payload) {
  if (process.send) process.send({ type: 'received', payload: message.payload });
  void client.query('UNLISTEN reverie_world_events').finally(async () => { client.release(); await pool.end(); process.exit(0); });
 }
});
await client.query('LISTEN reverie_world_events');
if (process.send) process.send({ type: 'ready' });
