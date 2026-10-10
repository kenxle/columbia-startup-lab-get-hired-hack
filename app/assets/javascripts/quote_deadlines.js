(() => {
  const duration = (minutes) => `${Math.floor(minutes / 60)}h ${String(minutes % 60).padStart(2, "0")}m`;

  const refreshDeadlines = () => {
    const now = Date.now();
    document.querySelectorAll('[data-quote-deadline="due"]').forEach((badge) => {
      const due = Date.parse(badge.dataset.deadlineAt);
      if (!Number.isFinite(due)) return;

      const remaining = due - now;
      const overdue = remaining <= 0;
      const minutes = overdue ? Math.floor(-remaining / 60000) : Math.ceil(remaining / 60000);
      const state = overdue ? "overdue" : remaining < 8 * 60 * 60 * 1000 ? "soon" : "calm";
      badge.textContent = `${overdue ? "Overdue by" : "Due in"} ${duration(minutes)}`;
      ["calm", "soon", "overdue"].forEach((value) => badge.classList.toggle(`deadline--${value}`, value === state));
    });
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", refreshDeadlines, { once: true });
  } else {
    refreshDeadlines();
  }
  window.setInterval(refreshDeadlines, 60000);
})();
