import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import WebSocket from '/Users/macos/.npm/_npx/1e7f6d9597241db0/node_modules/ws/wrapper.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const CONFIG_PATH = path.join(__dirname, 'config.json');

const DSH_API_BASE = process.env.DSH_WEB_URL || 'http://127.0.0.1:3080';
const DSH_WS_URL = DSH_API_BASE.replace(/^http/, 'ws') + '/api/events.mux';
const WORKSPACE_CWD = '/Users/macos/Documents/DSH Workspace/Caraeoke App';
const CURRENT_SESSION_ID = process.env.DSH_SESSION_ID || 'session-211d5028-a977-44ab-a502-413f418f458a';

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

if (!config.bot_token || config.bot_token.includes('YOUR_TELEGRAM_BOT_TOKEN')) {
  console.error('[Bridge] Error: bot_token is not configured in config.json');
  process.exit(1);
}

const TELEGRAM_API = `https://api.telegram.org/bot${config.bot_token}`;

let turnCount = 0;
const MAX_TURNS_PER_SESSION = 8; // Automatically cycle after 8 turns to keep tokens < 30k

async function createFreshSession() {
  try {
    const payload = {
      type: 'client-request',
      rpcId: crypto.randomUUID(),
      method: 'session.create',
      payload: {
        cwd: WORKSPACE_CWD
      }
    };

    const res = await fetch(`${DSH_API_BASE}/api/session.create`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    const data = await res.json();
    if (data.result?.ok && data.result.value?.sessionId) {
      const newId = data.result.value.sessionId;
      config.session_id = newId;
      fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
      turnCount = 0;
      console.log(`[Bridge] Auto-cycled to fresh session: ${newId}`);
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
    await tgCall('sendMessage', {
      chat_id: chatId,
      text: chunk,
      parse_mode: 'Markdown'
    }).catch(async () => {
      // Fallback without parse_mode in case markdown is invalid
      await tgCall('sendMessage', { chat_id: chatId, text: chunk });
    });
  }
}

async function postPromptToDSH(promptText) {
  const sessionId = config.session_id || CURRENT_SESSION_ID;
  const payload = {
    type: 'client-request',
    rpcId: crypto.randomUUID(),
    method: 'session.prompt',
    payload: {
      sessionId,
      mode: 'queue',
      content: [{ type: 'text', text: promptText }]
    }
  };

  const res = await fetch(`${DSH_API_BASE}/api/session.prompt`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  });

  return await res.json();
}

// WebSocket listener for DSH assistant responses
let ws = null;
let currentResponseBlocks = [];
let isGenerating = false;

function connectDshEvents() {
  ws = new WebSocket(DSH_WS_URL);

  ws.on('open', () => {
    console.log('[DSH WS] Connected to events downlink.');
  });

  ws.on('message', async (data) => {
    try {
      const msg = JSON.parse(data.toString());
      if (msg.type !== 'server-request') return;

      const method = msg.method;
      const payload = msg.payload || {};
      const targetSession = config.session_id || CURRENT_SESSION_ID;

      if (method === 'session/event' && payload.sessionId === targetSession) {
        const event = payload.event;
        if (!event) return;

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
              await sendTelegramMessage(config.allowed_chat_id, `🤖 *Josh (Chief of Staff):*\n\n${fullReply}`);
            }
            currentResponseBlocks = [];
            turnCount++;

            // Check if turn count reached auto-refresh threshold
            if (turnCount >= MAX_TURNS_PER_SESSION) {
              console.log(`[Bridge] Turn limit reached (${turnCount}/${MAX_TURNS_PER_SESSION}). Cycling session to keep token cost minimal...`);
              const newSessionId = await createFreshSession();
              if (newSessionId) {
                await sendTelegramMessage(config.allowed_chat_id, `🔄 *Context window refreshed automatically.*\nInput tokens reset from bloated ~250k → 4k. Full memory & codebase state preserved. Ready!`);
              }
            }
          }
        }
      } else if (method === 'approval/requested' && payload.sessionId === targetSession) {
        if (config.allowed_chat_id) {
          const tool = payload.toolName || 'Unknown Tool';
          const reason = payload.reason || 'Approval required';
          await sendTelegramMessage(config.allowed_chat_id, `⚠️ *Approval Required*\nTool: \`${tool}\`\nReason: ${reason}\nApprove via DSH Web GUI.`);
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

          // Auto-pair if chat_id is not yet locked
          if (!config.allowed_chat_id || config.allowed_chat_id === 0) {
            config.allowed_chat_id = fromChatId;
            fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
            await sendTelegramMessage(fromChatId, `✅ *Josh Connected*\nAuthorized Chat ID locked: \`${fromChatId}\`\nYou are now speaking directly with Chief of Staff.`);
            continue;
          }

          // Strict whitelist check
          if (fromChatId !== config.allowed_chat_id) {
            console.warn(`[Security] Ignored message from unauthorized chat: ${fromChatId}`);
            continue;
          }

          const text = msg.text.trim();

          if (text === '/start') {
            await sendTelegramMessage(fromChatId, `👋 *Josh (Chief of Staff) online.*\nReady for commands. Send any task or message.`);
            continue;
          }

          if (text === '/status' || text === '/dashboard') {
            try {
              const dash = JSON.parse(fs.readFileSync(path.join(__dirname, '../dashboard.json'), 'utf8'));
              let msg = `📊 *Caraoke Staff Dashboard*\n\n`;
              for (const [k, w] of Object.entries(dash.workers)) {
                msg += `👤 *${w.name}* (${w.status.toUpperCase()})\nTask: ${w.current_task}\n\n`;
              }
              msg += `⚡ *In Progress:*\n${dash.in_progress ? dash.in_progress.map(i => `• ${i}`).join('\n') : 'None'}\n\n`;
              msg += `✅ *Completed:*\n${dash.completed_items.map(i => `• ${i}`).join('\n')}\n\n`;
              msg += `🌐 Web Dashboard: http://127.0.0.1:3088\n`;
              msg += `💬 Session Turns: ${turnCount}/${MAX_TURNS_PER_SESSION}`;
              await sendTelegramMessage(fromChatId, msg);
            } catch (err) {
              await sendTelegramMessage(fromChatId, `📊 *Status Report*\nWorkspace: \`Caraeoke App\`\nStaff online: Axel, Vance, Ward.`);
            }
            continue;
          }

          if (text === '/newsession' || text === '/reset') {
            const newSessionId = await createFreshSession();
            await sendTelegramMessage(fromChatId, `🔄 *Fresh Session Spawned:*\n\`${newSessionId}\`\nInput tokens reset to minimum (~4,000). State preserved in Mnemon memory.`);
            continue;
          }

          // Forward user command to DSH session
          console.log(`[Telegram -> DSH] Received: ${text.slice(0, 50)}...`);
          await sendTelegramMessage(fromChatId, `⏳ *Task received by Josh.* Dispatching...`);
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
console.log('[Bridge] Starting Chief of Staff Telegram Bridge...');
connectDshEvents();
pollTelegram();
