/* ==========================================================
   L'AGENCE — interactions
   - bascule auto SVG -> Lottie si .json présent
   - copie de snippets code
   - onglets génériques (data-tab / data-config-tab / data-mcp-tab)
   - formulaire de configuration : génère commande shell + YAML
   ========================================================== */

(function () {
  "use strict";

  // ---------------------------------------------------------
  // 1. Lottie : tente de charger les .json déclarés. Sinon, on
  //    laisse le SVG fallback en place (déjà animé en CSS).
  // ---------------------------------------------------------
  function tryUpgradeAvatarsToLottie() {
    var holders = document.querySelectorAll(".avatar-lottie[data-lottie-src]");
    if (!holders.length) return;

    var srcs = Array.from(holders).map(function (h) {
      return h.getAttribute("data-lottie-src");
    });

    Promise.all(
      srcs.map(function (src) {
        return fetch(src, { method: "HEAD" })
          .then(function (r) { return r.ok ? src : null; })
          .catch(function () { return null; });
      })
    ).then(function (results) {
      var available = results.filter(Boolean);
      if (!available.length) return;

      var script = document.createElement("script");
      script.src = "https://unpkg.com/lottie-web@5.12.2/build/player/lottie.min.js";
      script.async = true;
      script.onload = function () { mountLotties(holders); };
      script.onerror = function () {
        console.warn("[L'Agence] Impossible de charger lottie-web — on garde les SVG.");
      };
      document.head.appendChild(script);
    });
  }

  function mountLotties(holders) {
    if (typeof window.lottie === "undefined") return;
    holders.forEach(function (holder) {
      var src = holder.getAttribute("data-lottie-src");
      fetch(src, { method: "HEAD" })
        .then(function (r) {
          if (!r.ok) return;
          holder.hidden = false;
          var avatar = holder.closest(".avatar");
          if (avatar) avatar.classList.add("is-lottie");
          window.lottie.loadAnimation({
            container: holder,
            path: src,
            renderer: "svg",
            loop: true,
            autoplay: true,
          });
        })
        .catch(function () { /* on garde le SVG */ });
    });
  }

  // ---------------------------------------------------------
  // 2. Copie de snippets via [data-copy-target]
  // ---------------------------------------------------------
  function bindCopyButtons() {
    document.querySelectorAll("[data-copy-target]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        var targetId = btn.getAttribute("data-copy-target");
        var target = document.getElementById(targetId);
        if (!target) return;
        var text = target.innerText || target.textContent || "";
        copyToClipboard(text).then(
          function () { flashCopied(btn); },
          function () { flashCopied(btn, true); }
        );
      });
    });
  }

  function copyToClipboard(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text);
    }
    return new Promise(function (resolve, reject) {
      try {
        var ta = document.createElement("textarea");
        ta.value = text;
        ta.style.position = "fixed";
        ta.style.opacity = "0";
        document.body.appendChild(ta);
        ta.select();
        document.execCommand("copy");
        document.body.removeChild(ta);
        resolve();
      } catch (e) { reject(e); }
    });
  }

  function flashCopied(btn, failed) {
    var original = btn.dataset.originalText || btn.innerText;
    btn.dataset.originalText = original;
    btn.innerText = failed ? "✗ Erreur" : "✓ Copié";
    btn.classList.add("is-copied");
    setTimeout(function () {
      btn.innerText = original;
      btn.classList.remove("is-copied");
    }, 1600);
  }

  // ---------------------------------------------------------
  // 3. Onglets génériques. Tout couple [data-X-tab] / [data-X-panel]
  //    sous un même conteneur fonctionne automatiquement.
  // ---------------------------------------------------------
  function bindTabsBy(tabAttr, panelAttr) {
    document.querySelectorAll("[" + tabAttr + "]").forEach(function (tab) {
      tab.addEventListener("click", function () {
        var key = tab.getAttribute(tabAttr);
        var tabsContainer = tab.parentElement;
        if (!tabsContainer) return;

        // Trouve la racine commune (la section qui contient à la fois
        // les tabs ET les panels). On remonte jusqu'au plus proche parent
        // qui contient des [panelAttr].
        var scope = tab.closest("section, .config-output, .tab-panel, body") || document;

        // Désactive les autres tabs au même niveau
        tabsContainer.querySelectorAll("[" + tabAttr + "]").forEach(function (t) {
          t.classList.remove("tab-active");
        });
        tab.classList.add("tab-active");

        // Active le panel correspondant DANS le même scope
        scope.querySelectorAll("[" + panelAttr + "]").forEach(function (panel) {
          // Ne touche que les panels du même niveau (mêmes attributs)
          if (panel.parentElement && panel.parentElement.contains(tab.parentElement)) {
            panel.hidden = panel.getAttribute(panelAttr) !== key;
          } else if (panel.closest("section, .config-output") === scope) {
            panel.hidden = panel.getAttribute(panelAttr) !== key;
          }
        });
      });
    });
  }

  // ---------------------------------------------------------
  // 4. Générateur de configuration BugHound
  //    Tout est calculé côté navigateur — aucun appel réseau.
  // ---------------------------------------------------------
  var INSTALL_URL = "https://slama-consulting.github.io/agence/install.sh";

  function bindConfigGenerator() {
    var form = document.getElementById("config-form");
    if (!form) return;

    var modeRadios = form.querySelectorAll("input[name='jira_mode']");
    var emailField = document.getElementById("email_field");

    function refreshEmailVisibility() {
      var mode = getSelectedMode();
      if (emailField) emailField.hidden = mode !== "api";
    }
    modeRadios.forEach(function (r) {
      r.addEventListener("change", refreshEmailVisibility);
    });
    refreshEmailVisibility();

    form.addEventListener("submit", function (ev) {
      ev.preventDefault();
      var values = readForm();
      if (!validate(values, form)) return;
      renderOutput(values);
    });

    form.addEventListener("reset", function () {
      var output = document.getElementById("config-output");
      if (output) output.hidden = true;
      // L'email reset ne déclenche pas auto le change → on rappelle
      setTimeout(refreshEmailVisibility, 0);
    });

    var dlBtn = document.getElementById("download-yaml-btn");
    if (dlBtn) {
      dlBtn.addEventListener("click", function () {
        var values = readForm();
        if (!validate(values, form)) return;
        downloadYaml(values);
      });
    }
  }

  function getSelectedMode() {
    var checked = document.querySelector("input[name='jira_mode']:checked");
    return checked ? checked.value : "browser";
  }

  function readForm() {
    var urlInput = document.getElementById("jira_url");
    var emailInput = document.getElementById("jira_email");
    return {
      mode: getSelectedMode(),
      url: (urlInput && urlInput.value || "").trim().replace(/\/+$/, ""),
      email: (emailInput && emailInput.value || "").trim(),
    };
  }

  function validate(values, form) {
    var urlInput = document.getElementById("jira_url");
    var hint = document.getElementById("jira_url_hint");
    var ok = true;

    if (!values.url || !/^https?:\/\/[^\s]+$/i.test(values.url)) {
      urlInput.classList.add("field-error");
      if (hint) {
        hint.textContent = "Veuillez saisir une URL complète (https://…).";
        hint.classList.add("hint-error");
      }
      ok = false;
    } else {
      urlInput.classList.remove("field-error");
      if (hint) {
        hint.innerHTML = "L'URL d'accueil de votre Jira (sans <code>/browse</code>, sans clé de ticket).";
        hint.classList.remove("hint-error");
      }
    }

    if (values.mode === "api") {
      var emailInput = document.getElementById("jira_email");
      if (!values.email || !/.+@.+\..+/.test(values.email)) {
        emailInput.classList.add("field-error");
        ok = false;
      } else {
        emailInput.classList.remove("field-error");
      }
    }
    return ok;
  }

  // ---------------------------------------------------------
  // 5. Rendu : commande shell + YAML
  // ---------------------------------------------------------
  function renderOutput(values) {
    var installCmd = buildInstallCommand(values);
    var yaml = buildConfigYaml(values);

    setText("install-cmd", installCmd);
    setText("config-yaml", yaml);

    var output = document.getElementById("config-output");
    if (output) {
      output.hidden = false;
      output.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }

  function setText(id, text) {
    var el = document.getElementById(id);
    if (el) el.textContent = text;
  }

  function shellQuote(value) {
    // Échappe les apostrophes pour un littéral entre simples quotes
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
  }

  function buildInstallCommand(values) {
    // ⚠️ Les variables doivent être attachées au *bash* à droite du pipe,
    //    pas au *curl* à gauche : sinon install.sh ne les voit pas.
    var envParts = [
      "JIRA_URL=" + shellQuote(values.url),
      "JIRA_MODE=" + shellQuote(values.mode),
    ];
    if (values.mode === "api" && values.email) {
      envParts.push("JIRA_EMAIL=" + shellQuote(values.email));
    }
    return [
      "curl -fsSL " + INSTALL_URL + " \\",
      "  | " + envParts.join(" ") + " bash",
    ].join("\n");
  }

  function buildConfigYaml(values) {
    var header = [
      "# Configuration BugHound — générée par L'Agence",
      "# Fichier à déposer dans : ~/.bughound/config.yaml",
      "# Les secrets (token, mot de passe) restent dans ~/.bughound/.env",
      "",
    ];

    var jiraBlock;
    if (values.mode === "browser") {
      jiraBlock = [
        "jira:",
        "  mode: browser",
        "  base_url: " + values.url,
        "  browser_profile_dir: ~/.bughound/chrome-profile",
        "  browser_headless_after_login: false",
        "  write_allowed_projects: []",
      ];
    } else {
      jiraBlock = [
        "jira:",
        "  mode: api",
        "  base_url: " + values.url,
        "  email: " + (values.email || "<votre-email>"),
        "  api_token: null  # défini via JIRA_API_TOKEN dans ~/.bughound/.env",
        "  write_allowed_projects: []",
      ];
    }

    var llmBlock = [
      "",
      "llm:",
      "  # Le LLM est routé via votre client MCP (Claude Code, Copilot, Cursor).",
      "  # Les paramètres ci-dessous ne sont utilisés qu'en mode CLI direct.",
      "  provider: copilot",
      "",
      "artifactory:",
      "  # Optionnel : si vos pièces jointes Jira sont sur un Artifactory privé,",
      "  # ajoutez ici une entrée par hôte. Les credentials vont dans ~/.bughound/.env",
      "  hosts: []",
    ];

    return header.concat(jiraBlock).concat(llmBlock).join("\n") + "\n";
  }

  function downloadYaml(values) {
    var content = buildConfigYaml(values);
    var blob = new Blob([content], { type: "text/yaml;charset=utf-8" });
    var url = URL.createObjectURL(blob);
    var a = document.createElement("a");
    a.href = url;
    a.download = "config.yaml";
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }

  // ---------------------------------------------------------
  // 6. Boot
  // ---------------------------------------------------------
  document.addEventListener("DOMContentLoaded", function () {
    bindCopyButtons();
    bindTabsBy("data-tab", "data-panel");
    bindTabsBy("data-config-tab", "data-config-panel");
    bindTabsBy("data-mcp-tab", "data-mcp-panel");
    bindConfigGenerator();
    tryUpgradeAvatarsToLottie();
  });
})();
