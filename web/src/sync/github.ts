import { ConflictError, MANIFEST_PATH, shardPath, type Cursor, type Manifest, type VaultStore } from './vault'

/**
 * Adapter A — a private GitHub repository as the vault.
 *
 * This is the transport that works without any server at all, which is why it
 * is the default: the app is a static page, and GitHub's REST API sets
 * `Access-Control-Allow-Origin: *` and accepts the Authorization header, so the
 * browser can talk to it directly.
 *
 * Blob SHAs are the version tokens, and the Contents API's `sha` parameter is a
 * compare-and-swap: a stale SHA is rejected with 409, which is exactly the
 * conflict signal the sync engine retries on.
 *
 * Reads go through the Git Data API rather than the Contents API because the
 * latter refuses to return a file over 1 MB as JSON, and a few years of ledger
 * will cross that.
 */

const API = 'https://api.github.com'

export interface GitHubConfig {
  owner: string
  repo: string
  branch: string
  token: string
}

export class GitHubError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly kind: 'auth' | 'not-found' | 'rate-limit' | 'conflict' | 'other',
  ) {
    super(message)
    this.name = 'GitHubError'
  }
}

interface TreeEntry {
  path: string
  sha: string
  type: string
}

export class GitHubStore implements VaultStore {
  readonly kind = 'github' as const
  /** Blob SHAs from the last tree read, so a write knows what it is replacing. */
  private shas = new Map<string, string>()

  constructor(private cfg: GitHubConfig) {}

  describe(): string {
    return `${this.cfg.owner}/${this.cfg.repo}`
  }

  private async call(path: string, init: RequestInit = {}, accept = 'application/vnd.github+json'): Promise<Response> {
    const res = await fetch(`${API}${path}`, {
      ...init,
      headers: {
        accept,
        authorization: `Bearer ${this.cfg.token}`,
        'x-github-api-version': '2022-11-28',
        ...(init.body ? { 'content-type': 'application/json' } : {}),
        ...init.headers,
      },
    })
    if (res.ok) return res

    const body = await res.text().catch(() => '')
    if (res.status === 401 || res.status === 403) {
      const remaining = res.headers.get('x-ratelimit-remaining')
      if (remaining === '0') {
        const reset = Number(res.headers.get('x-ratelimit-reset') ?? 0) * 1000
        throw new GitHubError(`GitHub rate limit reached; resets ${new Date(reset).toLocaleTimeString()}`, res.status, 'rate-limit')
      }
      throw new GitHubError('token rejected — check it has Contents write access to this repository', res.status, 'auth')
    }
    if (res.status === 404) throw new GitHubError(`not found: ${path}`, 404, 'not-found')
    if (res.status === 409 || res.status === 422) throw new ConflictError()
    throw new GitHubError(`GitHub ${res.status}: ${body.slice(0, 200)}`, res.status, 'other')
  }

  /** Cheap credential check that also tells the user what the token can see. */
  async verify(): Promise<{ ok: true; detail: string } | { ok: false; error: string }> {
    try {
      const repo = (await (await this.call(`/repos/${this.cfg.owner}/${this.cfg.repo}`)).json()) as {
        full_name: string
        private: boolean
        permissions?: { push?: boolean }
      }
      if (!repo.permissions?.push) return { ok: false, error: '这个令牌只能读，不能写。需要 Contents: Read and write。' }
      return { ok: true, detail: `${repo.full_name}${repo.private ? ' · 私有' : ' · 公开（建议改成私有）'}` }
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) }
    }
  }

  async readManifest(): Promise<Manifest | null> {
    try {
      const res = await this.call(
        `/repos/${this.cfg.owner}/${this.cfg.repo}/contents/${MANIFEST_PATH}?ref=${this.cfg.branch}`,
        {},
        'application/vnd.github.raw',
      )
      return JSON.parse(await res.text()) as Manifest
    } catch (e) {
      if (e instanceof GitHubError && e.kind === 'not-found') return null
      throw e
    }
  }

  async writeManifest(m: Manifest): Promise<void> {
    await this.put(MANIFEST_PATH, btoa(unescape(encodeURIComponent(JSON.stringify(m, null, 2)))), this.shas.get(MANIFEST_PATH) ?? null, 'vault: manifest')
  }

  async listShards(): Promise<Cursor> {
    const out: Cursor = {}
    try {
      const res = await this.call(
        `/repos/${this.cfg.owner}/${this.cfg.repo}/git/trees/${this.cfg.branch}?recursive=1`,
      )
      const tree = (await res.json()) as { tree?: TreeEntry[]; truncated?: boolean }
      for (const e of tree.tree ?? []) {
        if (e.type !== 'blob') continue
        this.shas.set(e.path, e.sha)
        if (e.path.startsWith('vault/s/')) out[e.path] = e.sha
      }
    } catch (e) {
      // An empty repository has no tree yet; that is a valid starting state.
      if (!(e instanceof GitHubError && e.kind === 'not-found')) throw e
    }
    return out
  }

  async readShard(month: string): Promise<string> {
    const path = shardPath(month)
    const sha = this.shas.get(path)
    if (!sha) throw new GitHubError(`no such shard: ${path}`, 404, 'not-found')
    // The blobs endpoint has no 1 MB ceiling, unlike the contents endpoint.
    const res = await this.call(
      `/repos/${this.cfg.owner}/${this.cfg.repo}/git/blobs/${sha}`,
      {},
      'application/vnd.github.raw',
    )
    return await res.text()
  }

  async writeShard(month: string, body: string, expected: string | null): Promise<string> {
    const path = shardPath(month)
    // The file's bytes are the base64 of the envelope; the Contents API then
    // base64s that again for transport. Double encoding is 33% waste on a small
    // file and buys a plain-text blob that `git diff` will not try to merge.
    const sha = await this.put(path, btoa(body), expected, `vault: ${month}`)
    this.shas.set(path, sha)
    return sha
  }

  private async put(path: string, contentB64: string, expected: string | null, message: string): Promise<string> {
    const res = await this.call(`/repos/${this.cfg.owner}/${this.cfg.repo}/contents/${path}`, {
      method: 'PUT',
      body: JSON.stringify({
        message,
        content: contentB64,
        branch: this.cfg.branch,
        ...(expected ? { sha: expected } : {}),
      }),
    })
    const json = (await res.json()) as { content?: { sha?: string } }
    const sha = json.content?.sha
    if (!sha) throw new GitHubError('write succeeded but returned no sha', 500, 'other')
    return sha
  }
}

/** A one-click link that pre-fills the scopes the vault needs. */
export const TOKEN_URL =
  'https://github.com/settings/tokens/new?scopes=repo&description=Countbook%20%E8%8A%B1%E5%BE%97%E5%80%BC'
