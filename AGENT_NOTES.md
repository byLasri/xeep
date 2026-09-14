# Agent Notes (for AI assistant memory refresh)

## Codespace Access
- Codespace name will be stored INSIDE the codespace at `/home/codespace/.agent_state.json`
- To reconnect: ask user for fresh token, then list codespaces via API:
  `GET /user/codespaces` -> find the one for repo `byLasri/xeep`
- Bridge server runs on port 8080 inside the codespace
- Bridge URL format: `https://<codespace-name>-8080.app.github.dev`
- Shared secret is stored in `/home/codespace/.agent_state.json`

## Recovery Protocol
1. Get fresh token from user
2. `GET https://api.github.com/user/codespaces` (with token)
3. Find codespace with `repository.full_name == "byLasri/xeep"`
4. If not running, `POST /user/codespaces/{name}/start`
5. Read `/home/codespace/.agent_state.json` via bridge or exec API
6. Resume control using bridge URL + shared secret

## Project
- TypeScript Cloudflare Worker proxy: DeepSeek SSE -> OpenAI chat completions
- Dev command: `npx wrangler dev`
- Deploy: `npx wrangler deploy`
