(function () {
  'use strict';

  document.documentElement.classList.remove('no-js');
  document.documentElement.classList.add('js');

  var STORAGE_KEY = 'shuffle-works-theme';
  var root = document.documentElement;
  var toggle = document.getElementById('theme-toggle');

  function applyTheme(theme) {
    root.setAttribute('data-theme', theme);
    toggle.setAttribute('aria-pressed', String(theme === 'light'));
  }

  // The inline head script already set data-theme before first paint (avoids a
  // flash of the wrong theme); just sync the toggle button's aria-pressed to match.
  toggle.setAttribute('aria-pressed', String(root.getAttribute('data-theme') === 'light'));

  toggle.addEventListener('click', function () {
    var next = root.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
    try {
      localStorage.setItem(STORAGE_KEY, next);
    } catch (e) {}
    applyTheme(next);
  });

  // Scroll-reveal for project cards, skipped entirely when reduced motion is requested.
  var prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var revealTargets = document.querySelectorAll('[data-reveal]');

  if (prefersReducedMotion || !('IntersectionObserver' in window)) {
    revealTargets.forEach(function (el) { el.classList.add('is-visible'); });
    return;
  }

  var observer = new IntersectionObserver(
    function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.15 }
  );

  revealTargets.forEach(function (el) { observer.observe(el); });
})();
