import test from "node:test";
import assert from "node:assert/strict";
import {starterWalletStatus} from "../src/world/starter-wallet.js";
const empty=[{currency_id:"gold",balance:"0"},{currency_id:"crystals",balance:"0"}];
const receipt=(currency_id:string)=>({currency_id,idempotency_key:"starter-grant:"+currency_id,reason:"starter_grant"});
test("untouched zero wallet eligible; missing currencies or existing balances require review",()=>{
 assert.equal(starterWalletStatus(empty,[]),"eligible");
 assert.equal(starterWalletStatus(empty.slice(0,1),[]),"review");
 assert.equal(starterWalletStatus([{currency_id:"gold",balance:"1"},empty[1]!],[]),"review");
});
test("do not top up spent or manually funded wallets; complete grant is idempotent",()=>{
 assert.equal(starterWalletStatus(empty,[{currency_id:"gold",idempotency_key:null,reason:"manual_grant"}]),"review");
 assert.equal(starterWalletStatus(empty,[receipt("gold")]),"review");
 assert.equal(starterWalletStatus(empty,[receipt("gold"),receipt("crystals")]),"already_granted");
});