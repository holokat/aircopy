// AirCopy marketing site — vanilla JS (ported from the design DC logic class).
(function () {
  function init() {
    const root = document;

    // --- scroll reveals ---
    try {
      const io = new IntersectionObserver((entries) => {
        entries.forEach((e) => {
          if (e.isIntersecting) {
            const el = e.target;
            const d = +(el.dataset.delay || 0);
            setTimeout(() => { el.style.opacity = '1'; el.style.transform = 'none'; }, d);
            io.unobserve(el);
          }
        });
      }, { threshold: 0.1, rootMargin: '0px 0px -7% 0px' });
      root.querySelectorAll('[data-reveal]').forEach((el) => io.observe(el));
      // safety: reveal everything after 3.5s in case observer misfires
      setTimeout(() => root.querySelectorAll('[data-reveal]').forEach((el) => { el.style.opacity = '1'; el.style.transform = 'none'; }), 3500);
    } catch (e) {}

    // --- hero word reveal ---
    try {
      const words = [...root.querySelectorAll('[data-word]')];
      words.forEach((w, i) => {
        w.style.opacity = '0';
        w.style.transform = 'translateY(26px) rotate(1.5deg)';
        w.style.transition = 'opacity .8s cubic-bezier(.16,1,.3,1),transform .8s cubic-bezier(.16,1,.3,1)';
        setTimeout(() => { w.style.opacity = '1'; w.style.transform = 'none'; }, 140 + i * 65);
      });
    } catch (e) {}

    // --- typed mono line ---
    try {
      const el = root.getElementById('typed');
      if (el) {
        const full = el.dataset.text || '';
        el.textContent = '';
        let i = 0;
        const tick = () => {
          if (i <= full.length) { el.textContent = full.slice(0, i); i++; setTimeout(tick, 42 + Math.random() * 45); }
        };
        setTimeout(tick, 820);
      }
    } catch (e) {}

    // --- nav island on scroll ---
    try {
      const island = root.getElementById('navIsland');
      const onScroll = () => {
        const s = window.scrollY > 24;
        if (s) {
          island.style.maxWidth = '1140px';
          island.style.marginTop = '12px';
          island.style.padding = '11px 26px';
          island.style.background = 'rgba(251,251,253,.82)';
          island.style.borderColor = 'rgba(20,20,30,.09)';
          island.style.backdropFilter = 'saturate(180%) blur(20px)';
          island.style.webkitBackdropFilter = 'saturate(180%) blur(20px)';
        } else {
          island.style.maxWidth = '1140px';
          island.style.marginTop = '0px';
          island.style.padding = '16px 0';
          island.style.background = 'rgba(251,251,253,0)';
          island.style.borderColor = 'rgba(20,20,30,0)';
          island.style.backdropFilter = 'none';
          island.style.webkitBackdropFilter = 'none';
        }
      };
      window.addEventListener('scroll', onScroll, { passive: true });
      onScroll();
    } catch (e) {}

    // --- feature illustration hover ---
    try {
      root.querySelectorAll('[data-feat]').forEach((cell) => {
        const card = cell.querySelector('[data-card]');
        cell.addEventListener('mouseenter', () => {
          if (card) { card.style.transform = 'translateY(-5px)'; card.style.borderColor = 'rgba(10,108,255,.28)'; }
        });
        cell.addEventListener('mouseleave', () => {
          if (card) { card.style.transform = 'none'; card.style.borderColor = 'rgba(20,20,30,.08)'; }
        });
      });
    } catch (e) {}

    // --- hero mock parallax ---
    try {
      const mock = root.getElementById('mock');
      if (mock && window.matchMedia('(pointer:fine)').matches) {
        window.addEventListener('mousemove', (ev) => {
          const dx = (ev.clientX - window.innerWidth / 2) / (window.innerWidth / 2);
          const dy = (ev.clientY - window.innerHeight / 2) / (window.innerHeight / 2);
          mock.style.transform = `translate(${dx * -9}px,${dy * -7}px) rotateX(${dy * 2.5}deg) rotateY(${dx * -3.5}deg)`;
        });
      }
    } catch (e) {}

    // --- magnetic tilt clip cards ---
    try {
      root.querySelectorAll('[data-tilt]').forEach((card) => {
        card.addEventListener('mousemove', (ev) => {
          const r = card.getBoundingClientRect();
          const px = (ev.clientX - r.left) / r.width - 0.5;
          const py = (ev.clientY - r.top) / r.height - 0.5;
          card.style.transform = `translateY(-2px) rotateX(${py * -7}deg) rotateY(${px * 9}deg)`;
        });
        card.addEventListener('mouseleave', () => { card.style.transform = 'none'; });
      });
    } catch (e) {}

    // --- live demo ---
    try { setupDemo(root); } catch (e) {}

    // --- easter egg: cmd C / cmd V toast ---
    try {
      const toast = root.getElementById('toast');
      let tt;
      const show = (msg, color) => {
        if (!toast) return;
        const inner = toast.firstElementChild; // span wrapper
        const dot = inner.firstElementChild;
        dot.style.background = color; dot.style.boxShadow = '0 0 8px ' + color;
        inner.childNodes[1].textContent = msg;
        toast.style.opacity = '1'; toast.style.transform = 'translate(-50%,0)';
        clearTimeout(tt);
        tt = setTimeout(() => { toast.style.opacity = '0'; toast.style.transform = 'translate(-50%,12px)'; }, 1700);
      };
      window.addEventListener('keydown', (ev) => {
        const k = ev.key.toLowerCase();
        if ((ev.metaKey || ev.ctrlKey) && k === 'c') show('Copied to AirCopy', '#0A6CFF');
        if ((ev.metaKey || ev.ctrlKey) && k === 'v') show('Pasted from AirCopy', '#22c55e');
      });
    } catch (e) {}
  }

  function setupDemo(root) {
    const path = root.getElementById('demoPath');
    const packet = root.getElementById('packet');
    const btn = root.getElementById('copyBtn');
    const drop = root.getElementById('dropZone');
    const dropChip = root.getElementById('dropChip');
    const dropEmpty = root.getElementById('dropEmpty');
    const dropMeta = root.getElementById('dropMeta');
    const reset = root.getElementById('resetBtn');
    if (!path || !packet || !btn) return;
    let busy = false, done = false;

    const run = () => {
      if (busy || done) return;
      busy = true;
      btn.textContent = 'Syncing…';
      const L = path.getTotalLength();
      packet.style.opacity = '1';
      const t0 = performance.now(), dur = 950;
      const step = (now) => {
        const p = Math.min(1, (now - t0) / dur);
        const e = p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2;
        const pt = path.getPointAtLength(e * L);
        packet.setAttribute('transform', `translate(${pt.x},${pt.y})`);
        if (p < 1) requestAnimationFrame(step);
        else {
          packet.style.opacity = '0';
          dropEmpty.style.display = 'none';
          dropChip.style.position = 'static';
          dropChip.style.opacity = '1';
          dropChip.style.transform = 'scale(1)';
          drop.style.borderColor = 'rgba(10,108,255,.4)';
          drop.style.borderStyle = 'solid';
          drop.style.background = 'rgba(10,108,255,.04)';
          dropMeta.style.opacity = '1';
          btn.textContent = 'Synced ✓';
          btn.style.background = '#22c55e';
          busy = false; done = true;
        }
      };
      requestAnimationFrame(step);
    };

    const doReset = () => {
      done = false; busy = false;
      dropChip.style.opacity = '0';
      dropChip.style.transform = 'scale(.9)';
      dropChip.style.position = 'absolute';
      dropEmpty.style.display = 'block';
      dropMeta.style.opacity = '0';
      drop.style.borderColor = 'rgba(20,20,30,.12)';
      drop.style.borderStyle = 'dashed';
      drop.style.background = 'transparent';
      btn.textContent = 'Copy & sync';
      btn.style.background = '#0A6CFF';
    };

    btn.addEventListener('click', run);
    if (reset) reset.addEventListener('click', doReset);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
