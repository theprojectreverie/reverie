import Stripe from "stripe";
import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import {z} from "zod";
import {config} from "../config.js";
import {pool} from "../db.js";

// Provisional sandbox catalogue, not approved commercial pricing.
export const TEST_PACKAGES=[{id:"moon_120",stones:120,amountCents:120},{id:"moon_600",stones:600,amountCents:600},{id:"moon_1200",stones:1200,amountCents:1200}] as const;
// Verified one-time prices in Project Reverie sandbox; never use in live mode.
export const SANDBOX_PRICES:Record<string,string>={moon_120:"price_1UfxaO2LtUT32LTcTqbZ6N9V",moon_600:"price_1UfxaU2LtUT32LTcIVY2cWmY",moon_1200:"price_1UfxaW2LtUT32LTcnQEm2UNg"};
const uuid=z.string().uuid();
const packageRequest=z.object({packageId:z.string(),requestId:uuid}).strict();
const limitValue=z.number().int().min(0).max(100000000).nullable();
const spendingInput=z.object({dailyCents:limitValue,monthlyCents:limitValue}).strict();
async function spending(id:string,db:Pick<typeof pool,"query">=pool){
 const r=(await db.query(`WITH totals AS (SELECT COALESCE(sum(amount_cents) FILTER(WHERE status='pending' OR (status IN ('credited','refunded','refund_review') AND GREATEST(created_at,COALESCE(credited_at,created_at))>=date_trunc('day',now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC')),0)::text AS daily,COALESCE(sum(amount_cents) FILTER(WHERE status='pending' OR (status IN ('credited','refunded','refund_review') AND GREATEST(created_at,COALESCE(credited_at,created_at))>=date_trunc('month',now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC')),0)::text AS monthly,COALESCE(sum(amount_cents) FILTER(WHERE status='pending'),0)::text AS pending FROM stripe_sandbox_orders WHERE player_id=$1) SELECT totals.*,l.daily_cents,l.monthly_cents FROM totals LEFT JOIN stripe_sandbox_spending_limits l ON l.player_id=$1`,[id])).rows[0];
 return {dailyCents:r.daily_cents??null,monthlyCents:r.monthly_cents??null,dailyCommittedCents:Number(r.daily),monthlyCommittedCents:Number(r.monthly),pendingCents:Number(r.pending),periodTimeZone:"UTC"};
}
type Order={id:string;player_id:string;request_id:string;package_id:string;stones:number;amount_cents:number;currency:string;status:string;session_id:string|null;payment_intent_id:string|null;created_at:string;credited_at:string|null;refunded_cents:number;dispute_seen:boolean;review_reason:string|null};
type CheckoutProvider=Pick<Stripe,"checkout"|"webhooks">;
function publicOrder(o:Order){return {id:o.id,requestId:o.request_id,packageId:o.package_id,stones:o.stones,amountCents:o.amount_cents,currency:o.currency,status:o.status,createdAt:o.created_at,creditedAt:o.credited_at,refundedCents:o.refunded_cents,disputeSeen:o.dispute_seen,reviewReason:o.review_reason};}
async function identity(req:FastifyRequest,reply:FastifyReply):Promise<string|null>{
 try{await req.jwtVerify();const c=req.user as {sub?:string;playerId?:string;tokenVersion?:number};
 if(c.sub&&c.playerId&&Number.isInteger(c.tokenVersion)){
 const q=await pool.query("SELECT p.id FROM players p JOIN accounts a ON a.id=p.account_id WHERE p.id=$1 AND a.id=$2 AND a.status='active' AND a.token_version=$3",[c.playerId,c.sub,c.tokenVersion]);if(q.rows[0])return q.rows[0].id;
 }}catch{}
 reply.code(401).send({error:"authentication_required"});return null;
}
function configuredProvider():CheckoutProvider|null{
 // A test key must NEVER grant currency on a production or remote database.
 if(config.NODE_ENV!=="development"||config.HOST!=="127.0.0.1"||!['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname)||process.env.STRIPE_TEST_ENABLED!=="true")return null;
 const key=process.env.STRIPE_TEST_SECRET_KEY??"";
 const signed=/^whsec_[A-Za-z0-9_]+$/.test(process.env.STRIPE_TEST_WEBHOOK_SECRET??"");
 const manual=process.env.STRIPE_TEST_MANUAL_RECONCILE==="true";
 if(!/^(sk|rk)_test_[A-Za-z0-9_]+$/.test(key)||(!signed&&!manual))return null;
 return new Stripe(key,{maxNetworkRetries:2,timeout:15000});
}
function intentId(s:Stripe.Checkout.Session):string|null{return typeof s.payment_intent==="string"?s.payment_intent:s.payment_intent?.id??null;}
function matches(o:Order,s:Stripe.Checkout.Session):boolean{
 return s.livemode===false&&s.mode==="payment"&&s.client_reference_id===o.id&&s.metadata?.order_id===o.id&&s.metadata?.player_id===o.player_id&&s.metadata?.package_id===o.package_id&&s.amount_total===o.amount_cents&&s.currency===o.currency&&(!o.session_id||s.id===o.session_id);
}
async function fulfill(s:Stripe.Checkout.Session):Promise<Order|null>{
 const id=s.metadata?.order_id;if(!uuid.safeParse(id).success)return null;
 const db=await pool.connect();try{
 await db.query("BEGIN");
 let o=(await db.query<Order>("SELECT * FROM stripe_sandbox_orders WHERE id=$1 FOR UPDATE",[id])).rows[0];
 if(!o||!matches(o,s)){await db.query("ROLLBACK");return null;}
 const pi=intentId(s);
 const charge=typeof s.payment_intent==="object"&&s.payment_intent? s.payment_intent.latest_charge:null;
 const reversed=typeof charge==="object"&&charge&&(charge.refunded||charge.amount_refunded>0||charge.disputed);
 if(o.status==="pending"&&reversed&&typeof charge==="object"&&charge){
 const amount=Math.min(o.amount_cents,Math.max(0,charge.amount_refunded));
 const full=charge.refunded&&amount===o.amount_cents&&!charge.disputed;
 o=(await db.query<Order>("UPDATE stripe_sandbox_orders SET status=$4,session_id=$2,payment_intent_id=$3,refunded_cents=$5,dispute_seen=$6,review_reason=$7,updated_at=now() WHERE id=$1 RETURNING *",[o.id,s.id,pi,full?"refunded":"refund_review",amount,charge.disputed,full?null:charge.disputed?"payment_dispute":"partial_refund"])).rows[0]!;
 }
 else if(o.status==="pending"&&s.payment_status==="paid"&&s.status==="complete"&&pi){
 const balance=(await db.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'paid_moonstones',$2) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=player_currencies.balance+EXCLUDED.balance RETURNING balance::text",[o.player_id,o.stones])).rows[0].balance;
 await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'paid_moonstones',$2,$3,'stripe_sandbox_purchase','stripe_order',$4,$5)",[o.player_id,o.stones,balance,o.id,"stripe:sandbox:"+o.id]);
 o=(await db.query<Order>("UPDATE stripe_sandbox_orders SET status='credited',session_id=$2,payment_intent_id=$3,credited_at=now(),updated_at=now() WHERE id=$1 RETURNING *",[o.id,s.id,pi])).rows[0]!;
 }else if(o.status==="pending"&&s.status==="expired"){
 o=(await db.query<Order>("UPDATE stripe_sandbox_orders SET status='expired',updated_at=now() WHERE id=$1 RETURNING *",[o.id])).rows[0]!;
 }
 await db.query("COMMIT");return o;
 }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
}
// Refund events report cumulative amounts. Review is sticky: a later top-up
// must not automatically pay for an older spent or disputed purchase.
async function refundReview(paymentIntent:string,refundedCents:number,disputed:boolean):Promise<void>{
 const db=await pool.connect();try{await db.query("BEGIN");
 const o=(await db.query<Order>("SELECT * FROM stripe_sandbox_orders WHERE payment_intent_id=$1 FOR UPDATE",[paymentIntent])).rows[0];
 if(!o||o.status==="refunded"||o.status==="expired"){await db.query("COMMIT");return;}
 if(!Number.isInteger(refundedCents)||refundedCents<0||refundedCents>o.amount_cents)throw Error("invalid_refund_amount");
 const amount=Math.max(o.refunded_cents,refundedCents), dispute=o.dispute_seen||disputed;
 let status="refund_review",reason=o.review_reason??(dispute?"payment_dispute":amount<o.amount_cents?"partial_refund":"wallet_review");
 if(dispute)reason="payment_dispute";
 else if(amount===o.amount_cents&&!o.credited_at){status="refunded";reason="";}
 else if(amount===o.amount_cents&&o.status!=="refund_review"&&o.credited_at){
 // Serialize with wallet spending. Any debit after this purchase makes
 // attribution ambiguous, so require review rather than clawing back later funds.
 const wallet=(await db.query("SELECT balance FROM player_currencies WHERE player_id=$1 AND currency_id='paid_moonstones' FOR UPDATE",[o.player_id])).rows[0];
 const grant=(await db.query("SELECT id FROM currency_ledger WHERE player_id=$1 AND currency_id='paid_moonstones' AND reason='stripe_sandbox_purchase' AND ref_id=$2",[o.player_id,o.id])).rows[0];
 const spent=grant?(await db.query("SELECT 1 FROM currency_ledger WHERE player_id=$1 AND currency_id='paid_moonstones' AND delta<0 AND id>$2 LIMIT 1",[o.player_id,grant.id])).rowCount:1;
 if(wallet&&BigInt(wallet.balance)>=BigInt(o.stones)&&!spent){
 const q=await db.query("UPDATE player_currencies SET balance=balance-$2 WHERE player_id=$1 AND currency_id='paid_moonstones' AND balance>=$2 RETURNING balance::text",[o.player_id,o.stones]);
 if(q.rowCount){await db.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'paid_moonstones',$2,$3,'stripe_sandbox_refund','stripe_order',$4,$5)",[o.player_id,-o.stones,q.rows[0].balance,o.id,"stripe:sandbox:refund:"+o.id]);status="refunded";reason="";}
 }else reason="spent_or_unattributed_stones";
 }
 await db.query("UPDATE stripe_sandbox_orders SET status=$2,refunded_cents=$3,dispute_seen=$4,review_reason=$5,updated_at=now() WHERE id=$1",[o.id,status,amount,dispute,reason||null]);await db.query("COMMIT");
 }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
}
async function getOrRecoverSession(provider:CheckoutProvider,o:Order):Promise<Stripe.Checkout.Session>{
 const meta={order_id:o.id,player_id:o.player_id,package_id:o.package_id};
 const base="http://127.0.0.1:"+config.PORT+"/v1/shop/return";
 const session=o.session_id?await provider.checkout.sessions.retrieve(o.session_id,{expand:["payment_intent.latest_charge"]}):await provider.checkout.sessions.create({mode:"payment",allowed_payment_method_types:["card"],client_reference_id:o.id,metadata:meta,payment_intent_data:{metadata:meta},line_items:[{price:SANDBOX_PRICES[o.package_id],quantity:1}],success_url:base+"?result=success",cancel_url:base+"?result=cancel",expires_at:Math.floor(new Date(o.created_at).getTime()/1000)+3600},{idempotencyKey:"reverie-sandbox:"+o.id});
 if(!matches(o,session))throw Error("checkout_mismatch");
 await pool.query("UPDATE stripe_sandbox_orders SET session_id=$2,payment_intent_id=COALESCE(payment_intent_id,$3),updated_at=now() WHERE id=$1 AND (session_id IS NULL OR session_id=$2)",[o.id,session.id,intentId(session)]);
 return session;
}
export function makeShopRoutes(provider:CheckoutProvider|null,signingSecret:string):FastifyPluginAsync{return async app=>{
 app.addHook("onSend",async(_req,reply,payload)=>{reply.header("Cache-Control","no-store");return payload;});
 app.get("/catalog",async(req,reply)=>{const id=await identity(req,reply);if(!id)return;return {playerId:id,enabled:!!provider,testMode:true,verificationMode:provider?(signingSecret?"webhook":"manual"):"disabled",currency:"eur",packages:TEST_PACKAGES};});
 app.get("/orders",async(req,reply)=>{const id=await identity(req,reply);if(!id)return;const q=await pool.query<Order>("SELECT * FROM stripe_sandbox_orders WHERE player_id=$1 ORDER BY created_at DESC LIMIT 30",[id]);return {playerId:id,orders:q.rows.map(publicOrder)};});
 app.get("/spending",{config:{rateLimit:{max:30,timeWindow:"1 minute"}}},async(req,reply)=>{const id=await identity(req,reply);if(!id)return;return {playerId:id,testMode:true,spending:await spending(id)};});
 app.post("/spending",{config:{rateLimit:{max:10,timeWindow:"1 minute"}}},async(req,reply)=>{
  const id=await identity(req,reply);if(!id)return;const input=spendingInput.safeParse(req.body);if(!input.success)return reply.code(400).send({error:"invalid_spending_limits"});
  const db=await pool.connect();try{await db.query("BEGIN");await db.query("SELECT id FROM players WHERE id=$1 FOR UPDATE",[id]);await db.query("INSERT INTO stripe_sandbox_spending_limits(player_id,daily_cents,monthly_cents) VALUES($1,$2,$3) ON CONFLICT(player_id) DO UPDATE SET daily_cents=EXCLUDED.daily_cents,monthly_cents=EXCLUDED.monthly_cents,updated_at=now()",[id,input.data.dailyCents,input.data.monthlyCents]);const result=await spending(id,db);await db.query("COMMIT");return {playerId:id,testMode:true,spending:result};}catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 });
 // Receipts reflect the recorded purchase ledger, not browser redirects.
 app.get("/receipt/:orderId",{config:{rateLimit:{max:30,timeWindow:"1 minute"}}},async(req,reply)=>{
  const id=await identity(req,reply);if(!id)return;
  const input=z.object({orderId:uuid}).strict().safeParse(req.params);if(!input.success)return reply.code(400).send({error:"invalid_order"});
  const q=await pool.query(`SELECT o.*,l.id::text AS ledger_id,l.delta::text AS ledger_delta FROM stripe_sandbox_orders o JOIN currency_ledger l ON l.player_id=o.player_id AND l.currency_id='paid_moonstones' AND l.reason='stripe_sandbox_purchase' AND l.ref_type='stripe_order' AND l.ref_id=o.id::text WHERE o.id=$1 AND o.player_id=$2 AND o.credited_at IS NOT NULL AND o.status IN ('credited','refund_review','refunded')`,[input.data.orderId,id]);
  const o=q.rows[0];if(!o)return reply.code(404).send({error:"receipt_not_found"});
  if(q.rows.length!==1||BigInt(o.ledger_delta)!==BigInt(o.stones))return reply.code(409).send({error:"receipt_requires_review"});
  const money=(c:number)=>"EUR "+(c/100).toFixed(2);
  const receipt=["REVERIE | SANDBOX PURCHASE RECORD","TEST ONLY - NOT A TAX INVOICE - NO REAL MONEY CHARGED","", "Order: "+o.id,"Verified at (UTC): "+new Date(o.credited_at).toISOString(),"Package: "+o.stones+" Paid Moonstones","Test payment: "+money(o.amount_cents),"Purchase ledger reference: "+o.ledger_id,"Recorded status: "+o.status,"Recorded test refund: "+money(o.refunded_cents),"Dispute recorded: "+(o.dispute_seen?"Yes":"No"),"Review reason: "+(o.review_reason??"None recorded"),"Record generated (UTC): "+new Date().toISOString(),"","This is a snapshot of Reverie's server records. Later refunds or disputes may change the recorded status. It is not proof of a real-money payment."].join("\n");
  return {playerId:id,testMode:true,orderId:o.id,filename:"reverie-test-receipt-"+o.id+".txt",receipt};
 });
 // Read-only ledger, available even when checkout is disabled.
 const ledgerInput=z.object({limit:z.coerce.number().int().min(1).max(50).default(20),before:z.string().regex(/^[1-9][0-9]{0,18}$/).refine(v=>BigInt(v)<=9223372036854775807n).optional()}).strict();
 app.get("/ledger",{config:{rateLimit:{max:60,timeWindow:"1 minute"}}},async(req,reply)=>{
  const id=await identity(req,reply);if(!id)return;
  const parsed=ledgerInput.safeParse(req.query);if(!parsed.success)return reply.code(400).send({error:"invalid_ledger_query"});
  const {limit,before}=parsed.data;
  if(before&&!(await pool.query("SELECT 1 FROM currency_ledger WHERE id=$1 AND player_id=$2 AND currency_id='paid_moonstones'",[before,id])).rowCount)return reply.code(400).send({error:"invalid_ledger_cursor"});
  const q=await pool.query(`WITH page AS (
    SELECT l.id,l.delta::text,l.balance_after::text,l.reason,l.ref_type,l.ref_id,l.created_at
    FROM currency_ledger l WHERE l.player_id=$1 AND l.currency_id='paid_moonstones' AND ($2::bigint IS NULL OR l.id<$2)
    ORDER BY l.id DESC LIMIT $3
   ) SELECT COALESCE((SELECT balance::text FROM player_currencies WHERE player_id=$1 AND currency_id='paid_moonstones'),'0') AS balance,
   COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id::text,'delta',p.delta,'balanceAfter',p.balance_after,'reason',p.reason,'referenceType',p.ref_type,'referenceId',p.ref_id,'createdAt',p.created_at,
   'order',CASE WHEN o.id IS NOT NULL THEN jsonb_build_object('id',o.id,'amountCents',o.amount_cents,'currency',o.currency,'stones',o.stones,'status',o.status) END,
   'summon',CASE WHEN g.id IS NOT NULL THEN jsonb_build_object('id',g.id,'bannerId',g.banner_id,'count',g.pull_count) END) ORDER BY p.id DESC)
   FROM page p LEFT JOIN stripe_sandbox_orders o ON p.ref_type='stripe_order' AND p.ref_id=o.id::text AND o.player_id=$1
   LEFT JOIN gacha_pulls g ON p.ref_type='gacha_pull' AND p.ref_id=g.id::text AND g.player_id=$1),'[]'::jsonb) AS entries`,[id,before??null,limit+1]);
  const rows=q.rows[0].entries;const entries=rows.slice(0,limit);
  return {playerId:id,testMode:true,balance:q.rows[0].balance,entries,nextCursor:rows.length>limit?entries.at(-1).id:null};
 });
 app.post("/checkout",{config:{rateLimit:{max:10,timeWindow:"1 minute"}}},async(req,reply)=>{
 const id=await identity(req,reply);if(!id)return;if(!provider)return reply.code(503).send({error:"stripe_sandbox_not_configured"});
 const body=packageRequest.safeParse(req.body);if(!body.success)return reply.code(400).send({error:"invalid_checkout"});
 const pack=TEST_PACKAGES.find(p=>p.id===body.data.packageId);if(!pack)return reply.code(400).send({error:"unknown_package"});
 const db=await pool.connect();let o:Order;
 try{await db.query("BEGIN");await db.query("SELECT id FROM players WHERE id=$1 FOR UPDATE",[id]);
 const existing=(await db.query<Order>("SELECT * FROM stripe_sandbox_orders WHERE player_id=$1 AND request_id=$2",[id,body.data.requestId])).rows[0];
 if(existing)o=existing;
 else{const pending=(await db.query<Order>("SELECT * FROM stripe_sandbox_orders WHERE player_id=$1 AND status='pending' ORDER BY created_at DESC LIMIT 1",[id])).rows[0];
 if(pending){await db.query("COMMIT");return reply.code(409).send({error:"pending_checkout_exists",playerId:id,order:publicOrder(pending)});}
 const budget=await spending(id,db);
 const dailyBlocked=budget.dailyCents!==null&&budget.dailyCommittedCents+pack.amountCents>budget.dailyCents;
 const monthlyBlocked=budget.monthlyCents!==null&&budget.monthlyCommittedCents+pack.amountCents>budget.monthlyCents;
 if(dailyBlocked||monthlyBlocked){await db.query("ROLLBACK");return reply.code(409).send({error:"spending_limit_reached",playerId:id,period:dailyBlocked?"daily":"monthly",spending:budget});}
 o=(await db.query<Order>("INSERT INTO stripe_sandbox_orders(player_id,request_id,package_id,stones,amount_cents,currency) VALUES($1,$2,$3,$4,$5,'eur') RETURNING *",[id,body.data.requestId,pack.id,pack.stones,pack.amountCents])).rows[0]!;}
 await db.query("COMMIT");}catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 if(o.package_id!==pack.id)return reply.code(409).send({error:"request_id_conflict"});
 if(o.status!=="pending")return {playerId:id,order:publicOrder(o),checkoutUrl:null};
 try{
 const session=await getOrRecoverSession(provider,o);
 const verified=await fulfill(session);if(!verified)return reply.code(502).send({error:"checkout_mismatch"});
 const url=verified.status==="pending"&&session.status==="open"&&session.url&&new URL(session.url).protocol==="https:"&&new URL(session.url).hostname==="checkout.stripe.com"?session.url:null;
 return {playerId:id,order:publicOrder(verified),checkoutUrl:url};
 }catch{req.log.warn("Stripe sandbox checkout unavailable");return reply.code(502).send({error:"checkout_unavailable_retry_same_request"});}
 });
 app.post("/cancel",{config:{rateLimit:{max:10,timeWindow:"1 minute"}}},async(req,reply)=>{
 const id=await identity(req,reply);if(!id)return;if(!provider)return reply.code(503).send({error:"stripe_sandbox_not_configured"});
 const body=z.object({orderId:uuid}).strict().safeParse(req.body);if(!body.success)return reply.code(400).send({error:"invalid_order"});
 const o=(await pool.query<Order>("SELECT * FROM stripe_sandbox_orders WHERE id=$1 AND player_id=$2",[body.data.orderId,id])).rows[0];if(!o)return reply.code(404).send({error:"order_not_found"});
 if(o.status!=="pending")return {playerId:id,order:publicOrder(o)};
 try{
 // Recover a lost creation response with the same Stripe idempotency key.
 let session=await getOrRecoverSession(provider,o);
 if(session.status==="open"&&session.payment_status==="unpaid"){
 try{session=await provider.checkout.sessions.expire(session.id);}catch{session=await provider.checkout.sessions.retrieve(session.id,{expand:["payment_intent.latest_charge"]});}
 }
 // A completed checkout always wins a cancel/payment race. Never refund or debit here.
 const verified=await fulfill(session);if(!verified)return reply.code(502).send({error:"checkout_mismatch"});
 if(verified.status==="pending")return reply.code(409).send({error:"checkout_not_cancelled",playerId:id,order:publicOrder(verified)});
 return {playerId:id,order:publicOrder(verified)};
 }catch{return reply.code(502).send({error:"cancellation_unverified_retry"});}
 });
 app.post("/reconcile",{config:{rateLimit:{max:15,timeWindow:"1 minute"}}},async(req,reply)=>{
 const id=await identity(req,reply);if(!id)return;if(!provider)return reply.code(503).send({error:"stripe_sandbox_not_configured"});
 const body=z.object({orderId:uuid}).strict().safeParse(req.body);if(!body.success)return reply.code(400).send({error:"invalid_order"});
 const o=(await pool.query<Order>("SELECT * FROM stripe_sandbox_orders WHERE id=$1 AND player_id=$2",[body.data.orderId,id])).rows[0];if(!o)return reply.code(404).send({error:"order_not_found"});
 if(!["pending","credited","refund_review"].includes(o.status)||!o.session_id)return {playerId:id,order:publicOrder(o)};
 try{
 const s=await provider.checkout.sessions.retrieve(o.session_id,{expand:["payment_intent.latest_charge"]});
 const verified=await fulfill(s);if(!verified)return reply.code(502).send({error:"checkout_mismatch"});
 const charge=typeof s.payment_intent==="object"&&s.payment_intent?s.payment_intent.latest_charge:null;
 const pi=intentId(s);
 if(pi&&typeof charge==="object"&&charge&&(charge.refunded||charge.amount_refunded>0||charge.disputed)){
 await refundReview(pi,charge.amount_refunded,charge.disputed);
 }
 const updated=(await pool.query<Order>("SELECT * FROM stripe_sandbox_orders WHERE id=$1 AND player_id=$2",[o.id,id])).rows[0]!;
 return {playerId:id,order:publicOrder(updated)};
 }catch{return reply.code(502).send({error:"verification_unavailable"});}
 });
 app.get("/return",async(req,reply)=>{return reply.type("text/html; charset=utf-8").send("<!doctype html><html><head><title>Reverie sandbox</title></head><body><h1>Reverie test checkout</h1><p>Return to the game and refresh your Moonstone shop. A redirect is not proof of payment. No real money was charged.</p></body></html>");});
 // Scoped parser preserves the original body for Stripe's SDK signature check.
 await app.register(async hooks=>{
 hooks.removeContentTypeParser("application/json");hooks.addContentTypeParser("application/json",{parseAs:"buffer"},(_req,body,done)=>done(null,body));
 hooks.post("/webhook",{bodyLimit:1024*1024,config:{rateLimit:false}},async(req,reply)=>{
 if(!provider||!signingSecret)return reply.code(503).send({error:"stripe_sandbox_not_configured"});
 let event:Stripe.Event;try{event=provider.webhooks.constructEvent(req.body as Buffer,String(req.headers["stripe-signature"]??""),signingSecret);}catch{return reply.code(400).send({error:"invalid_signature"});}
 if(event.livemode)return reply.code(400).send({error:"live_events_disabled"});
 if(["checkout.session.completed","checkout.session.async_payment_succeeded","checkout.session.expired"].includes(event.type)){
 const received=event.data.object as Stripe.Checkout.Session;
 if(received.metadata?.order_id){const s=await provider.checkout.sessions.retrieve(received.id,{expand:["payment_intent.latest_charge"]});if(!await fulfill(s))return reply.code(409).send({error:"unmatched_order"});}
 }else if(event.type==="charge.refunded"){
 const charge=event.data.object;const pi=typeof charge.payment_intent==="string"?charge.payment_intent:charge.payment_intent?.id;if(pi)await refundReview(pi,charge.amount_refunded,!!charge.disputed);
 }else if(event.type==="charge.dispute.created"){
 const dispute=event.data.object;const pi=typeof dispute.payment_intent==="string"?dispute.payment_intent:dispute.payment_intent?.id;if(pi)await refundReview(pi,0,true);
 }
 return {received:true};
 });
 });
};}
export const shopRoutes:FastifyPluginAsync=async app=>{
 const secret=process.env.STRIPE_TEST_WEBHOOK_SECRET??"";
 return makeShopRoutes(configuredProvider(),/^whsec_[A-Za-z0-9_]+$/.test(secret)?secret:"")(app,{});
};
