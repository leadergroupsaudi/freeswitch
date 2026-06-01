const express      = require('express');
const bodyParser   = require('body-parser');
const cors         = require('cors');
const path         = require('path');
const fs           = require('fs');
const multer       = require('multer');
const { execSync } = require('child_process');

const app = express();
app.use(cors());
app.use(bodyParser.json({ limit: '10mb' }));
app.use(express.static(path.join(__dirname, 'public')));

// ─── Config ───────────────────────────────────────────────────────────────────
const API_KEY = process.env.API_KEY || 'LeaderFS@Axionic#2026';
const PORT    = process.env.PORT    || 3000;

// ─── FreeSWITCH Paths (CentOS Production) ────────────────────────────────────
const FS_BASE      = '/usr/local/freeswitch-automax-instance';
const FS_SCRIPTS   = `${FS_BASE}/share/freeswitch/scripts`;
const FS_IVR_FLOWS = `${FS_BASE}/share/freeswitch/scripts/ivr_flows`;
const FS_DIALPLAN  = `${FS_BASE}/etc/freeswitch/dialplan/ivr_extensions`;
const FS_SOUNDS    = `${FS_BASE}/share/freeswitch/sounds/custom`;
const FS_CLI       = `/bin/fs_cli_automax --port 8022`;
// ─────────────────────────────────────────────────────────────────────────────

const store = {};

// Ensure required directories exist
[FS_IVR_FLOWS, FS_DIALPLAN, FS_SOUNDS].forEach(dir => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
    console.log(`Created: ${dir}`);
  }
});

// ─── API Key Middleware ───────────────────────────────────────────────────────
function requireApiKey(req, res, next) {
  const key = req.headers['x-api-key'];
  if (!key)         return res.status(401).json({ success: false, error: 'Unauthorized', message: 'Missing X-Api-Key header' });
  if (key !== API_KEY) return res.status(403).json({ success: false, error: 'Forbidden',      message: 'Invalid API key' });
  next();
}

// ─── File Helpers ─────────────────────────────────────────────────────────────
function writeJSON(p) {
  const fp = `${FS_IVR_FLOWS}/${p.extension}.json`;
  fs.writeFileSync(fp, JSON.stringify(p, null, 2), 'utf8');
  return fp;
}
function writeLua(p) {
  const fp = `${FS_SCRIPTS}/ivr_engine_${p.extension}.lua`;
  fs.writeFileSync(fp, genLua(p), 'utf8');
  return fp;
}
function writeXML(p) {
  const fp = `${FS_DIALPLAN}/${p.extension}.xml`;
  fs.writeFileSync(fp, genXML(p), 'utf8');
  return fp;
}
function deleteFiles(ext) {
  [`${FS_IVR_FLOWS}/${ext}.json`,
   `${FS_SCRIPTS}/ivr_engine_${ext}.lua`,
   `${FS_DIALPLAN}/${ext}.xml`
  ].forEach(f => { try { fs.unlinkSync(f); } catch (_) {} });
}
function reloadXML() {
  try {
    const out = execSync(`${FS_CLI} -x "reloadxml"`, { timeout: 5000 }).toString().trim();
    return { status: 'ok', output: out };
  } catch (e) {
    return { status: 'error', output: e.message };
  }
}

// ─── Validation ───────────────────────────────────────────────────────────────
function validate(p) {
  const e = [];
  if (!p.extension) e.push('extension required');
  if (!p.entry)     e.push('entry required');
  if (!p.nodes || typeof p.nodes !== 'object') { e.push('nodes required'); return e; }
  if (!p.nodes[p.entry]) e.push(`entry node "${p.entry}" not found in nodes`);
  Object.entries(p.nodes).forEach(([n, node]) => {
    if (!node || typeof node !== 'object') { e.push(`Node "${n}" is invalid`); return; }
    if (!node.type) { e.push(`Node "${n}" missing type`); return; }
    if (['menu','confirm','submenu'].includes(node.type)) {
      if (!node.audio)        e.push(`Node "${n}" missing audio`);
      if (!node.digits)       e.push(`Node "${n}" missing digits`);
      if (!node.valid_digits) e.push(`Node "${n}" missing valid_digits`);
      if (!node.next)         e.push(`Node "${n}" missing next`);
    }
    if (node.type === 'transfer' && !node.destination) e.push(`Node "${n}" transfer missing destination`);
    if (node.type === 'voicemail' && !node.mailbox)    e.push(`Node "${n}" voicemail missing mailbox`);
  });
  return e;
}

// ─── Simulate ─────────────────────────────────────────────────────────────────
function simulate(flow, digits) {
  const log = []; let cur = flow.entry, di = 0, steps = 0;
  while (cur && steps++ < 50) {
    const node = flow.nodes[cur];
    if (!node) { log.push({ node: cur, type: 'error', action: 'Node not found' }); break; }
    if (['menu','confirm','submenu'].includes(node.type)) {
      const digit = digits[di++] || null;
      log.push({ node: cur, type: node.type, action: `PLAY: ${node.audio}`, digit, validKeys: node.valid_digits });
      if (digit && node.next && node.next[digit]) {
        const nxt = node.next[digit];
        log.push({ node: cur, type: 'route', action: `Key "${digit}" → ${nxt}` });
        if (nxt === '__hangup__') { log.push({ node: 'system', type: 'hangup', action: 'HANGUP' }); break; }
        cur = nxt;
      } else { log.push({ node: cur, type: 'invalid', action: `Invalid digit "${digit||'none'}" → HANGUP` }); break; }
    } else if (node.type === 'transfer') {
      log.push({ node: cur, type: 'transfer', action: `TRANSFER → ${node.destination} [${node.mode||'blind'}]`, result: 'CALL TRANSFERRED' }); break;
    } else if (node.type === 'voicemail') {
      log.push({ node: cur, type: 'voicemail', action: `VOICEMAIL → mailbox:${node.mailbox}`, result: 'RECORDING' }); break;
    } else if (node.type === 'hangup') {
      log.push({ node: cur, type: 'hangup', action: node.audio ? `PLAY: ${node.audio}` : 'HANGUP', result: 'ENDED' }); break;
    } else if (['greeting','audio','play'].includes(node.type)) {
      log.push({ node: cur, type: node.type, action: `PLAY: ${node.audio||node.msg||'—'}` });
      cur = typeof node.next === 'string' ? node.next : (node.next ? Object.values(node.next)[0] : null);
    } else if (node.type === 'hours') {
      const h = new Date().getHours(), m = new Date().getMinutes(), now = h*60+m;
      const [sh,sm] = (node.open_start||'09:00').split(':').map(Number);
      const [eh,em] = (node.open_end  ||'18:00').split(':').map(Number);
      const open = now >= sh*60+sm && now < eh*60+em;
      log.push({ node: cur, type: 'hours', action: `HOURS → ${open?'OPEN':'CLOSED'}` });
      cur = open ? node.next?.open : node.next?.closed;
    } else if (node.type === 'holiday') {
      const today = new Date().toISOString().split('T')[0];
      const isH = (node.holidays||'').includes(today);
      log.push({ node: cur, type: 'holiday', action: `HOLIDAY → ${isH?'HOLIDAY':'NORMAL'}` });
      cur = isH ? node.next?.holiday : node.next?.normal;
    } else { log.push({ node: cur, type: 'unknown', action: `Unknown type: ${node.type}` }); break; }
  }
  return log;
}

// ─── Code Generators ──────────────────────────────────────────────────────────
function toLua(obj, indent) {
  indent = indent || '  ';
  if (obj === null || obj === undefined) return 'nil';
  if (typeof obj === 'boolean') return String(obj);
  if (typeof obj === 'number')  return String(obj);
  if (typeof obj === 'string')  return `"${obj.replace(/\\/g,'\\\\').replace(/"/g,'\\"')}"`;
  if (typeof obj === 'object') {
    const lines = Object.entries(obj).map(([k,v]) => `${indent}  ["${k}"] = ${toLua(v, indent+'  ')}`);
    return `{\n${lines.join(',\n')}\n${indent}}`;
  }
  return 'nil';
}

function genLua(p) {
  const ext = p.extension;
  return `-- IVR Engine: ${ext} | Generated: ${new Date().toISOString()}
-- No external dependencies (flow embedded as Lua table)
local flow = ${toLua({ entry: p.entry, nodes: p.nodes })}

session:answer()
session:sleep(500)

local function getDigits(n)
  local a,b,c,d = n.digits:match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
  return session:playAndGetDigits(
    tonumber(a),tonumber(b),tonumber(c),tonumber(d),
    "#", n.audio or "", n.invalid_audio or "", n.valid_digits or "[0-9]+"
  )
end

local depth = 0
local function exec(name)
  depth = depth + 1
  if depth > 50 then session:execute("hangup"); return end
  local n = flow.nodes[name]
  if not n then session:execute("hangup"); return end
  if n.type == "menu" or n.type == "confirm" or n.type == "submenu" then
    local retries, att = n.max_retries or 3, 0
    while att < retries do
      local d = getDigits(n)
      if d and d ~= "" and n.next and n.next[d] then
        if n.next[d] == "__hangup__" then session:execute("hangup"); return end
        exec(n.next[d]); return
      end
      att = att + 1
    end
    session:execute("hangup")
  elseif n.type == "transfer" then
    local m = n.mode or "blind"
    if m == "queue" then
      session:execute("fifo", n.destination.." in undef "..(n.ringback or "local_stream://moh"))
    else
      session:execute("transfer", n.destination.." XML "..(n.context or "default"))
    end
  elseif n.type == "voicemail" then
    session:execute("voicemail","default "..(n.domain or "default").." "..n.mailbox)
  elseif n.type == "hangup" then
    if n.audio then session:execute("playback",n.audio) end
    session:execute("hangup")
  elseif n.type == "greeting" or n.type == "audio" then
    if n.audio then session:execute("playback",n.audio)
    elseif n.msg then session:execute("speak","flite|kal|"..n.msg) end
    if n.next then
      local nxt = type(n.next)=="string" and n.next or next(n.next)
      if nxt then exec(nxt) end
    end
  elseif n.type == "hours" then
    local hour=tonumber(os.date("%H")); local min=tonumber(os.date("%M"))
    local now=hour*60+min
    local sh,sm=(n.open_start or "09:00"):match("(%d+):(%d+)")
    local eh,em=(n.open_end   or "18:00"):match("(%d+):(%d+)")
    local is_open=now>=tonumber(sh)*60+tonumber(sm) and now<tonumber(eh)*60+tonumber(em)
    exec(is_open and n.next.open or n.next.closed)
  elseif n.type == "holiday" then
    local today=os.date("%Y-%m-%d")
    local is_holiday=(n.holidays or ""):find(today,1,true)~=nil
    exec(is_holiday and n.next.holiday or n.next.normal)
  end
  depth = depth - 1
end

exec(flow.entry or "main_menu")
`;
}

function genXML(p) {
  const ext = p.extension, did = p.did || '';
  let pat = `^${ext}$`;
  if (did) pat = `^(${ext}|${did.replace('+','\\+')})$`;
  return `<?xml version="1.0" encoding="utf-8"?>
<!-- IVR: ${p.ivrName||ext} | Ext: ${ext} | Generated: ${new Date().toISOString()} -->
<extension name="IVR_${ext}">
  <condition field="destination_number" expression="${pat}">
    <action application="answer"/>
    <action application="set" data="ivr_extension=${ext}"/>
    <action application="lua" data="ivr_engine_${ext}.lua"/>
  </condition>
</extension>`;
}

// ─── IVR Routes ───────────────────────────────────────────────────────────────

// CREATE
app.post('/api/ivr/create', requireApiKey, (req, res) => {
  const p = req.body, errs = validate(p);
  if (errs.length) return res.status(400).json({ success: false, message: 'Validation failed', errors: errs });
  if (store[p.extension]) return res.status(409).json({ success: false, message: `Extension ${p.extension} already exists. Use PUT to update.` });
  const ext = p.extension, steps = [];
  try {
    steps.push({ step: 'validate',     status: 'ok' });
    store[ext] = { ...p, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() };
    const jsonPath = writeJSON(p); steps.push({ step: 'save_json',    status: 'ok', path: jsonPath });
    const luaPath  = writeLua(p);  steps.push({ step: 'generate_lua', status: 'ok', path: luaPath  });
    const xmlPath  = writeXML(p);  steps.push({ step: 'generate_xml', status: 'ok', path: xmlPath  });
    const reload   = reloadXML();  steps.push({ step: 'reloadxml',    status: reload.status, output: reload.output });
    res.status(201).json({ success: true, message: `IVR ${ext} created. Dial ${ext} to test.`, extension: ext, did: p.did||null, ivrName: p.ivrName||`IVR_${ext}`, nodeCount: Object.keys(p.nodes).length, steps, files: { json: jsonPath, lua: luaPath, dialplan: xmlPath } });
  } catch (err) {
    steps.push({ step: 'error', status: 'error', output: err.message });
    res.status(500).json({ success: false, message: 'File write failed', error: err.message, steps });
  }
});

// UPDATE
app.put('/api/ivr/:ext', requireApiKey, (req, res) => {
  const ext = req.params.ext, p = { ...req.body, extension: ext }, errs = validate(p);
  if (errs.length) return res.status(400).json({ success: false, errors: errs });
  if (!store[ext]) return res.status(404).json({ success: false, message: `IVR ${ext} not found` });
  const steps = [];
  try {
    steps.push({ step: 'validate',     status: 'ok' });
    store[ext] = { ...p, createdAt: store[ext].createdAt, updatedAt: new Date().toISOString() };
    const jsonPath = writeJSON(p); steps.push({ step: 'save_json',    status: 'ok', path: jsonPath });
    const luaPath  = writeLua(p);  steps.push({ step: 'generate_lua', status: 'ok', path: luaPath  });
    const xmlPath  = writeXML(p);  steps.push({ step: 'generate_xml', status: 'ok', path: xmlPath  });
    const reload   = reloadXML();  steps.push({ step: 'reloadxml',    status: reload.status, output: reload.output });
    res.json({ success: true, message: `IVR ${ext} updated`, extension: ext, nodeCount: Object.keys(p.nodes).length, steps, files: { json: jsonPath, lua: luaPath, dialplan: xmlPath } });
  } catch (err) {
    steps.push({ step: 'error', status: 'error', output: err.message });
    res.status(500).json({ success: false, message: 'File write failed', error: err.message, steps });
  }
});

// DELETE
app.delete('/api/ivr/:ext', requireApiKey, (req, res) => {
  const ext = req.params.ext;
  if (!store[ext]) return res.status(404).json({ success: false, message: `IVR ${ext} not found` });
  try {
    deleteFiles(ext); delete store[ext];
    const reload = reloadXML();
    res.json({ success: true, message: `IVR ${ext} deleted`, reloadxml: reload.output });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Delete failed', error: err.message });
  }
});

// LIST
app.get('/api/ivr/list', (req, res) => {
  const ivrs = Object.values(store).map(d => ({
    extension: d.extension, did: d.did||null, ivrName: d.ivrName||`IVR_${d.extension}`,
    entry: d.entry, nodeCount: Object.keys(d.nodes||{}).length, context: d.context||'default',
    createdAt: d.createdAt, updatedAt: d.updatedAt,
    files: { json: `${FS_IVR_FLOWS}/${d.extension}.json`, lua: `${FS_SCRIPTS}/ivr_engine_${d.extension}.lua`, dialplan: `${FS_DIALPLAN}/${d.extension}.xml` }
  }));
  res.json({ success: true, count: ivrs.length, ivrs });
});

// GET ONE
app.get('/api/ivr/:ext', (req, res) => {
  const d = store[req.params.ext];
  if (!d) return res.status(404).json({ success: false, message: `IVR ${req.params.ext} not found` });
  res.json({ success: true, ivr: d, files: { json: `${FS_IVR_FLOWS}/${d.extension}.json`, lua: `${FS_SCRIPTS}/ivr_engine_${d.extension}.lua`, dialplan: `${FS_DIALPLAN}/${d.extension}.xml` } });
});

// VALIDATE dry-run
app.post('/api/ivr/validate', (req, res) => {
  const p = req.body, errs = validate(p);
  if (errs.length) return res.status(400).json({ success: false, valid: false, errors: errs });
  res.json({ success: true, valid: true, message: 'Valid', extension: p.extension, nodeCount: Object.keys(p.nodes||{}).length, preview: { lua: genLua(p), xml: genXML(p) } });
});

// SIMULATE
app.post('/api/ivr/simulate', (req, res) => {
  const { extension, digits } = req.body, ivr = store[extension];
  if (!ivr) return res.status(404).json({ success: false, message: `IVR ${extension} not found` });
  const seq = (digits||'').toString().split('').filter(d => /\d/.test(d));
  res.json({ success: true, extension, digits: seq, callLog: simulate(ivr, seq) });
});

// PREVIEW LUA
app.get('/api/ivr/preview/lua/:ext', (req, res) => {
  const d = store[req.params.ext];
  if (!d) return res.status(404).send('Not found');
  res.type('text/plain').send(genLua(d));
});

// PREVIEW XML
app.get('/api/ivr/preview/xml/:ext', (req, res) => {
  const d = store[req.params.ext];
  if (!d) return res.status(404).send('Not found');
  res.type('text/xml').send(genXML(d));
});

// ─── Audio Upload ─────────────────────────────────────────────────────────────
// Uses multer.any() to accept ANY field name for files
// This supports: single file, multiple files, any field name
const audioUpload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => {
      fs.mkdirSync(FS_SOUNDS, { recursive: true });
      cb(null, FS_SOUNDS);
    },
    filename: (req, file, cb) => {
      cb(null, file.originalname);
    }
  }),
  fileFilter: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    if (['.wav', '.mp3', '.ogg'].includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error(`Invalid file type "${ext}". Only .wav .mp3 .ogg allowed`));
    }
  },
  limits: { fileSize: 20 * 1024 * 1024 } // 20MB per file
});

// POST /api/audio/upload  (requires API key)
// Accepts any field name, any number of files
// curl -F "file=@a.wav" -F "file=@b.wav"   ← multiple with same field
// curl -F "files=@a.wav" -F "files=@b.wav" ← multiple with "files" field
// curl -F "audio=@a.wav"                   ← any field name works
app.post('/api/audio/upload', requireApiKey, (req, res) => {
  audioUpload.any()(req, res, function(err) {
    if (err) {
      return res.status(400).json({ success: false, message: err.message });
    }

    const files = req.files || [];

    if (files.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'No files received. Send files as form-data with any field name (file, files, audio, etc.)'
      });
    }

    // Handle optional subdir — move files if needed
    const subdir = req.body && req.body.subdir ? req.body.subdir : '';
    const uploaded = [];

    for (const f of files) {
      let finalPath = f.path; // already saved to FS_SOUNDS/filename
      if (subdir) {
        const destDir = path.join(FS_SOUNDS, subdir);
        fs.mkdirSync(destDir, { recursive: true });
        finalPath = path.join(destDir, f.originalname);
        fs.renameSync(f.path, finalPath);
      }
      uploaded.push({
        filename: f.originalname,
        path:     finalPath,
        size:     f.size,
        field:    f.fieldname
      });
    }

    res.json({
      success: true,
      message: `${uploaded.length} file(s) uploaded successfully`,
      count:   uploaded.length,
      files:   uploaded
    });
  });
});

// LIST AUDIO
app.get('/api/audio/list', (req, res) => {
  function scanDir(dir, base) {
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
      const rel = base ? `${base}/${entry.name}` : entry.name;
      if (entry.isDirectory()) return scanDir(path.join(dir, entry.name), rel);
      if (['.wav','.mp3','.ogg'].includes(path.extname(entry.name).toLowerCase()))
        return [{ name: entry.name, path: `${FS_SOUNDS}/${rel}`, relative: rel, size: fs.statSync(path.join(dir, entry.name)).size }];
      return [];
    });
  }
  res.json({ success: true, sounds_dir: FS_SOUNDS, files: scanDir(FS_SOUNDS, '') });
});

// DELETE AUDIO
app.delete('/api/audio/:filename', requireApiKey, (req, res) => {
  const fp = path.join(FS_SOUNDS, req.params.filename);
  if (!fp.startsWith(FS_SOUNDS)) return res.status(400).json({ success: false, message: 'Invalid path' });
  if (!fs.existsSync(fp))        return res.status(404).json({ success: false, message: 'File not found' });
  fs.unlinkSync(fp);
  res.json({ success: true, message: `Deleted ${req.params.filename}` });
});

// ─── Health ───────────────────────────────────────────────────────────────────
app.get('/health', (req, res) => {
  res.json({
    status: 'ok', service: 'IVR API Server', version: '3.0.0',
    domain: 'https://leadefs.axionic.io',
    paths: { scripts: FS_SCRIPTS, ivr_flows: FS_IVR_FLOWS, dialplan: FS_DIALPLAN, sounds: FS_SOUNDS, fs_cli: FS_CLI },
    filesystem_checks: {
      ivr_flows_dir: fs.existsSync(FS_IVR_FLOWS),
      dialplan_dir:  fs.existsSync(FS_DIALPLAN),
      scripts_dir:   fs.existsSync(FS_SCRIPTS),
      sounds_dir:    fs.existsSync(FS_SOUNDS)
    },
    ivr_count: Object.keys(store).length,
    timestamp: new Date().toISOString()
  });
});

// ─── Start ────────────────────────────────────────────────────────────────────
app.listen(PORT, '127.0.0.1', () => {
  console.log(`\n✅  IVR API Server v3.0.0 → http://127.0.0.1:${PORT}`);
  console.log(`🌐  Public URL  → https://leadefs.axionic.io`);
  console.log(`🔑  API Key     → ${API_KEY}`);
  console.log(`\n📂  Paths:`);
  console.log(`    Scripts   : ${FS_SCRIPTS}   [${fs.existsSync(FS_SCRIPTS)   ? '✓' : '✗ MISSING'}]`);
  console.log(`    IVR flows : ${FS_IVR_FLOWS} [${fs.existsSync(FS_IVR_FLOWS) ? '✓' : '✗ MISSING'}]`);
  console.log(`    Dialplan  : ${FS_DIALPLAN}  [${fs.existsSync(FS_DIALPLAN)  ? '✓' : '✗ MISSING'}]`);
  console.log(`    Sounds    : ${FS_SOUNDS}    [${fs.existsSync(FS_SOUNDS)    ? '✓' : '✗ MISSING'}]\n`);
  console.log(`🔒  Protected: POST /api/ivr/create | PUT /api/ivr/:ext | DELETE /api/ivr/:ext`);
  console.log(`🔒  Protected: POST /api/audio/upload | DELETE /api/audio/:filename\n`);
  console.log(`📤  Audio upload accepts ANY field name (file, files, audio, etc.)\n`);
});
