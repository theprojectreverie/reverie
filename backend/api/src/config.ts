import { z } from "zod";
const schema = z.object({
 NODE_ENV:z.enum(["development","test","production"]).default("development"),
 HOST:z.string().default("127.0.0.1"), PORT:z.coerce.number().int().min(1).max(65535).default(8787),
 DATABASE_URL:z.string().min(1), JWT_SECRET:z.string().min(32),
 ACCESS_TOKEN_TTL_SECONDS:z.coerce.number().int().min(60).max(3600).default(900),
 GAME_SERVER_BOOTSTRAP_SECRET:z.string().min(32).optional(),
 SERVER_INCIDENT_MONITOR_ENABLED:z.enum(["0","1"]).default("0"),
 WORLD_EVENT_RETENTION_ENABLED:z.enum(["0","1"]).default("0"),
 WORLD_POSITION_RETENTION_HOURS:z.coerce.number().int().min(24).max(720).default(720),
 DEVELOPER_ACCOUNT_IDS:z.string().default(""),
 STAFF_OWNER_ACCOUNT_IDS:z.string().default(""),
 COMPENSATION_ADMIN_ACCOUNT_IDS:z.string().default(""),
 CORS_ORIGIN:z.string().default("http://127.0.0.1:8060")
});
export const config=schema.parse(process.env);
export const localDevelopmentRegistration = config.NODE_ENV === "development" && config.HOST === "127.0.0.1";
