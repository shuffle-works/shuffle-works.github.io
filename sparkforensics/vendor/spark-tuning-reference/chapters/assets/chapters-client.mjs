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
  sidebar.querySelectorAll('.nav-link').forEach((link) => {
    link.addEventListener('click', () => {
      sidebar.classList.remove('sidebar-open');
      navToggle.setAttribute('aria-expanded', 'false');
    });
  });
}

const navSearch = document.getElementById('nav-search');
if (navSearch) {
  navSearch.addEventListener('input', () => {
    const query = navSearch.value.trim().toLowerCase();
    document.querySelectorAll('.nav-group').forEach((group) => {
      let anyVisible = false;
      group.querySelectorAll('.nav-list > li').forEach((item) => {
        const matches = !query || item.textContent.toLowerCase().includes(query);
        item.hidden = !matches;
        anyVisible = anyVisible || matches;
      });
      group.hidden = !anyVisible;
    });
  });
}
