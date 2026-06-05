import { useEffect, useMemo, useState } from 'react';

const repoUrl = 'https://github.com/Leonmmcoset/csac-terminal';
const sourceUrl = `${repoUrl}/tree/main/flutter/csac`;
const releasesUrl = `${repoUrl}/releases`;
const latestReleaseUrl = `${releasesUrl}/latest`;
const releasesApiUrl =
  'https://api.github.com/repos/Leonmmcoset/csac-terminal/releases?per_page=5';
const crowdinUrl = 'https://zh.crowdin.com/project/csac-flutter';
const fallbackVersion = '1.3.9';

type ReleaseAsset = {
  id: number;
  name: string;
  browser_download_url: string;
  size: number;
};

type GitHubRelease = {
  id: number;
  name: string | null;
  tag_name: string;
  html_url: string;
  body: string | null;
  published_at: string | null;
  assets: ReleaseAsset[];
};

type LoadState = 'loading' | 'loaded' | 'error';

type IconName =
  | 'android'
  | 'bug_report'
  | 'chat'
  | 'code'
  | 'desktop_windows'
  | 'download'
  | 'groups'
  | 'lan'
  | 'markdown'
  | 'notifications'
  | 'open_in_new'
  | 'terminal'
  | 'translate';

const iconPaths: Record<IconName, string> = {
  android:
    'M17.6 9.48 19.2 6.7a1 1 0 0 0-1.74-1l-1.68 2.9A8.1 8.1 0 0 0 12 7.75c-1.36 0-2.64.33-3.77.9L6.46 5.7a1 1 0 1 0-1.72 1.02l1.68 2.84A7.5 7.5 0 0 0 4 15.1V18a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2.9a7.55 7.55 0 0 0-2.4-5.62ZM7.7 14.2a1.1 1.1 0 1 1 0-2.2 1.1 1.1 0 0 1 0 2.2Zm8.6 0a1.1 1.1 0 1 1 0-2.2 1.1 1.1 0 0 1 0 2.2Z',
  bug_report:
    'M20 8h-2.1a6.4 6.4 0 0 0-1.1-1.72L18 4.98 16.6 3.6l-1.38 1.37A6.3 6.3 0 0 0 13 4.14V2h-2v2.14c-.78.15-1.53.43-2.2.83L7.42 3.6 6 4.98l1.2 1.3A6.4 6.4 0 0 0 6.1 8H4v2h1.45A7.3 7.3 0 0 0 5.38 11v1H4v2h1.38v.9c0 .37.04.73.1 1.1H4v2h2.14A6.5 6.5 0 0 0 12 21a6.5 6.5 0 0 0 5.86-3H20v-2h-1.48c.06-.37.1-.73.1-1.1V14H20v-2h-1.38v-1c0-.34-.02-.67-.07-1H20V8Zm-8 11a4.5 4.5 0 0 1-4.5-4.5V11a4.5 4.5 0 0 1 9 0v3.5A4.5 4.5 0 0 1 12 19Zm-2-8.25a1.25 1.25 0 1 0 0 2.5 1.25 1.25 0 0 0 0-2.5Zm4 0a1.25 1.25 0 1 0 0 2.5 1.25 1.25 0 0 0 0-2.5Z',
  chat:
    'M4 5.5A3.5 3.5 0 0 1 7.5 2h9A3.5 3.5 0 0 1 20 5.5v6A3.5 3.5 0 0 1 16.5 15H10l-4.4 3.3A1 1 0 0 1 4 17.5V5.5Zm3.5-1A1.5 1.5 0 0 0 6 6v10l3.2-2.4a1 1 0 0 1 .6-.2h6.7A1.5 1.5 0 0 0 18 12V6a1.5 1.5 0 0 0-1.5-1.5h-9Z',
  code:
    'M8.7 16.3a1 1 0 0 1-1.4 1.4l-5-5a1 1 0 0 1 0-1.4l5-5a1 1 0 0 1 1.4 1.4L4.42 12l4.28 4.3Zm6.6 0L19.58 12 15.3 7.7a1 1 0 1 1 1.4-1.4l5 5a1 1 0 0 1 0 1.4l-5 5a1 1 0 0 1-1.4-1.4ZM13.96 4.26l-3 16a1 1 0 1 1-1.96-.38l3-16a1 1 0 1 1 1.96.38Z',
  desktop_windows:
    'M4 4h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-6v2h3a1 1 0 1 1 0 2H7a1 1 0 1 1 0-2h3v-2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Zm0 2v10h16V6H4Z',
  download:
    'M11 3a1 1 0 1 1 2 0v8.58l2.3-2.3a1 1 0 1 1 1.4 1.42l-4 4a1 1 0 0 1-1.4 0l-4-4a1 1 0 1 1 1.4-1.42l2.3 2.3V3ZM5 17a1 1 0 0 1 1 1v1h12v-1a1 1 0 1 1 2 0v2a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-2a1 1 0 0 1 1-1Z',
  groups:
    'M9 12a4 4 0 1 1 0-8 4 4 0 0 1 0 8Zm0 2c3.3 0 6 1.8 6 4v1a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-1c0-2.2 2.7-4 6-4Zm7.5-1.5a3 3 0 1 1 0-6 3 3 0 0 1 0 6Zm0 1.5c2.5 0 4.5 1.35 4.5 3v.5a1 1 0 0 1-1 1h-3.1V18c0-1.6-.9-3-2.3-4h1.9Z',
  lan:
    'M12 3a3 3 0 0 1 1 5.83V11h5a2 2 0 0 1 2 2v1.17A3 3 0 1 1 18 17v-3h-5v3.17a3 3 0 1 1-2 0V14H6v3a3 3 0 1 1-2-2.83V13a2 2 0 0 1 2-2h5V8.83A3 3 0 0 1 12 3Zm0 2a1 1 0 1 0 0 2 1 1 0 0 0 0-2ZM5 16a1 1 0 1 0 0 2 1 1 0 0 0 0-2Zm7 0a1 1 0 1 0 0 2 1 1 0 0 0 0-2Zm7 0a1 1 0 1 0 0 2 1 1 0 0 0 0-2Z',
  markdown:
    'M4 5h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2Zm0 2v10h16V7H4Zm2.5 3a1 1 0 0 1 1.8-.6L10 11.67l1.7-2.27a1 1 0 0 1 1.8.6v4a1 1 0 1 1-2 0v-1l-.7.94a1 1 0 0 1-1.6 0L8.5 13v1a1 1 0 1 1-2 0v-4Zm10.5 0a1 1 0 0 1 1 1v1.58l.3-.3a1 1 0 1 1 1.4 1.42l-2 2a1 1 0 0 1-1.4 0l-2-2a1 1 0 0 1 1.4-1.42l.3.3V11a1 1 0 0 1 1-1Z',
  notifications:
    'M12 22a2.5 2.5 0 0 1-2.45-2h4.9A2.5 2.5 0 0 1 12 22ZM5 17h14l-1.4-1.8a3 3 0 0 1-.6-1.84V10a5 5 0 0 0-10 0v3.36c0 .66-.22 1.3-.6 1.84L5 17Zm14.48-2.25L22 18v1H2v-1l2.52-3.25c.3-.38.48-.86.48-1.34V10a7 7 0 1 1 14 0v3.41c0 .48.17.96.48 1.34Z',
  open_in_new:
    'M6 5a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-5a1 1 0 1 1 2 0v5a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3V6a3 3 0 0 1 3-3h5a1 1 0 1 1 0 2H6Zm8-2h7v7a1 1 0 1 1-2 0V6.41l-7.3 7.3a1 1 0 0 1-1.4-1.42l7.29-7.29H14a1 1 0 1 1 0-2Z',
  terminal:
    'M4 5h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2Zm0 2v10h16V7H4Zm2.3 2.3a1 1 0 0 1 1.4 0l2 2a1 1 0 0 1 0 1.4l-2 2a1 1 0 1 1-1.4-1.4L7.58 12 6.3 10.7a1 1 0 0 1 0-1.4ZM11 14h5a1 1 0 1 1 0 2h-5a1 1 0 1 1 0-2Z',
  translate:
    'M12.87 15.07a11.4 11.4 0 0 1-3.24-2.26 12.2 12.2 0 0 0 2.2-4.31H14a1 1 0 1 0 0-2H9V5a1 1 0 0 0-2 0v1.5H2a1 1 0 1 0 0 2h7.74A10 10 0 0 1 8.2 11.4a11.2 11.2 0 0 1-1.5-2.03 1 1 0 0 0-1.74.98 13 13 0 0 0 1.75 2.42 12.2 12.2 0 0 1-3.19 2.1 1 1 0 0 0 .82 1.82 14.2 14.2 0 0 0 4.16-2.5 13.4 13.4 0 0 0 3.65 2.74 1 1 0 0 0 .72-1.86ZM17.2 10a1 1 0 0 1 .93.64l3.8 9.86a1 1 0 1 1-1.86.72L19.4 19h-4.8l-.67 2.22a1 1 0 0 1-1.86-.72l3.8-9.86a1 1 0 0 1 .93-.64h.4Zm-1.78 7h3.16L17 12.9 15.42 17Z',
};

function AppIcon({ name, slot }: { name: IconName; slot?: string }) {
  return (
    <svg
      aria-hidden="true"
      className="app-icon"
      focusable="false"
      slot={slot}
      viewBox="0 0 24 24"
    >
      <path d={iconPaths[name]} />
    </svg>
  );
}

const featureCards = [
  {
    icon: 'chat' as const,
    title: '聊天体验',
    body: '会话列表、私聊、群聊、引用回复、@ 成员、图片和语音消息都在一个客户端里完成。',
  },
  {
    icon: 'markdown' as const,
    title: 'Markdown 消息',
    body: '文字消息支持 Markdown 渲染，并对 HTML 做转义处理，代码块带有更清晰的阅读样式。',
  },
  {
    icon: 'groups' as const,
    title: '群组管理',
    body: '支持群资料、成员列表、邀请好友、管理员操作、群申请审核和群精华消息。',
  },
  {
    icon: 'notifications' as const,
    title: '通知中心',
    body: '集中处理通知、提及、回复和好友变更，未读数量会在应用内持续同步。',
  },
  {
    icon: 'translate' as const,
    title: '社区多语言',
    body: '翻译迁移到 Crowdin JSON，语言选择页可展示翻译进度，方便社区后续参与。',
  },
  {
    icon: 'lan' as const,
    title: '现代网络栈',
    body: '支持 HTTP/1.1 和 HTTP/2 协议显示，保留 PHP Session Cookie 登录态。',
  },
];

const platformCards = [
  {
    icon: 'desktop_windows' as const,
    title: 'Windows 安装包',
    body: '推荐从 Release 页面下载 Windows x64 安装器。',
    href: latestReleaseUrl,
    action: '打开最新 Release',
  },
  {
    icon: 'android' as const,
    title: 'Android APK',
    body: '移动端构建产物会随发布一起上传到 GitHub Releases。',
    href: releasesUrl,
    action: '查看发布文件',
  },
  {
    icon: 'terminal' as const,
    title: 'Linux / 其它平台',
    body: '查看每次发布包含的压缩包、可执行文件和构建说明。',
    href: releasesUrl,
    action: '浏览全部 Release',
  },
];

const fallbackRelease: GitHubRelease = {
  id: 0,
  tag_name: `v${fallbackVersion}`,
  name: `CsAC ${fallbackVersion}`,
  html_url: latestReleaseUrl,
  published_at: null,
  assets: [],
  body: [
    '当前页面会在浏览器中读取 GitHub Releases。',
    '如果网络不可用，可以直接打开 Release 页面查看安装包与更新日志。',
    '近期客户端已加入 Markdown 渲染、HTTP/2、Crowdin 多语言、邮箱验证和安装器 UI 改进。',
  ].join('\n'),
};

function formatDate(value: string | null) {
  if (!value) return '等待 GitHub Release 数据';
  return new Intl.DateTimeFormat('zh-CN', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(value));
}

function formatSize(bytes: number) {
  if (!Number.isFinite(bytes) || bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  let size = bytes;
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit += 1;
  }
  return `${size.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`;
}

function releaseTitle(release: GitHubRelease) {
  return release.name?.trim() || release.tag_name;
}

function releaseLines(release: GitHubRelease, maxLines = 5) {
  const body = release.body?.trim();
  if (!body) return ['这个 Release 暂无更新日志正文。'];
  return body
    .replace(/\r/g, '')
    .split('\n')
    .map((line) =>
      line
        .replace(/^#{1,6}\s*/, '')
        .replace(/^[-*]\s*/, '')
        .replace(/\*\*/g, '')
        .trim(),
    )
    .filter(Boolean)
    .slice(0, maxLines);
}

function App() {
  const [releases, setReleases] = useState<GitHubRelease[]>([fallbackRelease]);
  const [loadState, setLoadState] = useState<LoadState>('loading');

  useEffect(() => {
    const controller = new AbortController();
    fetch(releasesApiUrl, { signal: controller.signal })
      .then((response) => {
        if (!response.ok) {
          throw new Error(`GitHub API ${response.status}`);
        }
        return response.json() as Promise<GitHubRelease[]>;
      })
      .then((data) => {
        const stableReleases = data.filter((release) => !release.tag_name.includes('nightly'));
        setReleases(stableReleases.length > 0 ? stableReleases : [fallbackRelease]);
        setLoadState('loaded');
      })
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === 'AbortError') return;
        setLoadState('error');
      });
    return () => controller.abort();
  }, []);

  const latest = releases[0] ?? fallbackRelease;
  const releaseAssets = useMemo(() => latest.assets.slice(0, 6), [latest.assets]);

  return (
    <div className="app-shell">
      <header className="top-bar">
        <a className="brand" href="#top" aria-label="CsAC home">
          <img src="/icons/Icon-192.png" alt="" />
          <span>CsAC</span>
        </a>
        <nav aria-label="Primary navigation">
          <a href="#download">下载</a>
          <a href="#changelog">更新日志</a>
          <a href="#features">功能</a>
          <a href="#community">社区</a>
        </nav>
      </header>

      <main id="top">
        <section className="hero">
          <div className="hero-copy">
            <p className="eyebrow">Third-party CsAC client</p>
            <h1>CsAC</h1>
            <p className="lead">
              面向桌面和移动端的现代 CsAC 客户端。保留熟悉的聊天流程，同时加入本地缓存、
              Markdown、多语言、通知中心和跨平台发布支持。
            </p>
            <div className="hero-actions" aria-label="Primary actions">
              <md-filled-button href={latestReleaseUrl} target="_blank" rel="noreferrer">
                下载最新版本
                <AppIcon name="download" slot="icon" />
              </md-filled-button>
              <md-outlined-button href={releasesUrl} target="_blank" rel="noreferrer">
                查看 Release
                <AppIcon name="open_in_new" slot="icon" />
              </md-outlined-button>
            </div>
            <div className="hero-meta">
              <span className="meta-chip">当前版本 {fallbackVersion}</span>
              <span className="meta-chip">Windows x64 / Android / Linux</span>
            </div>
          </div>
        </section>

        <section id="download" className="section">
          <div className="section-heading">
            <p className="eyebrow">Download</p>
            <h2>下载与发布</h2>
            <p>
              官网直接链接到 GitHub Releases。安装包、APK、压缩包和源码快照都以 Release
              页面为准。
            </p>
          </div>
          <div className="download-grid">
            {platformCards.map((item) => (
              <article className="surface-card" key={item.title}>
                <AppIcon name={item.icon} />
                <h3>{item.title}</h3>
                <p>{item.body}</p>
                <md-outlined-button href={item.href} target="_blank" rel="noreferrer">
                  {item.action}
                </md-outlined-button>
              </article>
            ))}
          </div>
        </section>

        <section id="changelog" className="section section-tint">
          <div className="section-heading">
            <p className="eyebrow">Changelog</p>
            <h2>最近的更新日志</h2>
          </div>

          <div className="release-layout">
            <article className="release-panel">
              <div className="release-head">
                <div>
                  <p className="status-line">
                    {loadState === 'loading'
                      ? '正在加载 GitHub Releases'
                      : loadState === 'loaded'
                        ? '已同步 GitHub Releases'
                        : 'GitHub Releases 加载失败'}
                  </p>
                  <h3>{releaseTitle(latest)}</h3>
                  <p>{formatDate(latest.published_at)}</p>
                </div>
                <md-filled-button href={latest.html_url} target="_blank" rel="noreferrer">
                  打开详情
                </md-filled-button>
              </div>
              <ul className="release-lines">
                {releaseLines(latest).map((line) => (
                  <li key={line}>{line}</li>
                ))}
              </ul>
              {releaseAssets.length > 0 && (
                <div className="asset-list" aria-label="Release assets">
                  {releaseAssets.map((asset) => (
                    <a key={asset.id} href={asset.browser_download_url}>
                      <span>{asset.name}</span>
                      <small>{formatSize(asset.size)}</small>
                    </a>
                  ))}
                </div>
              )}
            </article>

            <div className="release-list">
              {releases.slice(0, 4).map((release) => (
                <a className="release-item" href={release.html_url} key={release.id}>
                  <span>{release.tag_name}</span>
                  <strong>{releaseTitle(release)}</strong>
                  <small>{formatDate(release.published_at)}</small>
                </a>
              ))}
            </div>
          </div>
        </section>

        <section id="features" className="section">
          <div className="section-heading">
            <p className="eyebrow">Features</p>
            <h2>核心能力</h2>
          </div>
          <div className="feature-grid">
            {featureCards.map((feature) => (
              <article className="surface-card feature-card" key={feature.title}>
                <md-icon>{feature.icon}</md-icon>
                <h3>{feature.title}</h3>
                <p>{feature.body}</p>
              </article>
            ))}
          </div>
        </section>

        <section id="community" className="section community-section">
          <div className="section-heading">
            <p className="eyebrow">Community</p>
            <h2>源码、翻译与反馈</h2>
            <p>项目使用 GitHub 管理源码和发布，社区多语言翻译通过 Crowdin 链接进入。</p>
          </div>
          <div className="community-actions">
            <md-elevated-button href={sourceUrl} target="_blank" rel="noreferrer">
              查看 Flutter 源码
              <AppIcon name="code" slot="icon" />
            </md-elevated-button>
            <md-elevated-button href={crowdinUrl} target="_blank" rel="noreferrer">
              参与 Crowdin 翻译
              <AppIcon name="translate" slot="icon" />
            </md-elevated-button>
            <md-elevated-button href={`${repoUrl}/issues`} target="_blank" rel="noreferrer">
              反馈问题
              <AppIcon name="bug_report" slot="icon" />
            </md-elevated-button>
          </div>
        </section>
      </main>

      <footer>
        <span>CsAC official website prototype</span>
        <a href={repoUrl}>GitHub</a>
        <a href={latestReleaseUrl}>Latest Release</a>
      </footer>
    </div>
  );
}

export default App;
