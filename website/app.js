const githubLink = document.querySelector("[data-github-link]");

if (githubLink && window.location.hostname.endsWith("netlify.app")) {
  githubLink.setAttribute("href", "https://github.com/");
}
