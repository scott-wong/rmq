(function (window, document) {
  "use strict";

  var observedHeader = null;
  var resizeObserver =
    typeof window.ResizeObserver === "function"
      ? new window.ResizeObserver(updateHeaderOffset)
      : null;

  function updateHeaderOffset() {
    var header = document.getElementById("header");
    if (!header) return;
    var height = Math.ceil(header.getBoundingClientRect().height);
    if (height > 0) {
      document.documentElement.style.setProperty(
        "--rmq-header-height",
        height + "px",
      );
    }
  }

  function observeHeader() {
    var header = document.getElementById("header");
    if (header === observedHeader) {
      updateHeaderOffset();
      return;
    }
    if (resizeObserver && observedHeader) {
      resizeObserver.disconnect();
    }
    observedHeader = header;
    if (resizeObserver && header) {
      resizeObserver.observe(header);
    }
    updateHeaderOffset();
  }

  function initialize() {
    observeHeader();
    if (window.MutationObserver) {
      new window.MutationObserver(observeHeader).observe(document.body, {
        childList: true,
        subtree: true,
      });
    }
    window.addEventListener("resize", updateHeaderOffset);
    if (document.fonts && document.fonts.ready) {
      document.fonts.ready.then(updateHeaderOffset);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initialize);
  } else {
    initialize();
  }
})(window, document);
