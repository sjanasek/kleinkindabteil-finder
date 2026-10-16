// HTTP über das System-curl. Node's eigener TLS-Stack (undici/https) wird vom
// DB-Edge mit "OPS_BLOCKED" (HTTP 452) abgewiesen, macOS-curl nicht.
import { execFile } from 'node:child_process';

export function request(url, { method = 'GET', headers = {}, body, timeout = 20 } = {}) {
  const args = ['-s', '-S', '--max-time', String(timeout), '-w', '\n%{http_code}', '-X', method, url];
  for (const [k, v] of Object.entries(headers)) args.push('-H', `${k}: ${v}`);
  if (body != null) args.push('--data-binary', '@-');
  return new Promise((resolve, reject) => {
    const child = execFile('curl', args, { maxBuffer: 64 * 1024 * 1024 }, (err, stdout, stderr) => {
      if (err && !stdout) return reject(new Error(`curl: ${stderr || err.message}`));
      const i = stdout.lastIndexOf('\n');
      const status = Number(stdout.slice(i + 1));
      resolve({ status, ok: status >= 200 && status < 300, text: stdout.slice(0, i) });
    });
    if (body != null) child.stdin.end(body);
  });
}
