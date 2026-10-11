import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import WebSocket from '/Users/macos/.npm/_npx/b86ed90107c62dab/node_modules/ws/wrapper.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const CONFIG_PATH = path.join(__dirname, 'config.json');

const DSH_API_BASE = process.env.DSH_WEB_URL || 'http://127.0.0.1:3080';
const DSH_WS_URL = DSH_API_BASE.replace(/^http/, 'ws') + '/api/remote.mux';
const WORKSPACE_CWD = process.env.PWD || '/Users/macos/Documents/DSH Workspace/Caraoke App';
const CURRENT_SESSION_ID = process.env.DSH_SESSION_ID || 'session-96c846ce-c673-4635-8831-7f4f78a2b0f7';

if (!fs.existsSync(CONFIG_PATH)) {
  const template = {
    bot_token: "YOUR_TELEGRAM_BOT_TOKEN_FROM_BOTFATHER",
    allowed_chat_id: 0,
    session_id: CURRENT_SESSION_ID
  };
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(template, null, 2));
  console.log(`[Bridge] Created template at ${CONFIG_PATH}. Please populate bot_token.`);
  process.exit(1);
}

const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
config.allowed_chat_id = Number(process.env.TELEGRAM_ALLOWED_CHAT_ID) || config.allowed_chat_id;

if (!config.bot_token || config.bot_token.includes('YOUR_TELEGRAM_BOT_TOKEN')) {
  console.error('[Bridge] Error: bot_token is not configured in config.json');
  process.exit(1);
}

if (!config.allowed_chat_id) {
  console.error('[Bridge] Error: allowed_chat_id must be configured in config.json or TELEGRAM_ALLOWED_CHAT_ID');
  process.exit(1);
}

const TELEGRAM_API = `https://api.telegram.org/bot${config.bot_token}`;

let turnCount = 0;
const MAX_TURNS_PER_SESSION = 10;

function getDshCookie(authority = '127.0.0.1:3080') {
  try {
    const credPath = path.join(process.env.DSH_HOME || path.join(process.env.HOME, '.dsh'), '.credentials.yaml');
    const yaml = fs.readFileSync(credPath, 'utf8');
    const match = yaml.match(/client-connection\/browser-session:[\s\S]*?secret:\s*([^\s]+)/);
    if (!match) return '';
    const secretBase64Url = match[1];
    const padding = '='.repeat((4 - secretBase64Url.length % 4) % 4);
    const secret = Buffer.from(secretBase64Url.replaceAll('-', '+').replaceAll('_', '/') + padding, 'base64');
    const cookieName = 'dsh-auth-' + crypto.createHash('sha256').update(authority).digest('base64url');
    const issuedAt = Date.now();
    const expiresAt = issuedAt + 7 * 24 * 60 * 60 * 1000;
    const payload = { version: 1, authority, issuedAt, expiresAt };
    const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
    const sig = crypto.createHmac('sha256', secret).update(body).digest('base64url');
    return `${cookieName}=v1.${body}.${sig}`;
  } catch (err) {
    console.error('[Bridge] Failed to compute DSH auth cookie:', err.message);
    return '';
  }
}

async function createFreshSession() {
  try {
    const authority = new URL(DSH_API_BASE).host;
    const cookie = getDshCookie(authority);
    const payload = {
      type: 'client-request',
      rpcId: crypto.randomUUID(),
      method: 'session/create',
      payload: {
        args: {
          request: {
            cwd: WORKSPACE_CWD
          }
        }
      }
    };

    const res = await fetch(`${DSH_API_BASE}/api/session/create`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Cookie': cookie,
        'Host': authority,
        'Origin': `http://${authority}`
      },
      body: JSON.stringify(payload)
    });

    const data = await res.json();
    if (data.result?.ok && data.result.value?.sessionId) {
      const newId = data.result.value.sessionId;
      config.session_id = newId;
      fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
      turnCount = 0;
      console.log(`[Bridge] Switched to fresh session: ${newId}`);
      subscribeToSession(newId);
      return newId;
    }
  } catch (err) {
    console.error('[Bridge] Failed to create fresh session:', err.message);
  }
  return null;
}

async function tgCall(method, body) {
  try {
    const res = await fetch(`${TELEGRAM_API}/${method}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
    return await res.json();
  } catch (err) {
    console.error(`[Telegram] ${method} error:`, err.message);
    return null;
  }
}

async function sendTelegramMessage(chatId, text) {
  if (!chatId || !text) return;
  const MAX_LEN = 4000;
  for (let i = 0; i < text.length; i += MAX_LEN) {
    const chunk = text.slice(i, i + MAX_LEN);
    // ponytail: Plaintext fallback on error. Add Telegram MarkdownV2 escape helper if markdown fidelity needed.
    const res = await tgCall('sendMessage', {
      chat_id: chatId,
      text: chunk,
      parse_mode: 'Markdown'
    });
    if (!res?.ok) {
      await tgCall('sendMessage', { chat_id: chatId, text: chunk });
    }
  }
}

async function postPromptToDSH(promptText) {
  const sessionId = config.session_id || CURRENT_SESSION_ID;
  const authority = new URL(DSH_API_BASE).host;
  const cookie = getDshCookie(authority);
  const payload = {
    type: 'client-request',
    rpcId: crypto.randomUUID(),
    method: 'session/prompt',
    payload: {
      args: {
        request: {
          requestId: crypto.randomUUID(),
          sessionId,
          mode: 'queue',
          content: [{ type: 'text', text: promptText }]
        }
      }
    }
  };

  const res = await fetch(`${DSH_API_BASE}/api/session/prompt`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Cookie': cookie,
      'Host': authority,
      'Origin': `http://${authority}`
    },
    body: JSON.stringify(payload)
  });

  return await res.json();
}

// WebSocket listener for DSH assistant responses
let ws = null;
let currentFollowStreamId = null;
let snapshotLoaded = false;
let currentResponseBlocks = [];
let isGenerating = false;

function subscribeToSession(targetSession) {
  if (!ws || ws.readyState !== WebSocket.OPEN) return;

  if (currentFollowStreamId) {
    try {
      ws.send(JSON.stringify({ type: 'cancel', streamId: currentFollowStreamId }));
    } catch {}
  }

  currentFollowStreamId = `follow-${targetSession}-${Date.now()}`;
  snapshotLoaded = false;
  currentResponseBlocks = [];

  ws.send(JSON.stringify({
    type: 'open',
    streamId: currentFollowStreamId,
    endpoint: 'session/follow',
    payload: {
      args: {
        request: {
          address: {
            kind: 'session',
            sessionId: targetSession
          }
        }
      }
    }
  }));

  console.log(`[DSH WS] Subscribed to follow session: ${targetSession}`);
}

function connectDshEvents() {
  const authority = new URL(DSH_API_BASE).host;
  const cookie = getDshCookie(authority);

  ws = new WebSocket(DSH_WS_URL, {
    headers: {
      'Cookie': cookie,
      'Host': authority,
      'Origin': `http://${authority}`
    }
  });

  ws.on('open', () => {
    console.log('[DSH WS] Connected to events downlink.');
    subscribeToSession(config.session_id || CURRENT_SESSION_ID);
  });

  ws.on('message', async (data) => {
    try {
      const msg = JSON.parse(data.toString());
      if (msg.type !== 'item' || !msg.value) return;

      const item = msg.value;

      if (item.type === 'snapshot') {
        snapshotLoaded = true;
        console.log(`[DSH WS] Snapshot received (cursor: ${item.cursor}). Listening for live events.`);
        return;
      }

      if (!snapshotLoaded) return;

      if (item.type === 'event' && item.event) {
        const event = item.event;

        if (event.type === 'turn/start') {
          isGenerating = true;
          currentResponseBlocks = [];
        } else if (event.type === 'assistant/message') {
          const content = event.data?.message?.content || [];
          for (const block of content) {
            if (block.type === 'text' && block.text) {
              currentResponseBlocks.push(block.text);
            }
          }
        } else if (event.type === 'turn/end') {
          isGenerating = false;
          if (currentResponseBlocks.length > 0 && config.allowed_chat_id) {
            const fullReply = currentResponseBlocks.join('\n\n').trim();
            if (fullReply) {
              await sendTelegramMessage(config.allowed_chat_id, `🤖 *Josh:*\n\n${fullReply}`);
            }
            currentResponseBlocks = [];
            turnCount++;

            if (turnCount >= MAX_TURNS_PER_SESSION) {
              console.log(`[Bridge] Turn limit reached (${turnCount}/${MAX_TURNS_PER_SESSION}). Cycling session...`);
              const newSessionId = await createFreshSession();
              if (newSessionId) {
                await sendTelegramMessage(
                  config.allowed_chat_id,
                  `🔄 *Context refreshed automatically.*\nFresh session created. Ready!`
                );
              }
            }
          }
        } else if (event.type === 'approval/requested') {
          if (config.allowed_chat_id) {
            const data = event.data || {};
            const tool = data.toolName || data.tool || 'Unknown Tool';
            const reason = data.reason || 'Approval required';
            await sendTelegramMessage(config.allowed_chat_id, `⚠️ *Approval Required*\nTool: \`${tool}\`\nReason: ${reason}\nApprove via DSH Web GUI.`);
          }
        }
      }
    } catch (err) {
      console.error('[DSH WS] Event parse error:', err.message);
    }
  });

  ws.on('close', () => {
    console.log('[DSH WS] Disconnected. Reconnecting in 3s...');
    setTimeout(connectDshEvents, 3000);
  });

  ws.on('error', (err) => {
    console.error('[DSH WS] Error:', err.message);
    ws.close();
  });
}

// Long-polling loop for Telegram incoming updates
let pollOffset = 0;

async function pollTelegram() {
  while (true) {
    try {
      const updates = await tgCall('getUpdates', {
        offset: pollOffset,
        timeout: 20
      });

      if (updates && updates.ok && Array.isArray(updates.result)) {
        for (const update of updates.result) {
          pollOffset = update.update_id + 1;
          const msg = update.message;
          if (!msg || !msg.text) continue;

          const fromChatId = msg.chat.id;

          // Strict whitelist check
          if (fromChatId !== config.allowed_chat_id) {
            console.warn(`[Security] Ignored message from unauthorized chat: ${fromChatId}`);
            continue;
          }

          const text = msg.text.trim();

          if (text === '/start') {
            await sendTelegramMessage(fromChatId, `👋 *Josh online.*\nReady for commands. Send any task or message.`);
            continue;
          }

          if (text === '/status') {
            const statusMsg = `📊 *Josh Status*\nSession: \`${config.session_id || CURRENT_SESSION_ID}\`\nTurns: ${turnCount}/${MAX_TURNS_PER_SESSION}`;
            await sendTelegramMessage(fromChatId, statusMsg);
            continue;
          }

          if (text === '/newsession' || text === '/reset') {
            const newSessionId = await createFreshSession();
            if (newSessionId) {
              await sendTelegramMessage(fromChatId, `🔄 *Fresh Session Spawned:*\n\`${newSessionId}\`\nReady!`);
            } else {
              await sendTelegramMessage(fromChatId, `❌ Failed to create fresh session.`);
            }
            continue;
          }

          // Forward user command to DSH session
          console.log(`[Telegram -> DSH] Received: ${text.slice(0, 50)}...`);
          await sendTelegramMessage(fromChatId, `⏳ *Josh:* Working on it...`);
          await postPromptToDSH(text);
        }
      }
    } catch (err) {
      console.error('[Polling] Error:', err.message);
      await new Promise((r) => setTimeout(r, 5000));
    }
  }
}

// Start bridge
console.log('[Bridge] Starting Telegram Bridge (Josh)...');
connectDshEvents();
pollTelegram();
