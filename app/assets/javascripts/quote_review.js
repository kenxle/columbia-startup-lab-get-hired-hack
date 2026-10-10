(() => {
  let dirty = false;
  let generation = 0;
  let pending;
  let currentURL = window.location.href;
  const root = () => document.querySelector('[data-review-root]');
  const announce = (message) => {
    const status = document.querySelector('[data-review-status]');
    if (status) status.textContent = message;
  };
  const discardAllowed = () => !dirty || window.confirm('You have unsaved changes. Discard them and open another line?');

  function openDetail(scroll) {
    const review = root();
    if (!review) return;
    const detail = review.querySelector('#line-detail');
    const selected = review.querySelector('[data-review-row].is-selected');
    if (detail && selected) {
      const drawer = document.createElement('tr');
      drawer.className = 'review-detail-row';
      const cell = document.createElement('td');
      cell.colSpan = 6;
      cell.append(detail);
      drawer.append(cell);
      selected.after(drawer);
      if (scroll) {
        const heading = detail.querySelector('#line-detail-heading');
        heading?.focus({ preventScroll: true });
        (heading || detail).scrollIntoView({ block: 'start', behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth' });
      }
    }
    review.querySelectorAll('.source-text').forEach((source) => {
      const mark = source.querySelector('mark');
      if (mark) source.scrollTop += mark.getBoundingClientRect().top - source.getBoundingClientRect().top - 24;
    });
    if (scroll) announce(detail ? `${detail.querySelector('#line-detail-heading').textContent.trim()} opened. Original RFQ highlights updated.` : 'No lines in this view.');
  }

  async function navigate(url, fromHistory = false) {
    if (!discardAllowed()) {
      if (fromHistory) window.history.pushState({}, '', currentURL);
      return;
    }
    dirty = false;
    const request = ++generation;
    pending?.abort();
    pending = new AbortController();
    root()?.setAttribute('aria-busy', 'true');
    announce('Opening line…');
    try {
      const response = await fetch(url, { credentials: 'same-origin', headers: { Accept: 'text/html' }, signal: pending.signal });
      if (!response.ok || response.redirected) throw new Error('Navigation unavailable');
      const page = new DOMParser().parseFromString(await response.text(), 'text/html');
      if (request !== generation) return;
      const next = page.querySelector('[data-review-root]');
      if (!next || !root()) throw new Error('Review unavailable');
      // Inputs can change while the request is in flight. Check again before
      // replacing the review, including approval and buyer-answer forms.
      if (!discardAllowed()) {
        if (fromHistory) window.history.pushState({}, '', currentURL);
        announce('Unsaved changes kept.');
        return;
      }
      root().replaceWith(document.importNode(next, true));
      const summary = document.querySelector('.summary');
      const nextSummary = page.querySelector('.summary');
      if (summary && nextSummary) summary.replaceWith(document.importNode(nextSummary, true));
      if (!fromHistory) window.history.pushState({}, '', url);
      currentURL = url;
      dirty = false;
      openDetail(true);
    } catch (error) {
      if (error.name === 'AbortError' || request !== generation) return;
      // Full navigation remains available if enhancement or fetch fails.
      window.location.assign(url);
    } finally {
      if (request === generation) root()?.removeAttribute('aria-busy');
    }
  }

  document.addEventListener('click', (event) => {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    let link = event.target.closest('a[data-review-link]');
    if (!link && !event.target.closest('a, button, input, select, textarea, label') && !window.getSelection()?.toString()) {
      link = event.target.closest('[data-review-row]')?.querySelector('a[data-review-link]');
    }
    if (!link || !root()?.contains(link) || link.target || link.hasAttribute('download')) return;
    const url = new URL(link.href, window.location.href);
    if (url.origin !== window.location.origin || url.pathname !== window.location.pathname) return;
    event.preventDefault();
    navigate(url.href);
  });
  const markDirty = (event) => { if (event.target.closest('[data-review-root] form')) dirty = true; };
  document.addEventListener('input', markDirty);
  document.addEventListener('change', markDirty);
  document.addEventListener('submit', (event) => {
    if (event.target.closest('[data-review-root]')) {
      dirty = false;
      ++generation;
      pending?.abort();
    }
  });
  window.addEventListener('beforeunload', (event) => {
    if (dirty) { event.preventDefault(); event.returnValue = ''; }
  });
  window.addEventListener('popstate', () => {
    if (root() && new URL(currentURL).pathname === window.location.pathname) navigate(window.location.href, true);
  });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => openDetail(false), { once: true });
  else openDetail(false);
})();
