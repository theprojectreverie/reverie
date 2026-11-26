import {test} from "node:test";
import assert from "node:assert/strict";
import {guildPartyPower,guildPowerCompatible,GUILD_DUEL_REMATCH_MINUTES} from "../src/world/guild-duel-policy.js";
test("guild power uses saved health, attack, defense, speed and all party members",()=>{
 const unit={maxHp:100,atk:20,defense:10,speed:10};
 assert.equal(guildPartyPower([unit]),330);
 assert.equal(guildPartyPower([unit,unit]),660);
 assert.ok(guildPartyPower([{...unit,atk:30}])>guildPartyPower([unit]));
});
test("guild matchup bounds are symmetric, bounded and widen only after 90 seconds",()=>{
 assert.equal(guildPowerCompatible(100,150,0),true);
 assert.equal(guildPowerCompatible(150,100,0),true);
 assert.equal(guildPowerCompatible(100,151,89),false);
 assert.equal(guildPowerCompatible(100,200,90),true);
 assert.equal(guildPowerCompatible(100,201,1000),false);
 assert.equal(guildPowerCompatible(0,100,90),false);
 assert.equal(guildPowerCompatible(NaN,100,90),false);
 assert.equal(GUILD_DUEL_REMATCH_MINUTES,15);
});