/**
 * Minimal read-only connectivity probe for a profile.
 */
import { getProviderEnvMap, type Provider } from './config/store.js';
import { T } from './i18n/index.js';

export interface CheckResult {
  ok: boolean;
  message: string;
}

const TIMEOUT_MS = 5000;

/** Probe GET {base}/v1/models with the profile's configured auth. */
export async function checkProfile(p: Provider): Promise<CheckResult> {
  const m = getProviderEnvMap(p);
  const base = (m.ANTHROPIC_BASE_URL ?? '').trim();
  if (!base) return { ok: false, message: T('check.noUrl') };

  const headers = authHeaders(m);
  if (!headers) return { ok: false, message: T('check.noKey') };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const resp = await fetch(`${base.replace(/\/+$/, '')}/v1/models`, {
      method: 'GET',
      headers: { ...headers, 'anthropic-version': '2023-06-01' },
      signal: controller.signal,
    });
    const code = String(resp.status);
    if (resp.ok) return { ok: true, message: T('check.ok', code) };
    if (resp.status === 401 || resp.status === 403) return { ok: false, message: T('check.auth', code) };
    if (resp.status === 404) return { ok: false, message: T('check.notFound', code) };
    return { ok: false, message: T('check.http', code) };
  } catch (e) {
    if ((e as Error).name === 'AbortError') return { ok: false, message: T('check.timeout') };
    const code = (e as NodeJS.ErrnoException).cause && typeof (e as NodeJS.ErrnoException).cause === 'object'
      ? ((e as NodeJS.ErrnoException).cause as NodeJS.ErrnoException).code
      : (e as NodeJS.ErrnoException).code;
    if (code === 'ENOTFOUND' || code === 'EAI_AGAIN') return { ok: false, message: T('check.dns') };
    return { ok: false, message: T('check.network') };
  } finally {
    clearTimeout(timer);
  }
}

function authHeaders(m: Record<string, string>): Record<string, string> | undefined {
  const apiKey = (m.ANTHROPIC_API_KEY ?? '').trim();
  if (apiKey) return { 'x-api-key': apiKey };
  const token = (m.ANTHROPIC_AUTH_TOKEN ?? '').trim();
  if (token) return { Authorization: `Bearer ${token}` };
  return undefined;
}
