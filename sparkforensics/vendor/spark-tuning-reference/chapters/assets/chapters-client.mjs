// Client behavior for the split reading site (per-chapter pages). A trimmed
// port of src/bridge.js's browser-wiring block: same theme toggle and mobile
// nav, minus the postMessage bridge and scroll-spy (each chapter is its own
// route here, not a scrolled section of one page).
const root = document.documentElement;
const toggle = document.getElementById('theme-toggle');

const syncThemeToggle = () => {
  const isLight = root.getAttribute('data-theme') === 'light';
  toggle?.setAttribute('aria-pressed', String(isLight));
  toggle?.setAttribute('aria-label', `Switch to ${isLight ? 'dark' : 'light'} theme`);
};

syncThemeToggle();
new MutationObserver(syncThemeToggle).observe(root, { attributes: true, attributeFilter: ['data-theme'] });

toggle?.addEventListener('click', () => {
  const theme = root.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
  root.setAttribute('data-theme', theme);
  try {
    localStorage.setItem('shuffle-works-theme', theme);
  } catch (_) {
    // The visual preference still works when persistent storage is blocked.
  }
});

const navToggle = document.getElementById('nav-toggle');
const sidebar = document.getElementById('sidebar');
if (navToggle && sidebar) {
  navToggle.addEventListener('click', () => {
    const isOpen = sidebar.classList.toggle('sidebar-open');
    navToggle.setAttribute('aria-expanded', String(isOpen));
  });
  // Delegated (rather than bound per-link at load): the full-text search
  // below injects new '.nav-link's into #nav-search-results after this
  // script runs, and those need the same close-on-click behavior.
  sidebar.addEventListener('click', (event) => {
    if (!event.target.closest('.nav-link')) return;
    sidebar.classList.remove('sidebar-open');
    navToggle.setAttribute('aria-expanded', 'false');
  });
}

// Full-text search: substring-match a query against every chapter's title
// and body text (assets/search-index.json, built by site/build-chapters.mjs
// from both the 'spark' and 'meta' corpora), not just the nav labels
// currently rendered in this page's own sidebar. Results replace the static
// nav groups while a query is present and link across corpora via
// '../<corpus>/<anchor>.html' (both corpora sit at the same depth under
// chapters/, same as the existing cross-corpus link in the shell template).
const navSearch = document.getElementById('nav-search');
if (navSearch && sidebar) {
  const staticGroups = Array.from(sidebar.querySelectorAll('.nav-group'));
  const results = document.createElement('div');
  results.className = 'nav-group';
  results.id = 'nav-search-results';
  results.hidden = true;
  results.setAttribute('role', 'status');
  results.setAttribute('aria-live', 'polite');
  navSearch.insertAdjacentElement('afterend', results);

  // Resolves to `null` (rather than `[]`) on a failed/missing fetch, so
  // renderResults can tell "the index didn't load" apart from "the index
  // loaded and nothing matched" instead of showing the same "No matches."
  // message for both.
  let indexPromise = null;
  const loadIndex = () => {
    if (!indexPromise) {
      indexPromise = fetch(new URL('search-index.json', import.meta.url))
        .then((response) => (response.ok ? response.json() : Promise.reject(new Error(String(response.status)))))
        .catch((err) => {
          console.error('search index unavailable:', err);
          return null;
        });
    }
    return indexPromise;
  };

  const renderResults = (query, entries) => {
    results.replaceChildren();
    if (entries === null) {
      const error = document.createElement('p');
      error.className = 'nav-search-empty';
      error.textContent = 'Search is unavailable right now.';
      results.appendChild(error);
      return;
    }
    const needle = query.toLowerCase();
    const matches = entries.filter(
      (entry) => entry.title.toLowerCase().includes(needle) || entry.text.toLowerCase().includes(needle),
    );
    if (matches.length === 0) {
      const empty = document.createElement('p');
      empty.className = 'nav-search-empty';
      empty.textContent = 'No matches.';
      results.appendChild(empty);
      return;
    }
    const list = document.createElement('ul');
    list.className = 'nav-list';
    for (const entry of matches) {
      const link = document.createElement('a');
      link.className = 'nav-link';
      link.href = `../${entry.corpus}/${entry.anchor}.html`;
      link.append(entry.title, ' ');
      const badge = document.createElement('span');
      badge.className = 'tag nav-search-corpus';
      badge.textContent = entry.corpus;
      link.appendChild(badge);
      const item = document.createElement('li');
      item.appendChild(link);
      list.appendChild(item);
    }
    results.appendChild(list);
  };

  navSearch.addEventListener('input', () => {
    const query = navSearch.value.trim();
    if (!query) {
      results.hidden = true;
      staticGroups.forEach((group) => {
        group.hidden = false;
      });
      return;
    }
    staticGroups.forEach((group) => {
      group.hidden = true;
    });
    results.hidden = false;
    loadIndex().then((entries) => renderResults(query, entries));
  });
}

// Copy-to-clipboard button for every code block (site/render.mjs highlights
// fenced code at build time; this stays client-side since it's a page
// affordance, not content).
document.querySelectorAll('.doc-section pre').forEach((pre) => {
  const code = pre.querySelector('code');
  if (!code) return;

  const wrapper = document.createElement('div');
  wrapper.className = 'code-block';
  pre.replaceWith(wrapper);
  wrapper.appendChild(pre);

  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'copy-button';
  button.textContent = 'Copy';
  button.setAttribute('aria-label', 'Copy code to clipboard');
  wrapper.appendChild(button);

  let resetTimer = null;
  button.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(code.textContent);
      button.textContent = 'Copied';
      button.classList.add('copied');
    } catch (_) {
      button.textContent = 'Copy failed';
    }
    clearTimeout(resetTimer);
    resetTimer = setTimeout(() => {
      button.textContent = 'Copy';
      button.classList.remove('copied');
    }, 1500);
  });
});
