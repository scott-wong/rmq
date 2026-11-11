(function (window, document) {
  "use strict";

  var STORAGE_KEY = "rmq-language";
  var SUPPORTED = ["zh-CN", "en-US"];
  var DEFAULT_LANGUAGE = "zh-CN";
  var catalogs = window.RMQ_LOCALES || {};

  function normalizeLanguage(value) {
    if (!value) return null;
    var lowered = String(value).toLowerCase();
    if (lowered === "zh" || lowered === "zh-cn" || lowered === "zh-hans") {
      return "zh-CN";
    }
    if (lowered === "en" || lowered === "en-us") {
      return "en-US";
    }
    return null;
  }

  function queryLanguage() {
    try {
      return normalizeLanguage(
        new URL(window.location.href).searchParams.get("lang"),
      );
    } catch (_error) {
      return null;
    }
  }

  function storedLanguage() {
    try {
      return normalizeLanguage(window.localStorage.getItem(STORAGE_KEY));
    } catch (_error) {
      return null;
    }
  }

  var language = queryLanguage() || storedLanguage() || DEFAULT_LANGUAGE;

  function interpolate(text, variables) {
    if (!variables) return text;
    return text.replace(/\{([A-Za-z0-9_]+)\}/g, function (match, name) {
      return Object.prototype.hasOwnProperty.call(variables, name)
        ? String(variables[name])
        : match;
    });
  }

  function t(source, variables) {
    var catalog = catalogs[language] || {};
    var translated = Object.prototype.hasOwnProperty.call(catalog, source)
      ? catalog[source]
      : source;
    return interpolate(translated, variables);
  }

  function selectHtml() {
    function option(value, label) {
      var selected = language === value ? " selected" : "";
      return (
        '<option value="' +
        value +
        '"' +
        selected +
        ">" +
        label +
        "</option>"
      );
    }
    return (
      '<label class="rmq-language-control">' +
      '<span class="rmq-language-label">' +
      t("Language") +
      "</span>" +
      '<select data-rmq-language aria-label="' +
      t("Language") +
      '">' +
      option("zh-CN", "中文") +
      option("en-US", "English") +
      "</select>" +
      "</label>"
    );
  }

  function setLanguage(nextLanguage) {
    var normalized = normalizeLanguage(nextLanguage) || DEFAULT_LANGUAGE;
    try {
      window.localStorage.setItem(STORAGE_KEY, normalized);
    } catch (_error) {
      // The URL remains authoritative when storage is unavailable.
    }
    var url;
    try {
      url = new URL(window.location.href);
    } catch (_error) {
      window.location.reload();
      return;
    }
    url.searchParams.set("lang", normalized);
    window.location.assign(url.toString());
  }

  function applyDocumentLanguage() {
    document.documentElement.lang = language;
    if (!document.title || document.title === "RMQ") {
      document.title = t("RMQ Management Console");
    }
  }

  document.addEventListener("change", function (event) {
    var target = event.target;
    if (target && target.matches && target.matches("[data-rmq-language]")) {
      setLanguage(target.value);
    }
  });

  window.rmqI18n = {
    language: language,
    supported: SUPPORTED.slice(),
    t: t,
    selectHtml: selectHtml,
    setLanguage: setLanguage,
  };
  window.t = t;

  applyDocumentLanguage();
  document.addEventListener("DOMContentLoaded", applyDocumentLanguage);
})(window, document);
