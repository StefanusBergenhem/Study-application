// ============================================================
// wf architecture renderer — client-side
// Inlined into the rendered HTML; reads window.__SPEC__ for the
// node index used by hover preview, search, and backlinks.
// ============================================================

(function () {
  "use strict";

  const root = document.documentElement;
  const SPEC = window.__SPEC__ || { nodes: {}, kinds: {} };

  // ───── Theme toggle ─────
  function currentTheme() {
    return root.getAttribute("data-theme")
        || (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
  }
  function applyTheme(t) {
    root.setAttribute("data-theme", t);
    try { localStorage.setItem("wf-arch-theme", t); } catch (_) {}
    const dot = document.querySelector(".theme-toggle .dot");
    if (dot) dot.style.background = t === "dark" ? "#ece1cb" : "#1a1611";
    const label = document.querySelector(".theme-toggle .label");
    if (label) label.textContent = t === "dark" ? "Light mode" : "Dark mode";
    // Re-init mermaid with matching theme
    if (window.mermaid && window._mermaidRendered) {
      // Mermaid re-render is heavy; skip live re-theme — initial render uses neutral.
    }
  }
  try {
    const saved = localStorage.getItem("wf-arch-theme");
    if (saved) applyTheme(saved);
  } catch (_) {}
  const toggle = document.querySelector(".theme-toggle");
  if (toggle) {
    toggle.addEventListener("click", () => {
      applyTheme(currentTheme() === "dark" ? "light" : "dark");
    });
  }

  // ───── Hover preview popover ─────
  const popover = document.createElement("div");
  popover.className = "popover";
  popover.setAttribute("role", "tooltip");
  document.body.appendChild(popover);

  let hideTimer = null;
  function showPopover(target, id) {
    const node = SPEC.nodes[id];
    if (!node) return;
    const kindLabel = (SPEC.kinds[node.kind] || node.kind || "").toUpperCase();
    popover.innerHTML = "";
    if (kindLabel) {
      const k = document.createElement("div");
      k.className = "pop-kind";
      k.style.background = kindBg(node.kind);
      k.textContent = kindLabel;
      popover.appendChild(k);
    }
    const idEl = document.createElement("div");
    idEl.className = "pop-id";
    idEl.textContent = id;
    popover.appendChild(idEl);
    if (node.title) {
      const t = document.createElement("div");
      t.className = "pop-title";
      t.textContent = node.title;
      popover.appendChild(t);
    }
    if (node.summary) {
      const s = document.createElement("div");
      s.className = "pop-summary";
      s.textContent = node.summary;
      popover.appendChild(s);
    }
    const rect = target.getBoundingClientRect();
    const popH = 120; // rough estimate; we'll measure after paint
    popover.style.left = (window.scrollX + rect.left) + "px";
    popover.style.top  = (window.scrollY + rect.bottom + 6) + "px";
    popover.classList.add("show");
    // Re-measure & flip if overflowing viewport bottom
    requestAnimationFrame(() => {
      const pr = popover.getBoundingClientRect();
      if (pr.bottom > window.innerHeight - 8) {
        popover.style.top = (window.scrollY + rect.top - pr.height - 6) + "px";
      }
      if (pr.right > window.innerWidth - 8) {
        popover.style.left = (window.scrollX + window.innerWidth - pr.width - 8) + "px";
      }
    });
  }
  function hidePopover() {
    popover.classList.remove("show");
  }
  function kindBg(kind) {
    switch (kind) {
      case "sys-req": return "var(--moss)";
      case "req":     return "var(--accent)";
      case "adr":     return "var(--cobalt)";
      case "comp":    return "var(--ink-soft)";
      default:        return "var(--ink-mute)";
    }
  }

  document.body.addEventListener("mouseover", (e) => {
    const a = e.target.closest("a.ref");
    if (!a) return;
    const id = a.dataset.ref;
    if (!id) return;
    clearTimeout(hideTimer);
    showPopover(a, id);
  });
  document.body.addEventListener("mouseout", (e) => {
    const a = e.target.closest("a.ref");
    if (!a) return;
    hideTimer = setTimeout(hidePopover, 120);
  });
  document.body.addEventListener("focusin", (e) => {
    const a = e.target.closest("a.ref");
    if (a && a.dataset.ref) showPopover(a, a.dataset.ref);
  });
  document.body.addEventListener("focusout", () => { hideTimer = setTimeout(hidePopover, 120); });

  // ───── Copy anchor on heading click ─────
  document.querySelectorAll(".anchor-id").forEach((el) => {
    el.addEventListener("click", (e) => {
      const id = el.getAttribute("href");
      if (!id) return;
      // Default behaviour scrolls to #id; also copy a link to clipboard.
      try {
        const url = window.location.href.split("#")[0] + id;
        navigator.clipboard && navigator.clipboard.writeText(url);
        const orig = el.textContent;
        el.textContent = "copied ✓";
        setTimeout(() => { el.textContent = orig; }, 900);
      } catch (_) {}
    });
  });

  // ───── Search / filter ─────
  const search = document.querySelector(".rail .search input");
  const allEntries = Array.from(document.querySelectorAll("article.entry, .sub-entry"));
  function applyFilter(q) {
    q = (q || "").trim().toLowerCase();
    if (!q) {
      allEntries.forEach((el) => el.classList.remove("dimmed"));
      clearMarks();
      return;
    }
    allEntries.forEach((el) => {
      const hay = (el.dataset.searchText || el.textContent).toLowerCase();
      if (hay.indexOf(q) === -1) el.classList.add("dimmed");
      else el.classList.remove("dimmed");
    });
  }
  function clearMarks() {
    document.querySelectorAll("mark.highlight").forEach((m) => {
      const t = document.createTextNode(m.textContent);
      m.parentNode.replaceChild(t, m);
    });
  }
  if (search) {
    search.addEventListener("input", (e) => applyFilter(e.target.value));
    document.addEventListener("keydown", (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        search.focus();
        search.select();
      }
      if (e.key === "Escape" && document.activeElement === search) {
        search.value = "";
        applyFilter("");
        search.blur();
      }
    });
  }

  // ───── Active rail entry on scroll ─────
  const railLinks = Array.from(document.querySelectorAll(".rail a[href^='#']"));
  const targetIds = railLinks.map(a => a.getAttribute("href").slice(1));
  const targets = targetIds
    .map(id => document.getElementById(id))
    .filter(Boolean);
  const linkFor = new Map();
  railLinks.forEach((a) => linkFor.set(a.getAttribute("href").slice(1), a));

  if ("IntersectionObserver" in window && targets.length) {
    const obs = new IntersectionObserver((entries) => {
      // Pick the topmost intersecting target
      const visible = entries.filter(e => e.isIntersecting)
        .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
      if (visible.length) {
        railLinks.forEach(l => l.classList.remove("active"));
        const link = linkFor.get(visible[0].target.id);
        if (link) link.classList.add("active");
      }
    }, { rootMargin: "-20% 0px -65% 0px", threshold: 0 });
    targets.forEach(t => obs.observe(t));
  }

  // ───── Mermaid: click → anchor ─────
  if (window.mermaid) {
    window.mermaid.initialize({
      startOnLoad: false,
      theme: "neutral",
      fontFamily: "IBM Plex Sans, system-ui, sans-serif",
      flowchart: { curve: "basis", htmlLabels: true, useMaxWidth: true },
    });
    window.mermaid.run({ querySelector: ".mermaid" }).then(() => {
      window._mermaidRendered = true;
      // Mermaid renders <g class="node">; we wrap component labels with id="comp-X" via JS
      document.querySelectorAll(".diagram-wrap .node").forEach((g) => {
        const labelEl = g.querySelector(".nodeLabel, foreignObject span, text");
        const label = labelEl ? labelEl.textContent.trim() : null;
        if (!label) return;
        const anchor = "#comp-" + label.replace(/[^a-z0-9_-]/gi, "-").toLowerCase();
        g.style.cursor = "pointer";
        g.addEventListener("click", () => {
          window.location.hash = anchor;
        });
      });
    }).catch((err) => {
      console.warn("mermaid render failed", err);
    });
  }

})();
