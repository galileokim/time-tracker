import { buildConfiguredApp } from "./app.js";
import { loadConfig } from "./config.js";

try {
  const config = loadConfig();
  const app = await buildConfiguredApp(config);

  await app.listen({ host: config.HOST, port: config.PORT });
} catch (error) {
  const message = error instanceof Error ? error.message : "Unknown startup error";
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
}
