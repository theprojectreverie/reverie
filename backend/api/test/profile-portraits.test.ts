import test from "node:test";
import assert from "node:assert/strict";
test("profile portraits respect rarity ownership and full Mythic ascension", async () => {
 process.env.NODE_ENV="test";
 process.env.DATABASE_URL="postgresql://unused:unused@127.0.0.1:1/unused";
 process.env.JWT_SECRET="isolated-portrait-test-secret-at-least-32-characters";
 const {profilePortraitUnlocks,profilePicture,PROFILE_PICTURES}=await import("../src/routes/social.js");
 const {pool}=await import("../src/db.js");
 try {
  for(const name of ["ravienna","gerald","lilith","cassien"]){
   const legend=name==="ravienna"?name:name+"_legendary";
   const mythic=name+"_mythic";
   for(const tier of ["legendary","mythic","ascended","human"]){
    const id=name+"_"+tier;
    assert.ok(PROFILE_PICTURES.includes(id as any));
    assert.equal(profilePicture(id),id);
    assert.ok(!profilePortraitUnlocks([]).includes(id));
   }
   const l=profilePortraitUnlocks([{char_id:legend,ascension:3}]);
   assert.ok(l.includes(name+"_legendary")&&l.includes(name+"_human"));
   assert.ok(!l.includes(mythic)&&!l.includes(name+"_ascended"));
   for(let a=0;a<=3;a++){
    const m=profilePortraitUnlocks([{char_id:mythic,ascension:a}]);
    assert.ok(m.includes(mythic)&&m.includes(name+"_human"));
    assert.equal(m.includes(name+"_ascended"),a===3);
   }
   assert.ok(!profilePortraitUnlocks([],[mythic]).includes(name+"_ascended"));
  }
  assert.equal(PROFILE_PICTURES.length,17);
  assert.deepEqual(profilePortraitUnlocks([]),["kael_avatar"]);
  for(const old of ["gerald","lilith","ravienna","cassien","nyx","kael_mythic","elathra"]) {
   assert.equal(profilePicture(old),"kael_avatar");
   assert.ok(!PROFILE_PICTURES.includes(old as any));
  }
  assert.equal(profilePicture("forged_ascended"),"kael_avatar");
 } finally {await pool.end();}
});
