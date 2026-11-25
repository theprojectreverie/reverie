export function clampAcknowledgement(previous:number, requested:number, latest:number):number {
  const safePrevious=Number.isSafeInteger(previous)?Math.max(0,previous):0;
  const safeLatest=Number.isSafeInteger(latest)?Math.max(0,latest):0;
  const safeRequested=Number.isSafeInteger(requested)?Math.max(0,requested):0;
  return Math.max(safePrevious,Math.min(safeRequested,safeLatest));
}
export function isReplayCursorValid(requested:number, latest:number):boolean {
  return Number.isSafeInteger(requested)&&requested>=0&&Number.isSafeInteger(latest)&&latest>=0&&requested<=latest;
}
