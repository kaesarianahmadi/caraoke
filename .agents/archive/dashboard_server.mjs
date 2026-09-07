import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { buildFeedbackPrompt } from './staff_contract.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = 3088;
const DSH_API_BASE = 'http://127.0.0.1:3080';
const CARAOKE_WORKSPACE_ID = '1c1b9bf4-4b21-4761-babc-47f11612b4de';
const TELEGRAM_CONFIG_PATH = path.join(__dirname, 'telegram-bridge/config.json');
const DASHBOARD_JSON_PATH = path.join(__dirname, 'dashboard.json');

const server = http.createServer(async (req, res) => {
  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const pathname = url.pathname;

  // Handle Feedback Submission
  if (req.method === 'POST' && pathname === '/api/feedback') {
    let bodyText = '';
    req.on('data', chunk => { bodyText += chunk; });
    req.on('end', async () => {
      try {
        const body = JSON.parse(bodyText);
        const feedback = (body.feedback || '').trim();
        const build = body.build || 24;

        if (!feedback) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: false, error: 'Feedback text is required' }));
          return;
        }

        console.log(`[Dashboard] Incoming feedback for Build ${build}: "${feedback.slice(0, 50)}..."`);

        // 1. Create fresh session inside Caraeoke App workspace
        const createPayload = {
          type: 'client-request',
          rpcId: crypto.randomUUID(),
          method: 'session.create',
          payload: {
            workspaceId: CARAOKE_WORKSPACE_ID
          }
        };

        const createRes = await fetch(`${DSH_API_BASE}/api/session.create`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(createPayload)
        });

        const createData = await createRes.json();
        const newSessionId = createData.result?.value?.sessionId;

        if (!newSessionId) {
          throw new Error('Failed to create session in Caraeoke workspace: ' + JSON.stringify(createData));
        }

        console.log(`[Dashboard] Spawned fresh session in Caraeoke App workspace: ${newSessionId}`);

        // 1b. Pin Josh's model: 9router / 3.8-flash-ag (MANDATORY: every new
        // dashboard session must run Josh on 3.8 flash, never harness default combo/ultra).
        const selectPayload = {
          type: 'client-request',
          rpcId: crypto.randomUUID(),
          method: 'session.selectModel',
          payload: {
            sessionId: newSessionId,
            provider: 'router9',
            model: '3.8-flash-ag'
          }
        };

        const selectRes = await fetch(`${DSH_API_BASE}/api/session.selectModel`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(selectPayload)
        });

        const selectData = await selectRes.json();
        if (!selectData?.result?.ok) {
          throw new Error('Failed to pin model router9/3.8-flash-ag on session: ' + JSON.stringify(selectData));
        }
        console.log(`[Dashboard] Pinned session ${newSessionId} to router9/3.8-flash-ag (3.8 flash)`);

        // 2. Update Telegram bridge to follow new session
        if (fs.existsSync(TELEGRAM_CONFIG_PATH)) {
          const tgConfig = JSON.parse(fs.readFileSync(TELEGRAM_CONFIG_PATH, 'utf8'));
          tgConfig.session_id = newSessionId;
          fs.writeFileSync(TELEGRAM_CONFIG_PATH, JSON.stringify(tgConfig, null, 2));

          // Notify on Telegram
          if (tgConfig.bot_token && tgConfig.allowed_chat_id) {
            fetch(`https://api.telegram.org/bot${tgConfig.bot_token}/sendMessage`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                chat_id: tgConfig.allowed_chat_id,
                text: `📋 *Feedback Received for Build ${build} via Dashboard*\n\n"${feedback.slice(0, 200)}..."\n\n🔄 *Fresh session created in Caraoke App workspace:* \`${newSessionId}\`\nTokens reset to ~4,000. Identity lock injected: Josh answers alone, dispatches Axel/Vance/Ward via 9router as his first action, applies their code, verifies CI, reports once.`
              })
            }).catch(() => {});
          }
        }

        // 3. Update dashboard state
        if (fs.existsSync(DASHBOARD_JSON_PATH)) {
          const dash = JSON.parse(fs.readFileSync(DASHBOARD_JSON_PATH, 'utf8'));
          dash.updated_at = new Date().toISOString();
          dash.build = build;
          dash.chief = {
            name: 'Josh',
            role: 'Chief of Staff & Orchestrator',
            model: 'router9/3.8-flash-ag',
            status: 'planning',
            current_action: `Formulating task delegation plan for Build ${build} feedback`
          };
          for (const k of Object.keys(dash.workers || {})) {
            dash.workers[k].status = 'queued';
            dash.workers[k].current_task = 'Awaiting task dispatch from Chief';
          }
          fs.writeFileSync(DASHBOARD_JSON_PATH, JSON.stringify(dash, null, 2));
        }

        // 4. Prompt the fresh session with mandatory delegation instructions
        const promptPayload = {
          type: 'client-request',
          rpcId: crypto.randomUUID(),
          method: 'session.prompt',
          payload: {
            sessionId: newSessionId,
            mode: 'queue',
            content: [
              {
                type: 'text',
                text: buildFeedbackPrompt(build, feedback)
              }
            ]
          }
        };

        await fetch(`${DSH_API_BASE}/api/session.prompt`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(promptPayload)
        });

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          ok: true,
          sessionId: newSessionId,
          message: `Spawned fresh session in Caraoke workspace with ~4,000 tokens. Josh is planning delegation.`
        }));

      } catch (err) {
        console.error('[Dashboard API Error]:', err.message);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: err.message }));
      }
    });
    return;
  }

  // Static File Serving
  let filePath = pathname === '/' || pathname === '/dashboard' ? '/dashboard.html' : pathname;
  const fullPath = path.join(__dirname, filePath);

  if (fs.existsSync(fullPath) && fs.statSync(fullPath).isFile()) {
    const ext = path.extname(fullPath);
    const mimeTypes = {
      '.html': 'text/html',
      '.json': 'application/json',
      '.css': 'text/css',
      '.js': 'text/javascript',
      '.svg': 'image/svg+xml',
      '.png': 'image/png'
    };
    res.writeHead(200, {
      'Content-Type': mimeTypes[ext] || 'text/plain',
      'Cache-Control': 'no-cache'
    });
    res.end(fs.readFileSync(fullPath));
  } else {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not found');
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[Dashboard Server] Live at http://127.0.0.1:${PORT}`);
});
