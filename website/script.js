document.addEventListener("DOMContentLoaded", () => {
  requestAnimationFrame(() => {
    document.body.classList.add("is-loaded");
  });

  const revealElements = document.querySelectorAll(".reveal");
  const topbar = document.querySelector(".topbar");

  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(
      (entries, currentObserver) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) {
            return;
          }

          entry.target.classList.add("is-visible");
          currentObserver.unobserve(entry.target);
        });
      },
      {
        threshold: 0.18,
        rootMargin: "0px 0px -8% 0px",
      }
    );

    revealElements.forEach((element) => observer.observe(element));
  } else {
    revealElements.forEach((element) => element.classList.add("is-visible"));
  }

  const syncTopbar = () => {
    if (!topbar) {
      return;
    }

    topbar.classList.toggle("is-scrolled", window.scrollY > 10);
  };

  syncTopbar();
  window.addEventListener("scroll", syncTopbar, { passive: true });
});
