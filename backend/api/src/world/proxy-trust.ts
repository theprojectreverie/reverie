// Only trust the immediate local reverse proxy, never arbitrary forwarded hops.
export function trustLocalProxy(address:string,hop:number){
 return hop===0&&["127.0.0.1","::1","::ffff:127.0.0.1"].includes(address);
}
