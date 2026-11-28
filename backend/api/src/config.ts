import { z } from "zod";
const schema = z.object({
 NODE_ENV:z.enum(["development","test","production"]).default("development"),
 HOST:z.string().default("127.0.0.1"), PORT:z.coerce.number().int().min(1).max(65535).default(8787),
 DATABASE_URL:z.string().min(1), JWT_SECRET:z.string().min(32),
 ACCESS_TOKEN_TTL_SECONDS:z.coerce.number().int().min(60).max(3600).default(900),
 GAME_SERVER_BOOTSTRAP_SECRET:z.string().min(32).optional(),
 TRUST_LOCAL_REVERSE_PROXY:z.enum(["0","1"]).default("0"),
 SHARED_RATE_LIMIT_NAMESPACE:z.string().regex(/^[a-zA-Z0-9_-]{1,48}$/).optional(),
 BACKUP_HEALTH_REPORT_PATH:z.string().min(1).optional(),
 OPERATIONAL_HISTORY_INSTANCE_ID:z.string().regex(/^[a-zA-Z0-9_-]{1,48}$/).optional(),
 REVERIE_STORY_WORKER_CONCURRENCY:z.coerce.number().int().min(1).max(2).default(2),
 REVERIE_ALPHA_REGISTRATION_MODE:z.enum(["invite","open"]).default("invite"),
 REVERIE_ALPHA_SIGNUPS_ENABLED:z.enum(["0","1"]).default("1"),
 PUBLIC_ALPHA_MONITOR_ENABLED:z.enum(["0","1"]).default("0"),
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
