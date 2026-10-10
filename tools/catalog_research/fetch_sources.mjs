import fs from 'node:fs';
import crypto from 'node:crypto';

const root = 'data/aviation';
fs.mkdirSync(`${root}/raw`, {recursive: true});
const manifestPath = `${root}/source_manifest.json`;
const manifest = fs.existsSync(manifestPath) ? JSON.parse(fs.readFileSync(manifestPath, 'utf8')) : [];
const pairs = process.argv.slice(2);
if (pairs.length % 2) throw new Error('Use pairs of source ID and public URL');
for (let i = 0; i < pairs.length; i += 2) {
  const [id, url] = pairs.slice(i, i + 2);
  if (!/^[a-z0-9-]+$/.test(id)) throw new Error('Invalid source ID');
  try {
    const r = await fetch(url, {signal: AbortSignal.timeout(45000)});
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const html = await r.text();
    fs.writeFileSync(`${root}/raw/${id}.html`, html);
    const entry = {id, url, final_url: r.url, retrieved_at: new Date().toISOString(), http_status: r.status, bytes: Buffer.byteLength(html), sha256: crypto.createHash('sha256').update(html).digest('hex'), raw_file: `raw/${id}.html`, publication_date: null};
    const existing = manifest.findIndex(x => x.id === id);
    if (existing === -1) manifest.push(entry); else manifest[existing] = entry;
    fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
    console.log(JSON.stringify({id, status: r.status, bytes: entry.bytes}));
  } catch (e) { console.log(JSON.stringify({id, error: e.message})); process.exitCode = 1; }
}
