/* Enhancement only: all content and navigation also work without JavaScript. */
(() => {
  const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
  if ('IntersectionObserver' in window && !motion.matches) {
    const elements = [...document.querySelectorAll('[data-reveal]')];
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        observer.unobserve(entry.target);
      }
    }, { threshold: 0.08, rootMargin: '0px 0px 24px 0px' });
    document.documentElement.classList.add('motion-ready');
    elements.forEach(element => observer.observe(element));
    motion.addEventListener('change', event => {
      if (event.matches) {
        elements.forEach(element => element.classList.add('is-visible'));
        observer.disconnect();
      }
    });
  }
  // A linked answer opens before the browser scrolls it into view.
  const openAnswer = () => {
    const id = location.hash.slice(1);
    if (!id) return;
    const answer = document.getElementById(id);
    if (answer instanceof HTMLDetailsElement) answer.open = true;
  };
  openAnswer();
  window.addEventListener('hashchange', openAnswer);
})();
