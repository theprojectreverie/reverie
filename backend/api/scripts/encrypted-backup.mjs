import {createCipheriv,createDecipheriv,randomBytes} from "node:crypto";
import {createReadStream,createWriteStream} from "node:fs";
import {open,link,unlink,stat,readdir} from "node:fs/promises";
import {pipeline} from "node:stream/promises";
import {Writable,Transform} from "node:stream";
import {join} from "node:path";
const magic=Buffer.from("REVBAK01"),headerSize=20,tagSize=16;
export function parseBackupKey(hex){
 if(typeof hex!=="string"||!/^[0-9a-fA-F]{64}$/.test(hex))throw Error("Backup key must be 32 random bytes in hex");
 return Buffer.from(hex,"hex");
}
// Create a new archive atomically. Never replace an existing backup.
export async function encryptArchive(input,destination,key,checkSource=async()=>{}){
 const temp=destination+".partial-"+randomBytes(8).toString("hex");
 const header=Buffer.concat([magic,randomBytes(12)]);
 const cipher=createCipheriv("aes-256-gcm",key,header.subarray(8));cipher.setAAD(header);
 const h=await open(temp,"wx",0o600);try{await h.writeFile(header);}finally{await h.close();}
 try{
  await pipeline(input,cipher,createWriteStream(temp,{flags:"a"}));
  await checkSource();
  const append=await open(temp,"a");try{await append.writeFile(cipher.getAuthTag());await append.sync();}finally{await append.close();}
  await verifyArchive(temp,key);
  await link(temp,destination);
 }finally{await unlink(temp).catch(()=>{});}
}
export async function verifyArchive(file,key,output){
 const size=(await stat(file)).size;
 if(size<headerSize+tagSize+1)throw Error("Truncated archive");
 const h=await open(file,"r");const header=Buffer.alloc(headerSize),tag=Buffer.alloc(tagSize);
 try{await h.read(header,0,header.length,0);await h.read(tag,0,tag.length,size-tagSize);}finally{await h.close();}
 if(!header.subarray(0,8).equals(magic))throw Error("Unknown archive format");
 const decipher=createDecipheriv("aes-256-gcm",key,header.subarray(8));decipher.setAAD(header);decipher.setAuthTag(tag);
 // Output must be treated as untrusted until this promise resolves. Restore
 // into a private temporary file, then authenticate before invoking pg_restore.
 await pipeline(createReadStream(file,{start:headerSize,end:size-tagSize-1}),decipher,output??new Writable({write(_b,_e,cb){cb()}}));
}
export async function rotationCandidates(dir,{keep=7,days=30,now=Date.now()}={}){
 if(!Number.isInteger(keep)||keep<7||!Number.isInteger(days)||days<30)throw Error("Unsafe retention bounds");
 const files=[];
 for(const entry of await readdir(dir,{withFileTypes:true})){
  if(!entry.isFile()||!/^reverie-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{12}\.rvbak$/.test(entry.name))continue;
  const file=join(dir,entry.name),info=await stat(file);
  files.push({name:entry.name,file,mtime:info.mtimeMs});
 }
 files.sort((a,b)=>b.name.localeCompare(a.name));
 return files.slice(keep).filter(f=>f.mtime<now-days*86400000).map(f=>f.name);
}
