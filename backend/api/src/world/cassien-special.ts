// Server-owned co-op thresholds; no client can choose damage or the target.
export function cassienSpecial(hp: number, targetId: string, now: number) {
 if (hp === 400) return {name: "Crimson Crescent", targetId, resolveAt: now + 1800, damage: 26};
 if (hp === 200) return {name: "Crimson Requiem", targetId, resolveAt: now + 2400, damage: 40};
 return null;
}
