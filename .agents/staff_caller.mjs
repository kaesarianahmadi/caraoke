import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DASHBOARD_PATH = path.join(__dirname, 'dashboard.json');
const SKILLS_DIR = path.join(__dirname, 'skills');

const ROUTER9_URL = 'http://127.0.0.1:20133/v1/chat/completions';
const ROUTER9_KEY = 'sk-e92659a40677cd72-k5vczl-6164e221';

export async function dispatchToWorker(workerKey, modelId, systemSoul, prompt, skillNames = []) {
  const startTime = Date.now();
  console.log(`[Dispatch] Sending real request to ${workerKey.toUpperCase()} on model ${modelId}...`);

  // Inject requested skills into system context
  let fullSystemPrompt = systemSoul;
  for (const skillName of skillNames) {
    const skillPath = path.join(SKILLS_DIR, `${skillName}.md`);
    if (fs.existsSync(skillPath)) {
      const skillContent = fs.readFileSync(skillPath, 'utf8');
      fullSystemPrompt += `\n\n--- INJECTED SKILL: ${skillName} ---\n${skillContent}`;
      console.log(`[Skill] Injected ${skillName} into ${workerKey.toUpperCase()} context.`);
    }
  }

  let responseText = '';
  let errorMsg = null;
  let usage = null;

  try {
    const res = await fetch(ROUTER9_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${ROUTER9_KEY}`
      },
      body: JSON.stringify({
        model: modelId,
        messages: [
          { role: 'system', content: fullSystemPrompt },
          { role: 'user', content: prompt }
        ],
        max_tokens: 600
      })
    });

    const raw = await res.text();
    try {
      const data = JSON.parse(raw);
      if (data.choices && data.choices[0]) {
        let text = data.choices[0].message.content || '';
        if (text.includes('<｜｜DSML')) {
          text = text.split('<｜｜DSML')[0].trim();
        }
        responseText = text.trim();
        usage = data.usage;
      } else {
        errorMsg = data.error?.message || raw;
      }
    } catch {
      const match = raw.match(/"content":"(.*?)"/);
      if (match) {
        responseText = match[1].replace(/\\n/g, '\n').replace(/\\"/g, '"');
      } else {
        errorMsg = raw.slice(0, 250);
      }
    }
  } catch (err) {
    errorMsg = err.message;
  }

  const durationMs = Date.now() - startTime;

  // Log telemetry to dashboard.json
  try {
    const dash = JSON.parse(fs.readFileSync(DASHBOARD_PATH, 'utf8'));
    dash.updated_at = new Date().toISOString();
    if (dash.workers[workerKey]) {
      dash.workers[workerKey].status = errorMsg ? 'error' : 'active';
      dash.workers[workerKey].last_activity = responseText.slice(0, 120);
      dash.workers[workerKey].active_model = modelId;
    }

    if (!dash.telemetry_log) dash.telemetry_log = [];
    dash.telemetry_log.unshift({
      timestamp: new Date().toLocaleTimeString(),
      caller: "Josh (Chief of Staff)",
      worker: workerKey,
      model: modelId,
      skills_used: skillNames,
      duration_ms: durationMs,
      prompt_preview: prompt.slice(0, 90),
      response_preview: responseText || `Error: ${errorMsg}`,
      status: errorMsg ? 'failed' : 'success'
    });

    dash.telemetry_log = dash.telemetry_log.slice(0, 20);
    fs.writeFileSync(DASHBOARD_PATH, JSON.stringify(dash, null, 2));
  } catch (err) {
    console.error('Failed to write dashboard:', err.message);
  }

  return { workerKey, modelId, responseText, errorMsg, durationMs };
}
