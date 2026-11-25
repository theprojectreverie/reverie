export class PlayerRealtimeLimits {
  private readonly connections = new Map<string, number>();
  private readonly windows = new Map<string, { startedAt: number; count: number }>();

  constructor(
    readonly maxConnections = 2,
    readonly maxMessagesPerSecond = 30,
  ) {
    if (!Number.isInteger(maxConnections) || maxConnections < 1) throw new RangeError("maxConnections must be positive");
    if (!Number.isInteger(maxMessagesPerSecond) || maxMessagesPerSecond < 1) throw new RangeError("maxMessagesPerSecond must be positive");
  }

  open(playerId: string): boolean {
    const count = this.connections.get(playerId) ?? 0;
    if (count >= this.maxConnections) return false;
    this.connections.set(playerId, count + 1);
    return true;
  }

  close(playerId: string): void {
    const remaining = Math.max(0, (this.connections.get(playerId) ?? 0) - 1);
    if (remaining === 0) {
      this.connections.delete(playerId);
      this.windows.delete(playerId);
    } else {
      this.connections.set(playerId, remaining);
    }
  }

  allowMessage(playerId: string, now: number): boolean {
    if (!Number.isFinite(now)) return false;
    const current = this.windows.get(playerId);
    if (!current || now - current.startedAt >= 1000 || now < current.startedAt) {
      this.windows.set(playerId, { startedAt: now, count: 1 });
      return true;
    }
    if (current.count >= this.maxMessagesPerSecond) return false;
    current.count++;
    return true;
  }

  connectionCount(playerId: string): number {
    return this.connections.get(playerId) ?? 0;
  }
}
