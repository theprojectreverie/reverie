import {existsSync,mkdirSync,readFileSync,renameSync,statSync,unlinkSync,writeFileSync,openSync,closeSync,readdirSync} from "node:fs";
import {dirname,join,resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {createHash,randomUUID} from "node:crypto";
import {inflateSync} from "node:zlib";
export const contentDirectory=()=>resolve(process.env.REVERIE_LIVE_CONTENT_DIR||fileURLToPath(new URL("../../live-content/",import.meta.url)));
export function readDocument(path:string):unknown{try{if(statSync(path).size>262144)throw Error("manifest_too_large");return JSON.parse(readFileSync(path,"utf8"));}catch(e){if((e as NodeJS.ErrnoException).code==="ENOENT")return undefined;throw e;}}
export function withPublishLock<T>(path:string,fn:()=>T):T{
 mkdirSync(dirname(path),{recursive:true});const lock=path+".lock";let fd:number;try{fd=openSync(lock,"wx");}catch(e){if((e as NodeJS.ErrnoException).code==="EEXIST")throw Error("publish_busy");throw e;}try{return fn();}finally{closeSync(fd);unlinkSync(lock);}
}
export function atomicDocument(path:string,value:unknown){const bytes=Buffer.from(JSON.stringify(value,null,2)+"\n");if(bytes.length>262144)throw Error("manifest_too_large");const tmp=path+"."+randomUUID()+".tmp";try{writeFileSync(tmp,bytes,{flag:"wx"});renameSync(tmp,path);}finally{if(existsSync(tmp))unlinkSync(tmp);}}
export const digest=(bytes:Buffer)=>createHash("sha256").update(bytes).digest("hex");
const signature=Buffer.from([137,80,78,71,13,10,26,10]);
function crc32(b:Buffer){let crc=0xffffffff;for(const n of b){crc^=n;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}return (crc^0xffffffff)>>>0;}
// Only non-interlaced 8-bit RGB/RGBA PNG, bounded compressed and decoded size.
// Drop all ancillary metadata (including embedded text/profiles) from the stored file.
export function canonicalArtwork(bytes:Buffer):Buffer{
 if(bytes.length<45||bytes.length>1048576||!bytes.subarray(0,8).equals(signature))throw Error("invalid_png");let pos=8,w=0,h=0,channels=0,ended=false,seenData=false,dataClosed=false;const chunks:Buffer[]=[signature],data:Buffer[]=[];
 while(pos+12<=bytes.length){const len=bytes.readUInt32BE(pos);if(len>1048576||pos+12+len>bytes.length)throw Error("invalid_png");const type=bytes.toString("ascii",pos+4,pos+8),body=bytes.subarray(pos+8,pos+8+len),chunk=bytes.subarray(pos,pos+12+len);if(crc32(bytes.subarray(pos+4,pos+8+len))!==bytes.readUInt32BE(pos+8+len))throw Error("invalid_png_crc");
  if(!w&&type!=="IHDR")throw Error("invalid_png_header");
  if(type==="IHDR"){if(w||len!==13)throw Error("invalid_png_header");w=body.readUInt32BE(0);h=body.readUInt32BE(4);channels=body[9]===2?3:body[9]===6?4:0;if(w<1||h<1||w>1024||h>1024||body[8]!==8||!channels||body[10]!==0||body[11]!==0||body[12]!==0)throw Error("unsupported_png_format");chunks.push(chunk);}
  else if(type==="IDAT"){if(dataClosed)throw Error("invalid_png_order");seenData=true;data.push(body);chunks.push(chunk);}
  else if(type==="IEND"){if(len||!seenData||pos+12!==bytes.length)throw Error("invalid_png_end");chunks.push(chunk);ended=true;break;}
  else{if(!/^[a-z][A-Za-z]{3}$/.test(type))throw Error("unsupported_png_chunk");if(seenData)dataClosed=true;}
  pos+=12+len;
 }
 if(!ended)throw Error("invalid_png_end");const stride=w*channels+1,raw=inflateSync(Buffer.concat(data),{maxOutputLength:stride*h});if(raw.length!==stride*h)throw Error("invalid_png_pixels");for(let y=0;y<h;y++)if(raw[y*stride]!>4)throw Error("invalid_png_filter");return Buffer.concat(chunks);
}
const artDirectory=()=>join(contentDirectory(),"artwork");
export function artworkPath(hash:string){if(!/^[a-f0-9]{64}$/.test(hash))throw Error("invalid_artwork_id");return join(artDirectory(),hash+".png");}
export function readArtwork(hash:string){const path=artworkPath(hash);if(statSync(path).size>1048576)throw Error("artwork_too_large");const bytes=readFileSync(path);if(digest(bytes)!==hash)throw Error("artwork_hash_mismatch");return bytes;}
export function storeArtwork(input:Buffer){const bytes=canonicalArtwork(input),hash=digest(bytes),path=artworkPath(hash);return withPublishLock(join(artDirectory(),"upload"),()=>{if(existsSync(path)){readArtwork(hash);return hash;}const files=readdirSync(artDirectory()).filter(f=>/^[a-f0-9]{64}\.png$/.test(f));if(files.length>=100||files.reduce((n,f)=>n+statSync(join(artDirectory(),f)).size,0)+bytes.length>64*1024*1024)throw Error("artwork_storage_limit");writeFileSync(path,bytes,{flag:"wx"});return hash;});}
