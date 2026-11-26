import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import {mkdtemp,writeFile,readFile,utimes,rm,readdir} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {Readable} from "node:stream";
import {encryptArchive,verifyArchive,rotationCandidates,parseBackupKey} from "./encrypted-backup.mjs";
const dir=await mkdtemp(join(tmpdir(),"reverie-encryption-qa-"));
const key=randomBytes(32),data=randomBytes(1024*1024),file=join(dir,"fixture.rvbak");
try{
 assert.deepEqual(parseBackupKey(key.toString("hex")),key);assert.throws(()=>parseBackupKey("short"));
 await encryptArchive(Readable.from([data]),file,key);
 const original=await readFile(file);
 assert.ok(!original.includes(data.subarray(0,64)));
 await assert.rejects(encryptArchive(Readable.from([data]),file,key));
 assert.deepEqual(await readFile(file),original);
 const tampered=Buffer.from(original);tampered[100]^=1;await writeFile(join(dir,"tampered"),tampered);
 await assert.rejects(verifyArchive(join(dir,"tampered"),key));
 await assert.rejects(verifyArchive(file,randomBytes(32)));
 const failed=join(dir,"failed.rvbak");
 await assert.rejects(encryptArchive(Readable.from([data]),failed,key,async()=>{throw Error("failed dump")}));
 assert.ok(!(await readdir(dir)).some(n=>n==="failed.rvbak"||n.includes(".partial-")));
 const now=Date.now(),old=new Date(now-40*86400000);
 for(let i=1;i<=9;i++){
  const name="reverie-202601"+String(i).padStart(2,"0")+"T000000Z-abcdef123456.rvbak",path=join(dir,name);
  await writeFile(path,"synthetic retention fixture");await utimes(path,old,old);
 }
 await writeFile(join(dir,"unrelated.txt"),"leave alone");
 const planned=await rotationCandidates(dir,{now});
 assert.deepEqual(planned,["reverie-20260102T000000Z-abcdef123456.rvbak","reverie-20260101T000000Z-abcdef123456.rvbak"]);
 await assert.rejects(rotationCandidates(dir,{keep:1}));
 assert.ok((await readdir(dir)).includes(planned[0]));
 console.log("PASS AES-GCM, tamper rejection, wrong-key rejection, atomic non-overwrite, failed dump cleanup and review-only retention");
}finally{await rm(dir,{recursive:true,force:true});}
