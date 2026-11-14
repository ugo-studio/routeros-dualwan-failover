(function () {
  // Copy buttons
  document.querySelectorAll(".code").forEach(function (block) {
    var btn = block.querySelector(".copy");
    var pre = block.querySelector("pre");
    btn.addEventListener("click", function () {
      var text = pre.innerText;
      var done = function (label) {
        btn.textContent = label;
        setTimeout(function () { btn.textContent = "Copy"; }, 1600);
      };
      var selectFallback = function () {
        var r = document.createRange();
        r.selectNodeContents(pre);
        var s = window.getSelection();
        s.removeAllRanges();
        s.addRange(r);
        done("Selected, press Ctrl+C");
      };
      try {
        navigator.clipboard.writeText(text).then(function () { done("Copied"); }, selectFallback);
      } catch (e) { selectFallback(); }
    });
  });

  // Contents: collapsed by default on narrow screens
  var toggle = document.getElementById("toc-toggle");
  var narrow = window.matchMedia("(max-width: 900px)");
  if (narrow.matches) toggle.open = false;
  document.querySelectorAll(".toc a").forEach(function (a) {
    a.addEventListener("click", function () { if (narrow.matches) toggle.open = false; });
  });

  // Highlight the current section
  var links = {};
  document.querySelectorAll(".toc a").forEach(function (a) { links[a.getAttribute("href").slice(1)] = a; });
  var heads = Array.prototype.filter.call(document.querySelectorAll(".doc h2[id]"), function (h) { return links[h.id]; });
  function mark() {
    var current = heads[0];
    for (var i = 0; i < heads.length; i++) {
      if (heads[i].getBoundingClientRect().top < 120) current = heads[i];
    }
    Object.keys(links).forEach(function (k) { links[k].classList.toggle("active", current && k === current.id); });
  }
  window.addEventListener("scroll", mark, { passive: true });
  mark();
})();
