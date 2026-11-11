(function () {
  "use strict";

  var BASE = (function () {
    var marker = document.body.getAttribute("data-base") || "/warden";
    while (marker.endsWith("/")) {
      marker = marker.slice(0, -1);
    }
    if (!marker.startsWith("/")) {
      marker = "/" + marker;
    }
    return marker;
  })();

  var VIEWS = ["overview", "services", "metrics", "proxies", "singbox", "backups", "audit", "settings"];
  var KIND_LABEL = { docker: "Docker 容器", systemd: "systemd 服务", singbox: "sing-box 实例" };
  var ACTION_LABEL = {
    start: "启动", stop: "停止", restart: "重启",
    test: "测试配置", reload: "重载配置", check: "检查配置"
  };
  var AUDIT_LABEL = {
    login: "登录", logout: "退出", action: "服务操作", "key-change": "修改密钥",
    reauth: "验证密钥", "backup-create": "创建备份", "backup-delete": "删除备份",
    "backup-download": "下载备份", "cert-dry-run": "证书检查",
    "singbox-reveal": "查看连接信息", alert: "状态告警"
  };
  var state = {
    authenticated: false,
    csrf: "",
    session: null,
    view: "overview",
    overview: null,
    services: null,
    metrics: null,
    metricHours: 24,
    proxies: null,
    singbox: null,
    backups: null,
    audit: null,
    auditQuery: "",
    settings: null,
    timer: null
  };

  function byId(id) {
    return document.getElementById(id);
  }

  function append(node, children) {
    var list = children.flat(Infinity);
    for (var index = 0; index < list.length; index += 1) {
      var child = list[index];
      if (child === null || child === undefined || child === false) {
        continue;
      }
      node.appendChild(child instanceof Node ? child : document.createTextNode(String(child)));
    }
  }

  function h(tag, attrs) {
    var node = document.createElement(tag);
    var attributes = attrs || {};
    var keys = Object.keys(attributes);
    for (var index = 0; index < keys.length; index += 1) {
      var key = keys[index];
      var value = attributes[key];
      if (value === null || value === undefined || value === false) {
        continue;
      }
      if (key === "class") {
        node.className = value;
      } else if (key === "text") {
        node.textContent = value;
      } else if (key === "dataset") {
        var names = Object.keys(value);
        for (var dataIndex = 0; dataIndex < names.length; dataIndex += 1) {
          node.dataset[names[dataIndex]] = value[names[dataIndex]];
        }
      } else if (key.startsWith("on") && typeof value === "function") {
        node.addEventListener(key.slice(2).toLowerCase(), value);
      } else if (key === "value") {
        node.value = value;
      } else if (key === "checked") {
        node.checked = Boolean(value);
      } else if (key === "disabled") {
        node.disabled = Boolean(value);
      } else {
        node.setAttribute(key, value === true ? "" : String(value));
      }
    }
    append(node, Array.prototype.slice.call(arguments, 2));
    return node;
  }

  function setText(id, value) {
    var node = byId(id);
    if (node) {
      node.textContent = value;
    }
  }

  function button(label, className, onClick, extra) {
    var attrs = Object.assign({ class: "btn " + (className || ""), type: "button" }, extra || {});
    if (onClick) {
      attrs.onclick = onClick;
    }
    return h("button", attrs, label);
  }

  function pageHead(title, subtitle, actions) {
    return h("header", { class: "page-head" },
      h("div", {},
        h("p", { class: "eyebrow" }, "NODE WARDEN"),
        h("h1", { class: "page-title" }, title),
        subtitle ? h("p", { class: "page-sub" }, subtitle) : null
      ),
      actions && actions.length ? h("div", { class: "page-actions" }, actions) : null
    );
  }

  function emptyBlock(title, text) {
    return h("div", { class: "empty" },
      h("div", { class: "empty-mark" }, "—"),
      h("div", { class: "empty-title" }, title),
      text ? h("div", { class: "empty-text" }, text) : null
    );
  }

  function skeleton(container) {
    var body = h("div", { class: "skeleton" },
      h("div", { class: "sk-line w40" }), h("div", { class: "sk-line w70" }),
      h("div", { class: "sk-line w25" }), h("div", { class: "sk-line w70" }),
      h("div", { class: "sk-line w40" })
    );
    container.replaceChildren(body);
  }

  function errorState(container, message, retry) {
    var body = h("div", { class: "empty" },
      h("div", { class: "empty-mark" }, "!"),
      h("div", { class: "empty-title" }, "加载失败"),
      h("div", { class: "empty-text" }, message || "请检查服务连接后重试"),
      retry ? h("div", { class: "form-actions" }, button("重试", "btn-sm", retry)) : null
    );
    container.replaceChildren(body);
  }

  function pad2(value) {
    return value < 10 ? "0" + value : String(value);
  }

  function formatDate(value) {
    if (!value) {
      return "—";
    }
    var date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return String(value);
    }
    return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate()) +
      " " + pad2(date.getHours()) + ":" + pad2(date.getMinutes()) + ":" + pad2(date.getSeconds());
  }

  function formatClock(value) {
    if (!value) {
      return "—";
    }
    var date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return "—";
    }
    return pad2(date.getHours()) + ":" + pad2(date.getMinutes());
  }

  function formatBytes(value) {
    var bytes = Number(value);
    if (!Number.isFinite(bytes) || bytes < 0) {
      return "—";
    }
    var units = ["B", "KB", "MB", "GB", "TB"];
    var index = 0;
    while (bytes >= 1024 && index < units.length - 1) {
      bytes = bytes / 1024;
      index += 1;
    }
    var digits = index === 0 ? 0 : 1;
    return bytes.toFixed(digits) + " " + units[index];
  }

  function formatDuration(seconds) {
    var total = Number(seconds);
    if (!Number.isFinite(total) || total < 0) {
      return "—";
    }
    total = Math.floor(total);
    var days = Math.floor(total / 86400);
    var hours = Math.floor((total % 86400) / 3600);
    var minutes = Math.floor((total % 3600) / 60);
    var parts = [];
    if (days) {
      parts.push(days + " 天");
    }
    if (hours) {
      parts.push(hours + " 小时");
    }
    if (!days && minutes) {
      parts.push(minutes + " 分钟");
    }
    if (!parts.length) {
      return "少于 1 分钟";
    }
    return parts.join(" ");
  }

  function uptimeValue(seconds) {
    var total = Number(seconds);
    if (!Number.isFinite(total) || total < 0) {
      return { value: "—", suffix: "" };
    }
    var days = Math.floor(total / 86400);
    if (days > 0) {
      return { value: String(days), suffix: "天" };
    }
    var hours = Math.floor(total / 3600);
    if (hours > 0) {
      return { value: String(hours), suffix: "小时" };
    }
    return { value: String(Math.floor(total / 60)), suffix: "分钟" };
  }

  function clip(value, limit) {
    var text = value === null || value === undefined ? "" : String(value);
    return text.length > limit ? text.slice(0, limit) + "..." : text;
  }

  function percentClass(value) {
    var number = Number(value);
    if (!Number.isFinite(number)) {
      number = 0;
    }
    number = Math.max(0, Math.min(100, number));
    return "pct-" + (Math.round(number / 5) * 5);
  }

  function percentTone(value) {
    var number = Number(value);
    if (number >= 90) {
      return "danger";
    }
    if (number >= 75) {
      return "warn";
    }
    return "";
  }

  function serviceState(row) {
    if (!row || !row.status || !row.status.active) {
      return { tone: "down", label: "未运行", detail: (row && row.status && row.status.detail) || "服务未运行" };
    }
    if (!row.health || !row.health.ok) {
      return { tone: "warn", label: "运行异常", detail: (row && row.health && row.health.detail) || "健康检查未通过" };
    }
    return { tone: "up", label: "运行中", detail: (row.status && row.status.detail) || "运行正常" };
  }

  function isRowUp(row) {
    return serviceState(row).tone === "up";
  }

  function statusPill(tone, label) {
    return h("span", { class: "status-pill " + tone }, h("i", {}), label);
  }

  function metaItem(label, value) {
    var text = value === null || value === undefined || value === "" ? "—" : String(value);
    return h("div", { class: "meta-item" },
      h("span", { class: "meta-label" }, label),
      h("span", { class: "meta-value", title: text }, text)
    );
  }

  function kv(label, value) {
    var text = value === null || value === undefined || value === "" ? "—" : String(value);
    return h("div", { class: "kv" }, h("span", {}, label), h("b", { title: text }, text));
  }

  function infoList(rows) {
    return h("div", { class: "info-list" }, rows.map(function (row) {
      return h("div", { class: "info-row" }, h("span", {}, row[0]), h("b", {}, row[1]));
    }));
  }

  function metricChip(label, value) {
    return h("span", { class: "metric-chip" }, label + " ", h("b", {}, value || "—"));
  }

  function actionLabel(action) {
    return ACTION_LABEL[action] || action;
  }

  function auditLabel(action) {
    return AUDIT_LABEL[action] || action;
  }

  function endpoint(path) {
    return BASE + path;
  }

  function setConnected(ok) {
    var node = byId("conn");
    if (!node) {
      return;
    }
    node.classList.toggle("is-bad", !ok);
    var label = node.querySelector("span");
    if (label) {
      label.textContent = ok ? "已连接" : "连接中断";
    }
  }

  async function api(path, options) {
    var opts = options || {};
    var method = opts.method || "GET";
    var headers = { Accept: "application/json" };
    if (opts.body !== undefined) {
      headers["Content-Type"] = "application/json";
    }
    if (method !== "GET" && method !== "HEAD" && state.csrf) {
      headers["X-CSRF-Token"] = state.csrf;
    }
    var controller = new AbortController();
    var timeout = setTimeout(function () {
      controller.abort();
    }, opts.timeout || 45000);
    var response;
    try {
      response = await fetch(endpoint(path), {
        method: method,
        headers: headers,
        credentials: "same-origin",
        cache: "no-store",
        body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
        signal: controller.signal
      });
    } catch (error) {
      setConnected(false);
      if (error && error.name === "AbortError") {
        throw new Error("请求超时，请稍后重试");
      }
      throw new Error("无法连接到面板服务");
    } finally {
      clearTimeout(timeout);
    }
    setConnected(true);
    var data = null;
    var contentType = response.headers.get("content-type") || "";
    if (contentType.indexOf("application/json") >= 0) {
      try {
        data = await response.json();
      } catch (error) {
        data = null;
      }
    }
    if (response.status === 401 && !opts.allow401 && state.authenticated) {
      showLogin(true);
      throw new Error("登录已过期，请重新登录");
    }
    if (!response.ok) {
      throw new Error((data && data.error) || "请求失败（HTTP " + response.status + "）");
    }
    return data;
  }

  function toast(message, tone) {
    var stack = byId("toasts");
    if (!stack) {
      return;
    }
    var item = h("div", { class: "toast " + (tone || "") },
      h("span", { class: "toast-mark" }, tone === "err" ? "!" : "i"),
      h("span", {}, message)
    );
    stack.appendChild(item);
    while (stack.children.length > 4) {
      stack.removeChild(stack.firstChild);
    }
    setTimeout(function () {
      if (item.parentNode) {
        item.parentNode.removeChild(item);
      }
    }, tone === "err" ? 7000 : 4000);
  }

  async function copyText(value) {
    try {
      await navigator.clipboard.writeText(value);
      toast("已复制", "ok");
    } catch (error) {
      toast("复制失败，请手动选择文本后复制", "err");
    }
  }

  function openModal(title, body, footer) {
    var modal = byId("modal");
    setText("modal-title", title);
    var bodyNode = byId("modal-body");
    if (bodyNode) {
      bodyNode.replaceChildren();
      append(bodyNode, [body]);
    }
    var footNode = byId("modal-foot");
    if (footNode) {
      footNode.replaceChildren();
      append(footNode, footer || []);
      footNode.hidden = !(footer && footer.length);
    }
    if (modal) {
      modal.hidden = false;
    }
    var target = byId("modal-body") ? byId("modal-body").querySelector("input, select, textarea, button") : null;
    if (target) {
      setTimeout(function () {
        target.focus();
      }, 30);
    }
  }

  function closeModal() {
    var modal = byId("modal");
    if (modal) {
      modal.hidden = true;
    }
  }

  function confirmAction(title, message, run) {
    var cancel = button("取消", "btn-quiet", closeModal);
    var accept = button("确定", "btn-danger", async function () {
      closeModal();
      await run();
    });
    openModal(title, h("p", { class: "modal-hint" }, message), [cancel, accept]);
  }

  function openOutputModal(title, output, ok) {
    var body = h("div", {},
      h("p", { class: "modal-hint" }, ok ? "操作执行成功。" : "操作执行失败。"),
      h("pre", { class: "log-output", tabindex: "0" }, output || "无输出")
    );
    openModal(title, body, [button("关闭", "btn-quiet", closeModal)]);
  }

  function setLoginError(message) {
    var node = byId("login-error");
    if (!node) {
      return;
    }
    node.textContent = message || "";
    node.hidden = !message;
  }

  function applySession(session) {
    state.authenticated = true;
    state.session = session;
    state.csrf = session.csrf || "";
    setText("version", session.version ? "v" + session.version : "v—");
    setText("login-version", session.version ? "v" + session.version : "v—");
  }

  function showLogin(expired) {
    state.authenticated = false;
    state.csrf = "";
    state.session = null;
    stopTimer();
    var app = byId("app");
    var login = byId("login");
    if (app) {
      app.hidden = true;
    }
    if (login) {
      login.hidden = false;
    }
    var key = byId("login-key");
    if (key) {
      key.value = "";
    }
    setLoginError(expired ? "登录已过期，请重新登录" : "");
    setTimeout(function () {
      if (key) {
        key.focus();
      }
    }, 30);
  }

  async function showApp() {
    var login = byId("login");
    var app = byId("app");
    if (login) {
      login.hidden = true;
    }
    if (app) {
      app.hidden = false;
    }
    updateTop();
    startTimer();
    var target = readHash() || "overview";
    await navigate(target, false);
  }

  async function onLogin(event) {
    event.preventDefault();
    var input = byId("login-key");
    var submit = byId("login-submit");
    var key = input ? input.value.trim() : "";
    if (!key) {
      setLoginError("请输入访问密钥");
      return;
    }
    setLoginError("");
    if (submit) {
      submit.disabled = true;
      submit.textContent = "登录中...";
    }
    try {
      var session = await api("/api/login", { method: "POST", body: { key: key }, allow401: true });
      applySession(session);
      if (input) {
        input.value = "";
      }
      await showApp();
    } catch (error) {
      setLoginError(error.message);
    } finally {
      if (submit) {
        submit.disabled = false;
        submit.textContent = "登录";
      }
    }
  }

  async function logout() {
    try {
      await api("/api/logout", { method: "POST", body: {} });
    } catch (error) {
      // The local session is cleared even when the server is unreachable.
    }
    state.overview = null;
    state.services = null;
    state.metrics = null;
    state.proxies = null;
    state.singbox = null;
    state.backups = null;
    state.audit = null;
    state.settings = null;
    state.auditQuery = "";
    showLogin(false);
    toast("已退出登录", "ok");
  }

  function readHash() {
    var value = location.hash ? location.hash.slice(1) : "";
    if (value.startsWith("/")) {
      value = value.slice(1);
    }
    return VIEWS.indexOf(value) >= 0 ? value : "";
  }

  function updateViewClasses() {
    var navItems = document.querySelectorAll(".nav-item");
    for (var index = 0; index < navItems.length; index += 1) {
      navItems[index].classList.toggle("is-active", navItems[index].getAttribute("data-view") === state.view);
    }
    var panels = document.querySelectorAll("[data-view-panel]");
    for (var panelIndex = 0; panelIndex < panels.length; panelIndex += 1) {
      panels[panelIndex].hidden = panels[panelIndex].getAttribute("data-view-panel") !== state.view;
    }
  }

  async function navigate(view, writeHash) {
    if (VIEWS.indexOf(view) < 0) {
      view = "overview";
    }
    state.view = view;
    updateViewClasses();
    if (writeHash !== false) {
      try {
        history.replaceState(null, "", "#" + view);
      } catch (error) {
        location.hash = view;
      }
    }
    if (view === "overview") {
      await loadOverview();
      return;
    }
    if (!state.overview) {
      await loadOverview({ notify: false });
    }
    if (view === "services") {
      await loadServices();
    } else if (view === "metrics") {
      await loadMetrics();
    } else if (view === "proxies") {
      await loadProxies();
    } else if (view === "singbox") {
      await loadSingbox();
    } else if (view === "backups") {
      await loadBackups();
    } else if (view === "audit") {
      await loadAudit(state.auditQuery);
    } else if (view === "settings") {
      await loadSettings();
    }
  }

  function updateTop() {
    var panel = state.settings || (state.overview && state.overview.panel) || {};
    var host = (state.overview && state.overview.host) || {};
    setText("top-host", host.hostname || panel.hostname || "—");
    setText("top-url", panel.public_url || "");
    setText("foot-node", host.hostname || "");
    setText("version", state.session && state.session.version ? "v" + state.session.version : "v—");
    setText("login-version", state.session && state.session.version ? "v" + state.session.version : "v—");
    setText("login-endpoint", panel.public_url || "Node Warden");
  }

  function setClock() {
    var now = new Date();
    setText("sidebar-clock", pad2(now.getHours()) + ":" + pad2(now.getMinutes()) + ":" + pad2(now.getSeconds()));
  }

  function startTimer() {
    stopTimer();
    state.timer = setInterval(function () {
      if (document.hidden || !state.authenticated) {
        return;
      }
      if (state.view !== "overview" && state.view !== "services") {
        return;
      }
      var modal = byId("modal");
      if (modal && !modal.hidden) {
        return;
      }
      if (state.view === "overview") {
        loadOverview({ notify: false });
      } else {
        loadServices({ notify: false });
      }
    }, 20000);
  }

  function stopTimer() {
    if (state.timer) {
      clearInterval(state.timer);
      state.timer = null;
    }
  }

  async function refreshView() {
    var refresh = byId("refresh");
    if (refresh && refresh.disabled) {
      return;
    }
    if (refresh) {
      refresh.disabled = true;
    }
    try {
      if (state.view === "overview") {
        await loadOverview();
      } else if (state.view === "services") {
        await loadServices();
        await loadOverview({ notify: false });
      } else if (state.view === "metrics") {
        await loadMetrics();
      } else if (state.view === "proxies") {
        await loadProxies();
      } else if (state.view === "singbox") {
        await loadSingbox();
      } else if (state.view === "backups") {
        await loadBackups();
      } else if (state.view === "audit") {
        await loadAudit(state.auditQuery);
      } else if (state.view === "settings") {
        await loadSettings();
      }
    } finally {
      if (refresh) {
        refresh.disabled = false;
      }
    }
  }

  function bind() {
    var loginForm = byId("login-form");
    if (loginForm) {
      loginForm.addEventListener("submit", onLogin);
    }
    var logoutButton = byId("logout");
    if (logoutButton) {
      logoutButton.addEventListener("click", logout);
    }
    var refreshButton = byId("refresh");
    if (refreshButton) {
      refreshButton.addEventListener("click", refreshView);
    }
    var modalClose = byId("modal-close");
    if (modalClose) {
      modalClose.addEventListener("click", closeModal);
    }
    var closers = document.querySelectorAll("[data-close]");
    for (var index = 0; index < closers.length; index += 1) {
      closers[index].addEventListener("click", closeModal);
    }
    var navItems = document.querySelectorAll(".nav-item");
    for (var navIndex = 0; navIndex < navItems.length; navIndex += 1) {
      navItems[navIndex].addEventListener("click", function (event) {
        var target = event.currentTarget.getAttribute("data-view");
        navigate(target);
      });
    }
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape") {
        var modal = byId("modal");
        if (modal && !modal.hidden) {
          closeModal();
        }
      }
    });
    window.addEventListener("hashchange", function () {
      var target = readHash();
      if (state.authenticated && target && target !== state.view) {
        navigate(target, false);
      }
    });
  }

  // ---------- overview ----------

  async function loadOverview(options) {
    var opts = options || {};
    var container = byId("overview-content");
    if (!state.overview && container) {
      skeleton(container);
    }
    try {
      var data = await api("/api/overview");
      state.overview = data;
      state.services = data.services || state.services;
      updateTop();
      if (state.view === "overview") {
        renderOverview();
      } else if (state.view === "services" && state.services) {
        renderServices();
      }
    } catch (error) {
      if (!state.authenticated) {
        return;
      }
      if (state.overview) {
        if (opts.notify !== false) {
          toast(error.message, "err");
        }
      } else if (container) {
        errorState(container, error.message, function () {
          loadOverview();
        });
      }
    }
  }

  function panel(title, note, body, options) {
    var opts = options || {};
    return h("section", { class: "panel" },
      h("div", { class: "panel-head" },
        h("div", {},
          h("div", { class: "panel-title" }, title),
          note ? h("div", { class: "panel-note" }, note) : null
        ),
        opts.action || null
      ),
      h("div", { class: "panel-body" + (opts.flush ? " flush" : "") }, body)
    );
  }

  function linkButton(label, onClick) {
    return h("button", { class: "section-link", type: "button", onclick: onClick }, label);
  }

  function meter(percent) {
    var value = Number(percent);
    if (!Number.isFinite(value)) {
      value = 0;
    }
    return h("div", { class: "meter" },
      h("div", { class: "meter-fill " + percentTone(value) + " " + percentClass(value) })
    );
  }

  function statCard(label, value, suffix, meta, percent, tone) {
    return h("article", { class: "stat-card", "data-tone": tone || null },
      h("div", { class: "stat-top" },
        h("span", { class: "stat-label" }, label),
        h("span", { class: "stat-icon" }, "")
      ),
      h("div", { class: "stat-value" }, value, suffix ? h("small", {}, suffix) : null),
      h("div", { class: "stat-meta", title: meta }, meta),
      percent === null ? null : meter(percent)
    );
  }

  function buildAlerts(data) {
    var alerts = [];
    var services = data.services || [];
    for (var index = 0; index < services.length; index += 1) {
      var service = services[index];
      var status = serviceState(service);
      if (status.tone === "down") {
        alerts.push({ tone: "danger", text: service.name + " 未运行" });
      } else if (status.tone === "warn") {
        alerts.push({ tone: "warn", text: service.name + " 健康检查未通过" });
      }
    }
    var cert = data.certificate;
    if (cert && cert.ok && typeof cert.days_remaining === "number" && cert.days_remaining < 14) {
      alerts.push({ tone: "warn", text: "TLS 证书剩余 " + cert.days_remaining + " 天" });
    }
    if (cert && !cert.ok) {
      alerts.push({ tone: "warn", text: "TLS 证书检查失败" });
    }
    var disk = data.host && data.host.disk;
    if (disk && disk.percent >= 85) {
      alerts.push({ tone: "danger", text: "系统盘使用率 " + disk.percent + "%" });
    }
    return alerts.slice(0, 5);
  }

  function renderOverview() {
    var container = byId("overview-content");
    if (!container) {
      return;
    }
    if (!state.overview) {
      skeleton(container);
      return;
    }
    var data = state.overview;
    var host = data.host || {};
    var memory = host.memory || {};
    var disk = host.disk || {};
    var services = data.services || [];
    var upCount = services.filter(isRowUp).length;
    var uptime = uptimeValue(host.uptime_seconds);
    var alerts = buildAlerts(data);

    var stats = h("div", { class: "stat-grid" },
      statCard("CPU 使用率", String(Math.round(Number(host.cpu_percent) || 0)), "%",
        (host.cpu_count || "—") + " 核 · 负载 " + ((host.load || []).join(" / ") || "—"),
        Number(host.cpu_percent) || 0, percentTone(host.cpu_percent)),
      statCard("内存使用率", String(Math.round(Number(memory.percent) || 0)), "%",
        formatBytes(memory.used) + " / " + formatBytes(memory.total),
        Number(memory.percent) || 0, percentTone(memory.percent)),
      statCard("系统盘使用率", String(Math.round(Number(disk.percent) || 0)), "%",
        formatBytes(disk.used) + " / " + formatBytes(disk.total),
        Number(disk.percent) || 0, percentTone(disk.percent)),
      statCard("运行时间", uptime.value, uptime.suffix,
        (host.os || "—") + " · " + (host.kernel || "—"), null, "")
    );

    var alertNodes = alerts.map(function (alert) {
      return h("div", { class: "notice " + alert.tone },
        h("span", { class: "notice-mark" }, alert.tone === "danger" ? "!" : "i"),
        h("span", {}, alert.text)
      );
    });

    var serviceGrid = services.length
      ? h("div", { class: "service-grid" }, services.map(function (service) {
          return serviceCard(service, false);
        }))
      : emptyBlock("暂无服务", "服务清单由 /etc/node-warden/services.json 管理");

    var auditPanel = panel("最近操作", "", auditRows(data.audit || [], true), { flush: true });

    var overviewGrid = h("div", { class: "overview-grid" },
      h("div", {},
        panel("服务状态", upCount + " / " + services.length + " 正常", serviceGrid, {
          action: linkButton("全部服务", function () { navigate("services"); })
        }),
        auditPanel
      ),
      h("div", {},
        panel("TLS 证书", "", certificateBody(data.certificate)),
        panel("监听端口", (data.ports || []).length + " 个", portBody(data.ports || []), { flush: true }),
        panel("系统信息", "", infoList([
          ["主机名", host.hostname || "—"],
          ["操作系统", host.os || "—"],
          ["内核", host.kernel || "—"],
          ["架构", host.arch || "—"],
          ["备份数量", String((data.backups && data.backups.count) || 0)],
          ["数据目录", host.data_disk ? formatBytes(host.data_disk.used) + " / " + formatBytes(host.data_disk.total) : "—"]
        ]))
      )
    );

    var page = h("div", {},
      pageHead("总览", "当前节点的运行状态和资源使用情况",
        [button("刷新", "btn-sm", refreshView), h("span", { class: "section-note" }, "更新 " + formatDate(data.as_of))]
      ),
      alertNodes.length ? h("div", { class: "stack" }, alertNodes) : null,
      stats,
      overviewGrid
    );
    container.replaceChildren(page);
  }

  function certificateBody(cert) {
    if (!cert) {
      return emptyBlock("暂无证书信息");
    }
    if (!cert.ok) {
      return emptyBlock("证书检查失败", clip(cert.error || "无法读取 TLS 证书", 160));
    }
    var days = Number(cert.days_remaining);
    var tone = days < 14 ? "danger" : days < 30 ? "warn" : "";
    return h("div", { class: "cert-wrap" },
      h("div", { class: "cert-days " + tone },
        Number.isFinite(days) ? String(days) : "—",
        h("small", {}, "剩余天数")
      ),
      h("div", { class: "cert-meta" },
        h("b", {}, cert.domain || "—"),
        h("span", {}, "到期时间 " + formatDate(cert.not_after)),
        h("span", {}, "签发时间 " + formatDate(cert.not_before)),
        h("span", {}, days > 0 ? "证书有效" : "证书已过期")
      )
    );
  }

  function portBody(ports) {
    if (!ports.length) {
      return emptyBlock("暂无监听端口");
    }
    return h("div", { class: "port-list" }, ports.map(function (port) {
      var address = port.wildcard ? "全部地址" : (port.address || "—");
      var process = port.process ? " · " + port.process : "";
      return h("div", { class: "port-row" },
        h("span", { class: "port-number" }, String(port.port)),
        h("span", { class: "port-name", title: address + process }, address + process),
        h("span", { class: "port-pid" }, port.pid ? "pid " + port.pid : "TCP")
      );
    }));
  }

  function resultChip(result) {
    var value = result || "ok";
    var ok = value === "ok" || value === "up";
    return h("span", { class: "result-chip " + (ok ? "ok" : "failed") }, value);
  }

  function auditRows(items, compact) {
    if (!items.length) {
      return emptyBlock("暂无审计记录");
    }
    return h("div", { class: "audit-list" }, items.map(function (item) {
      return h("div", { class: "audit-row" },
        h("span", { class: "audit-time" }, formatClock(item.ts)),
        h("span", { class: "audit-action" }, auditLabel(item.action)),
        h("span", { class: "audit-detail", title: item.detail || "" }, item.detail || "—"),
        compact ? null : h("span", { class: "audit-ip" }, item.ip || "—"),
        resultChip(item.result)
      );
    }));
  }

  function serviceCard(row, full) {
    var status = serviceState(row);
    var metrics = row.metrics || null;
    var availability = row.uptime || null;
    var percent = availability && availability.pct !== null ? availability.pct : null;
    var meta = [
      metaItem("类型", KIND_LABEL[row.kind] || row.kind || "—"),
      metaItem("目标", row.target || row.id),
      metaItem("健康检查", row.health && row.health.type !== "none"
        ? (row.health.ok ? (row.health.latency_ms + " ms") : "未通过")
        : "正常"),
      metaItem("24 小时可用率", percent === null ? "暂无样本" : percent + "%")
    ];

    var metricsLine = metrics ? h("div", { class: "metrics-line" },
      metricChip("CPU", metrics.cpu),
      metricChip("内存", metrics.memory),
      metricChip("内存占比", metrics.memory_percent)
    ) : null;

    var alertLine = status.tone === "up" ? null : h("div", { class: "service-alert" }, clip(status.detail, 180));

    var uptimeBlock = full ? h("div", { class: "uptime-block" },
      h("div", { class: "uptime-labels" },
        h("span", {}, "24 小时可用率"),
        h("span", {}, percent === null ? "暂无样本" : percent + "%")
      ),
      h("div", { class: "uptime-bar" },
        h("div", { class: "uptime-fill " + percentTone(percent) + " " + percentClass(percent) })
      ),
      availability && availability.incidents && availability.incidents.length
        ? h("div", { class: "service-alert" }, "最近 24 小时有 " + availability.incidents.length + " 次中断，累计 " + formatDuration(availability.down_seconds))
        : null
    ) : null;

    var actions = null;
    if (full) {
      var actionNodes = (row.actions || []).map(function (action) {
        var className = action === "stop" ? "btn-sm btn-danger" : "btn-sm";
        return button(actionLabel(action), className, function () {
          handleAction(row, action);
        });
      });
      if (row.logs && row.logs.length) {
        actionNodes.push(button("日志", "btn-sm btn-quiet", function () {
          openLogs(row);
        }));
      }
      actions = h("div", { class: "service-actions" }, actionNodes);
    }

    return h("article", { class: "service-card is-" + status.tone + (full ? " service-full" : "") },
      h("div", { class: "service-head" },
        h("div", {},
          h("div", { class: "service-name" }, row.name || row.id),
          h("div", { class: "service-id" }, row.target || row.id)
        ),
        statusPill(status.tone, status.label)
      ),
      row.description ? h("div", { class: "service-desc" }, row.description) : null,
      h("div", { class: "service-meta" }, meta),
      metricsLine,
      alertLine,
      uptimeBlock,
      full ? null : h("div", { class: "service-foot" },
        h("span", { class: "section-note" }, percent === null ? "暂无可用率样本" : "可用率 " + percent + "%"),
        h("span", { class: "section-note" }, row.health && row.health.detail ? clip(row.health.detail, 48) : "—")
      ),
      actions
    );
  }

  async function handleAction(row, action) {
    var destructive = action === "stop" || action === "restart";
    if (!destructive) {
      await executeAction(row, action);
      return;
    }
    confirmAction("确认" + actionLabel(action), "将" + actionLabel(action) + " " + row.name + "。", async function () {
      await executeAction(row, action);
    });
  }

  async function executeAction(row, action) {
    try {
      var result = await api("/api/services/" + encodeURIComponent(row.id) + "/action", {
        method: "POST",
        body: { action: action }
      });
      if (state.view === "services") {
        await loadServices({ notify: false });
      } else {
        await loadOverview({ notify: false });
      }
      if (result && result.output) {
        openOutputModal(row.name + " · " + actionLabel(action), result.output, Boolean(result.ok));
      } else {
        toast(result && result.ok ? "操作完成" : "操作失败", result && result.ok ? "ok" : "err");
      }
    } catch (error) {
      toast(error.message, "err");
    }
  }

  function openLogs(row) {
    var sources = row.logs || [];
    if (!sources.length) {
      toast("该服务没有配置日志源", "err");
      return;
    }
    var select = h("select", {});
    sources.forEach(function (source) {
      select.appendChild(h("option", { value: source.id }, source.label));
    });
    var output = h("pre", { class: "log-output", tabindex: "0" }, "正在加载...");
    var content = "";
    var copy = button("复制", "btn-sm", function () {
      copyText(content);
    });
    var refresh = button("刷新", "btn-sm", function () {
      loadServiceLogs(row, select.value, output, function (text) {
        content = text;
      });
    });
    select.addEventListener("change", function () {
      loadServiceLogs(row, select.value, output, function (text) {
        content = text;
      });
    });
    var body = h("div", {},
      h("div", { class: "log-toolbar" }, select, refresh, copy),
      output
    );
    openModal("日志 · " + row.name, body, [button("关闭", "btn-quiet", closeModal)]);
    loadServiceLogs(row, select.value, output, function (text) {
      content = text;
    });
  }

  async function loadServiceLogs(row, source, output, onContent) {
    output.textContent = "正在加载...";
    try {
      var data = await api("/api/services/" + encodeURIComponent(row.id) + "/logs?source=" +
        encodeURIComponent(source) + "&tail=200");
      var text = data && data.text ? data.text : "无日志内容";
      output.textContent = text;
      if (onContent) {
        onContent(text);
      }
    } catch (error) {
      output.textContent = error.message;
    }
  }

  // ---------- services ----------

  async function loadServices(options) {
    var opts = options || {};
    var container = byId("services-content");
    if (!state.services && container) {
      skeleton(container);
    }
    try {
      var data = await api("/api/services");
      var metrics = {};
      (state.overview && state.overview.services ? state.overview.services : []).forEach(function (row) {
        if (row.metrics) {
          metrics[row.id] = row.metrics;
        }
      });
      var rows = data.services || [];
      rows.forEach(function (row) {
        if (!row.metrics && metrics[row.id]) {
          row.metrics = metrics[row.id];
        }
      });
      state.services = rows;
      if (state.view === "services") {
        renderServices();
      }
    } catch (error) {
      if (!state.authenticated) {
        return;
      }
      if (state.services) {
        if (opts.notify !== false) {
          toast(error.message, "err");
        }
      } else if (container) {
        errorState(container, error.message, function () {
          loadServices();
        });
      }
    }
  }

  function renderServices() {
    var container = byId("services-content");
    if (!container) {
      return;
    }
    var rows = state.services || (state.overview && state.overview.services) || [];
    if (!rows.length) {
      container.replaceChildren(pageHead("服务", "服务状态、可用率和操作",
        [button("刷新", "btn-sm", refreshView)])
      );
      container.appendChild(emptyBlock("暂无服务", "服务清单由 /etc/node-warden/services.json 管理"));
      return;
    }
    var upCount = rows.filter(isRowUp).length;
    var page = h("div", {},
      pageHead("服务", "服务状态、可用率和操作",
        [button("刷新", "btn-sm", refreshView), h("span", { class: "section-note" }, upCount + " / " + rows.length + " 正常")]
      ),
      h("div", { class: "services-list" }, rows.map(function (row) {
        return serviceCard(row, true);
      }))
    );
    container.replaceChildren(page);
  }

  // ---------- sing-box ----------

  async function loadSingbox(options) {
    var opts = options || {};
    var container = byId("singbox-content");
    if (!state.singbox && container) {
      skeleton(container);
    }
    try {
      var data = await api("/api/singbox");
      state.singbox = data;
      if (state.view === "singbox") {
        renderSingbox();
      }
    } catch (error) {
      if (!state.authenticated) {
        return;
      }
      if (state.singbox) {
        if (opts.notify !== false) {
          toast(error.message, "err");
        }
      } else if (container) {
        errorState(container, error.message, function () {
          loadSingbox();
        });
      }
    }
  }

  function singboxService() {
    var rows = state.services || (state.overview && state.overview.services) || [];
    for (var index = 0; index < rows.length; index += 1) {
      if (rows[index].kind === "singbox") {
        return rows[index];
      }
    }
    return null;
  }

  function inboundCard(inbound) {
    var users = (inbound.users || []).map(function (user) {
      return user.username || user.name || "用户";
    }).join("、");
    var tls = inbound.tls || {};
    return h("div", { class: "inbound-card" },
      h("div", { class: "inbound-head" },
        h("span", { class: "inbound-title" }, inbound.tag || "未命名入站"),
        h("span", { class: "inbound-type" }, inbound.type || "unknown")
      ),
      h("div", { class: "kv-grid" },
        kv("监听地址", (inbound.listen || "*") + ":" + (inbound.port || "—")),
        kv("传输方式", inbound.transport || "tcp"),
        kv("用户", users || "无"),
        kv("TLS", tls.enabled ? (tls.reality ? "REALITY" : "已启用") : "未启用")
      )
    );
  }

  function renderSingbox() {
    var container = byId("singbox-content");
    if (!container) {
      return;
    }
    var data = state.singbox;
    if (!data) {
      skeleton(container);
      return;
    }
    var service = singboxService();
    var files = data.files || [];
    var inbounds = data.inbounds || [];
    var check = data.check;
    var checkLabel = check ? (check.ok ? "检查通过" : "检查失败") : "尚未检查";
    var checkTone = check ? (check.ok ? "up" : "down") : "warn";

    var inboundNodes = inbounds.length
      ? h("div", { class: "inbound-grid" }, inbounds.map(inboundCard))
      : emptyBlock("暂无入站配置", "未在 /etc/sing-box 配置文件中找到入站");

    var fileNodes = files.length
      ? h("div", { class: "config-files" }, files.map(function (file) {
          return h("div", { class: "config-file" },
            h("div", {},
              h("div", { class: "config-file-name" }, file.label),
              h("div", { class: "config-file-meta" }, formatBytes(file.size) + " · " + formatDate(file.mtime * 1000))
            ),
            button("查看", "btn-sm", function () {
              openConfig(file);
            })
          );
        }))
      : emptyBlock("暂无配置文件");

    var checkPanel = panel("运行状态", data.installed ? "已安装" : "未安装",
      h("div", {},
        h("div", { class: "form-actions" },
          statusPill(data.installed ? "up" : "down", data.installed ? "已安装" : "未安装"),
          statusPill(checkTone, checkLabel)
        ),
        h("div", { class: "divider" }),
        infoList([
          ["版本", data.version || "—"],
          ["入站数量", String(inbounds.length)],
          ["配置文件", String(files.length) + " 个"],
          ["最后检查", check ? formatDate(check.checked_at) : "—"]
        ]),
        check && !check.ok ? h("pre", { class: "check-output" }, check.output || "无输出") : null
      )
    );

    var actionNodes = [];
    if (service && service.actions && service.actions.indexOf("check") >= 0) {
      actionNodes.push(button("检查配置", "btn-sm", function () {
        handleAction(service, "check");
      }));
    }
    actionNodes.push(button("查看连接信息", "btn-sm btn-primary", openReveal));
    var actionPanel = panel("操作", "", h("div", { class: "form-actions" }, actionNodes));

    var page = h("div", {},
      pageHead("Sing-box", "入站配置、配置检查和连接信息",
        [button("刷新", "btn-sm", refreshView), button("查看连接信息", "btn-sm btn-primary", openReveal)]
      ),
      data.error ? h("div", { class: "notice danger" },
        h("span", { class: "notice-mark" }, "!"),
        h("span", {}, data.error)
      ) : null,
      !data.installed ? h("div", { class: "notice warn" },
        h("span", { class: "notice-mark" }, "i"),
        h("span", {}, "未检测到 sing-box 可执行文件。请先完成安装。")
      ) : null,
      h("div", { class: "sb-grid" },
        h("div", {},
          panel("入站", inbounds.length + " 个", inboundNodes),
          panel("配置文件", files.length + " 个", fileNodes)
        ),
        h("div", {},
          checkPanel,
          actionPanel
        )
      )
    );
    container.replaceChildren(page);
  }

  async function openConfig(file) {
    var content = "";
    var output = h("pre", { class: "config-output", tabindex: "0" }, "正在加载...");
    var body = h("div", {}, output);
    var copy = button("复制", "btn-sm", function () {
      copyText(content);
    });
    openModal("配置文件 · " + file.label, body, [copy, button("关闭", "btn-quiet", closeModal)]);
    try {
      var data = await api("/api/singbox/config?file=" + encodeURIComponent(file.id));
      content = data && data.content ? data.content : "无内容";
      output.textContent = content;
      if (data && data.warning) {
        var warning = h("div", { class: "notice warn" },
          h("span", { class: "notice-mark" }, "i"),
          h("span", {}, data.warning)
        );
        body.replaceChildren(warning, output);
      }
    } catch (error) {
      output.textContent = error.message;
    }
  }

  function openReveal() {
    var input = h("input", {
      type: "password",
      autocomplete: "current-password",
      placeholder: "请输入当前访问密钥",
      required: true
    });
    var error = h("p", { class: "form-error", hidden: true });
    var form = h("form", { class: "modal-form", id: "reveal-form" },
      h("p", { class: "modal-hint" }, "查看连接信息需要再次验证当前访问密钥。连接信息包含登录凭据，请妥善保管。"),
      h("label", { class: "field" }, h("span", {}, "访问密钥"), input),
      error
    );
    var submit = h("button", { class: "btn btn-primary", type: "submit", form: "reveal-form" }, "查看");
    form.addEventListener("submit", async function (event) {
      event.preventDefault();
      var key = input.value.trim();
      if (!key) {
        error.textContent = "请输入访问密钥";
        error.hidden = false;
        return;
      }
      error.hidden = true;
      submit.disabled = true;
      submit.textContent = "验证中...";
      try {
        var data = await api("/api/singbox/reveal", {
          method: "POST",
          body: { key: key },
          allow401: true
        });
        showRevealResult(data);
      } catch (failure) {
        error.textContent = failure.message;
        error.hidden = false;
      } finally {
        submit.disabled = false;
        submit.textContent = "查看";
      }
    });
    openModal("查看连接信息", form, [button("取消", "btn-quiet", closeModal), submit]);
  }

  function userSummary(user) {
    if (user === null || user === undefined) {
      return "—";
    }
    if (typeof user !== "object") {
      return String(user);
    }
    var keys = Object.keys(user);
    var parts = [];
    for (var index = 0; index < keys.length; index += 1) {
      var value = user[keys[index]];
      if (value === "" || value === null || value === undefined) {
        continue;
      }
      parts.push(keys[index] + "=" + (typeof value === "object" ? JSON.stringify(value) : String(value)));
    }
    return parts.length ? parts.join("  ") : "—";
  }

  function showRevealResult(data) {
    var warnings = data.warnings || [];
    var inbounds = data.inbounds || [];
    var body = h("div", {},
      h("p", { class: "modal-hint" }, "主机：" + (data.host || "—")),
      warnings.length ? h("div", { class: "notice warn" },
        h("span", { class: "notice-mark" }, "i"),
        h("span", {}, warnings.join("；"))
      ) : null,
      inbounds.length ? h("div", { class: "reveal-list" }, inbounds.map(function (inbound) {
        var users = inbound.users || [];
        var userNodes = users.map(function (user) {
          return h("div", { class: "reveal-user" }, userSummary(user));
        });
        return h("div", { class: "reveal-item" },
          h("div", { class: "reveal-head" },
            h("b", {}, inbound.tag || "未命名入站"),
            h("span", { class: "inbound-type" }, inbound.type || "unknown")
          ),
          inbound.share_uri ? h("div", { class: "share-url" },
            h("code", {}, inbound.share_uri),
            button("复制", "btn-sm copy-btn", function () {
              copyText(inbound.share_uri);
            })
          ) : h("div", { class: "service-alert" }, "无法生成分享链接"),
          userNodes.length ? h("div", {}, userNodes) : null
        );
      })) : emptyBlock("暂无入站")
    );
    openModal("连接信息", body, [button("关闭", "btn-quiet", closeModal)]);
  }

  // ---------- backups ----------

  async function loadBackups(options) {
    var opts = options || {};
    var container = byId("backups-content");
    if (state.backups === null && container) {
      skeleton(container);
    }
    try {
      var data = await api("/api/backups");
      state.backups = data.backups || [];
      if (state.view === "backups") {
        renderBackups();
      }
    } catch (error) {
      if (!state.authenticated) {
        return;
      }
      if (state.backups !== null) {
        if (opts.notify !== false) {
          toast(error.message, "err");
        }
      } else if (container) {
        errorState(container, error.message, function () {
          loadBackups();
        });
      }
    }
  }

  function renderBackups() {
    var container = byId("backups-content");
    if (!container) {
      return;
    }
    if (state.backups === null) {
      skeleton(container);
      return;
    }
    var backups = state.backups;
    var create = button("创建备份", "btn-primary", function () {
      createBackup(create);
    });
    var page = h("div", {},
      pageHead("备份", "配置备份的创建、下载和删除",
        [create, button("刷新", "btn-sm", refreshView)]
      ),
      backups.length ? h("div", { class: "backup-list" }, backups.map(function (backup) {
        var entries = backup.entries || [];
        var labels = entries.map(function (entry) {
          return entry.label || entry.id;
        }).join("、");
        return h("article", { class: "card backup-card" },
          h("div", {},
            h("div", { class: "backup-title" },
              h("b", {}, backup.id),
              h("span", { class: "result-chip ok" }, "可用")
            ),
            h("div", { class: "backup-meta" },
              h("span", {}, "创建 " + formatDate(backup.created)),
              h("span", {}, formatBytes(backup.size)),
              h("span", {}, entries.length + " 个路径")
            ),
            h("div", { class: "backup-entries", title: labels }, labels || "—"),
            h("div", { class: "hash" }, "SHA-256 " + (backup.sha256 || "—"))
          ),
          h("div", { class: "backup-actions" },
            h("a", {
              class: "btn btn-sm",
              href: endpoint("/api/backups/" + encodeURIComponent(backup.id) + "/download"),
              download: backup.id + ".tar.gz"
            }, "下载"),
            button("删除", "btn-sm btn-danger", function () {
              confirmAction("确认删除", "将删除备份 " + backup.id + "。", async function () {
                await deleteBackup(backup.id);
              });
            })
          )
        );
      })) : emptyBlock("暂无备份", "创建备份后会在此处显示备份文件")
    );
    container.replaceChildren(page);
  }

  async function createBackup(trigger) {
    if (trigger && trigger.disabled) {
      return;
    }
    if (trigger) {
      trigger.disabled = true;
      trigger.textContent = "创建中...";
    }
    try {
      await api("/api/backups", { method: "POST", body: {}, timeout: 180000 });
      toast("备份已创建", "ok");
      await loadBackups({ notify: false });
    } catch (error) {
      toast(error.message, "err");
    } finally {
      if (trigger) {
        trigger.disabled = false;
        trigger.textContent = "创建备份";
      }
    }
  }

  async function deleteBackup(id) {
    try {
      await api("/api/backups/" + encodeURIComponent(id) + "/delete", { method: "POST", body: {} });
      toast("备份已删除", "ok");
      await loadBackups({ notify: false });
    } catch (error) {
      toast(error.message, "err");
    }
  }

  // ---------- audit ----------

  async function loadAudit(query, options) {
    var opts = options || {};
    state.auditQuery = query || "";
    var container = byId("audit-content");
    if (state.audit === null && container) {
      skeleton(container);
    }
    try {
      var data = await api("/api/audit?limit=200&q=" + encodeURIComponent(state.auditQuery));
      state.audit = data.items || [];
      if (state.view === "audit") {
        renderAudit();
      }
    } catch (error) {
      if (!state.authenticated) {
        return;
      }
      if (state.audit !== null) {
        if (opts.notify !== false) {
          toast(error.message, "err");
        }
      } else if (container) {
        errorState(container, error.message, function () {
          loadAudit(state.auditQuery);
        });
      }
    }
  }

  function renderAudit() {
    var container = byId("audit-content");
    if (!container) {
      return;
    }
    if (state.audit === null) {
      skeleton(container);
      return;
    }
    var input = h("input", {
      class: "search-input",
      type: "search",
      placeholder: "搜索动作、内容或 IP",
      value: state.auditQuery
    });
    var form = h("form", { class: "toolbar" },
      input,
      h("button", { class: "btn btn-sm btn-primary", type: "submit" }, "查询"),
      button("清除", "btn-sm btn-quiet", function () {
        input.value = "";
        loadAudit("");
      })
    );
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      loadAudit(input.value.trim());
    });
    var rows = state.audit;
    var table = rows.length ? h("div", { class: "table-wrap" },
      h("table", {},
        h("thead", {}, h("tr", {},
          h("th", {}, "时间"),
          h("th", {}, "动作"),
          h("th", {}, "内容"),
          h("th", {}, "结果"),
          h("th", { class: "mono" }, "来源 IP")
        )),
        h("tbody", {}, rows.map(function (item) {
          return h("tr", {},
            h("td", { class: "mono nowrap" }, formatDate(item.ts)),
            h("td", { class: "mono nowrap" }, auditLabel(item.action)),
            h("td", { title: item.detail || "" }, item.detail || "—"),
            h("td", {}, resultChip(item.result)),
            h("td", { class: "mono nowrap" }, item.ip || "—")
          );
        }))
      )
    ) : emptyBlock("暂无审计记录", "登录和操作记录会写入 /var/lib/node-warden/audit.log");

    container.replaceChildren(h("div", {},
      pageHead("审计日志", "登录、服务操作、备份和密钥修改记录",
        [button("刷新", "btn-sm", refreshView)]
      ),
      form,
      table
    ));
  }

  // ---------- settings ----------

  async function loadSettings(options) {
    var opts = options || {};
    var container = byId("settings-content");
    if (state.settings === null && container) {
      skeleton(container);
    }
    try {
      var data = await api("/api/settings");
      state.settings = data;
      updateTop();
      if (state.view === "settings") {
        renderSettings();
      }
    } catch (error) {
      if (!state.authenticated) {
        return;
      }
      if (state.settings !== null) {
        if (opts.notify !== false) {
          toast(error.message, "err");
        }
      } else if (container) {
        errorState(container, error.message, function () {
          loadSettings();
        });
      }
    }
  }

  function formField(label, input, hint) {
    return h("label", { class: "field" },
      h("span", {}, label),
      input,
      hint ? h("span", { class: "field-hint" }, hint) : null
    );
  }

  function randomKey() {
    var bytes = new Uint8Array(32);
    crypto.getRandomValues(bytes);
    var binary = "";
    for (var index = 0; index < bytes.length; index += 1) {
      binary += String.fromCharCode(bytes[index]);
    }
    return btoa(binary).split("+").join("-").split("/").join("_").split("=").join("");
  }

  function keySettingsBody(data) {
    var current = h("input", {
      type: "password",
      autocomplete: "current-password",
      placeholder: "当前访问密钥",
      required: true
    });
    var next = h("input", {
      type: "password",
      autocomplete: "new-password",
      placeholder: "新访问密钥，至少 10 个字符",
      required: true
    });
    var confirm = h("input", {
      type: "password",
      autocomplete: "new-password",
      placeholder: "再次输入新访问密钥",
      required: true
    });
    var error = h("p", { class: "form-error", hidden: true });
    var ok = h("p", { class: "form-ok", hidden: true });
    var generate = button("生成随机密钥", "btn-sm", function () {
      var value = randomKey();
      next.type = "text";
      confirm.type = "text";
      next.value = value;
      confirm.value = value;
      toast("已生成随机密钥，请先保存再提交", "ok");
    });
    var submit = h("button", { class: "btn btn-primary", type: "submit" }, "保存新密钥");
    var form = h("form", { class: "modal-form stack" },
      h("div", { class: "info-list" },
        h("div", { class: "info-row" }, h("span", {}, "当前密钥指纹"), h("b", {}, data.key_fingerprint || "—")),
        h("div", { class: "info-row" }, h("span", {}, "上次修改"), h("b", {}, formatDate(data.key_changed_at)))
      ),
      h("div", { class: "divider" }),
      formField("当前访问密钥", current),
      formField("新访问密钥", next, "10 到 256 个字符，不能包含空白或控制字符。"),
      formField("确认新访问密钥", confirm),
      h("div", { class: "form-actions" }, submit, generate),
      error,
      ok
    );
    form.addEventListener("submit", async function (event) {
      event.preventDefault();
      var currentValue = current.value.trim();
      var nextValue = next.value.trim();
      var confirmValue = confirm.value.trim();
      error.hidden = true;
      ok.hidden = true;
      if (!currentValue || !nextValue) {
        error.textContent = "请完整填写当前密钥和新密钥";
        error.hidden = false;
        return;
      }
      if (nextValue !== confirmValue) {
        error.textContent = "两次输入的新密钥不一致";
        error.hidden = false;
        return;
      }
      submit.disabled = true;
      submit.textContent = "保存中...";
      try {
        var session = await api("/api/key/change", {
          method: "POST",
          body: { current_key: currentValue, new_key: nextValue },
          allow401: true
        });
        applySession(session);
        toast("访问密钥已更新，其他会话已失效", "ok");
        state.settings = null;
        await loadOverview({ notify: false });
        await loadSettings({ notify: false });
      } catch (failure) {
        error.textContent = failure.message;
        error.hidden = false;
      } finally {
        submit.disabled = false;
        submit.textContent = "保存新密钥";
      }
    });
    return form;
  }

  function certSettingsBody() {
    var cert = state.overview && state.overview.certificate;
    if (!cert) {
      return emptyBlock("暂无证书信息");
    }
    if (!cert.ok) {
      return h("div", {},
        emptyBlock("证书检查失败", clip(cert.error || "", 160)),
        h("div", { class: "form-actions" },
          button("执行检查", "btn-sm", function () {
            certDryRun(this);
          })
        )
      );
    }
    var days = Number(cert.days_remaining);
    return h("div", {},
      h("div", { class: "info-list" },
        h("div", { class: "info-row" }, h("span", {}, "域名"), h("b", {}, cert.domain || "—")),
        h("div", { class: "info-row" }, h("span", {}, "到期时间"), h("b", {}, formatDate(cert.not_after))),
        h("div", { class: "info-row" }, h("span", {}, "剩余天数"), h("b", {}, String(days) + " 天")),
        h("div", { class: "info-row" }, h("span", {}, "签发者"), h("b", {}, cert.issuer || "—"))
      ),
      h("div", { class: "form-actions" },
        button("执行检查", "btn-sm", function () {
          certDryRun(this);
        })
      )
    );
  }

  async function certDryRun(trigger) {
    if (trigger && trigger.disabled) {
      return;
    }
    if (trigger) {
      trigger.disabled = true;
      trigger.textContent = "检查中...";
    }
    try {
      var result = await api("/api/cert/renew", { method: "POST", body: {}, timeout: 200000 });
      openOutputModal(result.ok ? "证书检查通过" : "证书检查失败", result.output || "无输出", Boolean(result.ok));
      toast(result.ok ? "证书检查通过" : "证书检查失败", result.ok ? "ok" : "err");
      await loadOverview({ notify: false });
      await loadSettings({ notify: false });
    } catch (error) {
      toast(error.message, "err");
    } finally {
      if (trigger) {
        trigger.disabled = false;
        trigger.textContent = "执行检查";
      }
    }
  }

  function monitorSettingsBody(data) {
    return infoList([
      ["监控", data.monitor_enabled ? "启用" : "停用"],
      ["采样间隔", data.monitor_interval ? data.monitor_interval + " 秒" : "—"],
      ["会话有效期", formatDuration(data.session_ttl)],
      ["备份数量", String(data.backup_count || 0)]
    ]);
  }

  function panelSettingsBody(data) {
    return infoList([
      ["名称", data.name || "Node Warden"],
      ["版本", data.version || "—"],
      ["访问地址", data.public_url || "—"],
      ["基础路径", data.base_path || "—"],
      ["主机名", data.hostname || "—"],
      ["启动时间", formatDate(data.started_at)]
    ]);
  }

  function backupSettingsBody(data) {
    return h("div", {},
      infoList([
        ["备份数量", String(data.backup_count || 0)],
        ["备份目录", "/var/lib/node-warden/backups"]
      ]),
      h("div", { class: "form-actions" },
        linkButton("打开备份页", function () {
          navigate("backups");
        })
      )
    );
  }

  function renderSettings() {
    var container = byId("settings-content");
    if (!container || !state.settings) {
      if (container) {
        skeleton(container);
      }
      return;
    }
    var data = state.settings;
    var page = h("div", {},
      pageHead("设置", "访问密钥、面板信息和证书检查",
        [button("刷新", "btn-sm", refreshView)]
      ),
      h("div", { class: "settings-grid" },
        panel("访问密钥", "", keySettingsBody(data), { action: null }),
        panel("面板信息", "", panelSettingsBody(data)),
        panel("监控与会话", "", monitorSettingsBody(data)),
        panel("TLS 证书", "", certSettingsBody()),
        panel("备份", "", backupSettingsBody(data), { action: null })
      )
    );
    var keyPanel = page.querySelector(".settings-grid .panel");
    if (keyPanel) {
      keyPanel.classList.add("span-2");
    }
    container.replaceChildren(page);
  }


  // ---------- metrics ----------

  var SVG_NS = "http://www.w3.org/2000/svg";

  function sv(tag, attrs) {
    var node = document.createElementNS(SVG_NS, tag);
    var values = attrs || {};
    var keys = Object.keys(values);
    for (var index = 0; index < keys.length; index += 1) {
      var value = values[keys[index]];
      if (value !== null && value !== undefined) {
        node.setAttribute(keys[index], String(value));
      }
    }
    return node;
  }

  function formatRate(value) {
    if (!Number.isFinite(Number(value)) || Number(value) < 0) {
      return "—";
    }
    return formatBytes(Number(value)) + "/s";
  }

  function chartBlock(options) {
    var opts = options || {};
    var series = (opts.series || []).filter(function (item) {
      return item && item.values && item.values.length;
    });
    var allValues = [];
    var maxLength = 0;
    for (var seriesIndex = 0; seriesIndex < series.length; seriesIndex += 1) {
      var values = series[seriesIndex].values;
      maxLength = Math.max(maxLength, values.length);
      for (var valueIndex = 0; valueIndex < values.length; valueIndex += 1) {
        var current = Number(values[valueIndex]);
        if (Number.isFinite(current)) {
          allValues.push(current);
        }
      }
    }
    if (!allValues.length || !maxLength) {
      return emptyBlock("暂无趋势数据", "监控采样运行一段时间后会显示图表");
    }
    var max = Number(opts.max);
    if (!Number.isFinite(max) || max <= 0) {
      max = Math.max.apply(null, allValues);
      if (!Number.isFinite(max) || max <= 0) {
        max = 1;
      }
      max = max * 1.15;
    }
    var min = Number(opts.min) || 0;
    var span = max - min || 1;
    var height = 44;
    var svg = sv("svg", {
      viewBox: "0 0 100 " + height,
      class: "chart-svg",
      role: "img",
      "aria-label": opts.label || "趋势图",
      preserveAspectRatio: "none"
    });
    [0, 10, 20, 30, 40].forEach(function (y) {
      svg.appendChild(sv("line", { x1: 0, y1: y, x2: 100, y2: y, class: "chart-grid" }));
    });
    for (var lineIndex = 0; lineIndex < series.length; lineIndex += 1) {
      var item = series[lineIndex];
      var count = item.values.length;
      var points = [];
      for (var pointIndex = 0; pointIndex < count; pointIndex += 1) {
        var raw = Number(item.values[pointIndex]);
        if (!Number.isFinite(raw)) {
          continue;
        }
        var x = count <= 1 ? 50 : (pointIndex / (count - 1)) * 100;
        var y = height - ((Math.max(min, Math.min(max, raw)) - min) / span) * height;
        points.push(x.toFixed(2) + "," + y.toFixed(2));
      }
      if (points.length) {
        svg.appendChild(sv("polyline", {
          points: points.join(" "),
          class: "chart-line " + (item.className || "chart-line-a"),
          "vector-effect": "non-scaling-stroke"
        }));
      }
    }
    var legend = series.map(function (item) {
      return h("span", { class: "chart-key" },
        h("i", { class: "chart-swatch " + (item.className || "chart-line-a") }),
        item.name
      );
    });
    function axisLabel(value) {
      if (typeof opts.formatMax === "function") {
        return opts.formatMax(value);
      }
      return String(Math.round(value)) + (opts.unit || "");
    }
    return h("div", { class: "chart" },
      h("div", { class: "chart-legend" }, legend),
      svg,
      h("div", { class: "chart-scale" },
        h("span", {}, axisLabel(max)),
        h("span", {}, axisLabel((max + min) / 2)),
        h("span", {}, axisLabel(min))
      )
    );
  }

  function metricRangeBar() {
    var options = [
      { hours: 1, label: "1 小时" },
      { hours: 6, label: "6 小时" },
      { hours: 24, label: "24 小时" },
      { hours: 72, label: "3 天" }
    ];
    return h("div", { class: "range-bar" }, options.map(function (option) {
      return h("button", {
        class: "range-btn" + (state.metricHours === option.hours ? " is-active" : ""),
        type: "button",
        onclick: function () {
          if (state.metricHours === option.hours) {
            return;
          }
          state.metricHours = option.hours;
          state.metrics = null;
          loadMetrics();
        }
      }, option.label);
    }));
  }

  async function loadMetrics(options) {
    var opts = options || {};
    var container = byId("metrics-content");
    if (!state.metrics && container) {
      skeleton(container);
    }
    try {
      var points = state.metricHours <= 6 ? 96 : 96;
      var data = await api("/api/metrics?hours=" + state.metricHours + "&points=" + points);
      state.metrics = data;
      if (state.view === "metrics") {
        renderMetrics();
      }
    } catch (error) {
      if (!state.authenticated) {
        return;
      }
      if (state.metrics) {
        if (opts.notify !== false) {
          toast(error.message, "err");
        }
      } else if (container) {
        errorState(container, error.message, function () {
          loadMetrics();
        });
      }
    }
  }

  function renderMetrics() {
    var container = byId("metrics-content");
    if (!container || !state.metrics) {
      if (container) {
        skeleton(container);
      }
      return;
    }
    var data = state.metrics;
    var host = data.host || {};
    var live = host.metrics || {};
    var network = live.network || {};
    var diskio = live.disk_io || {};
    var memory = host.memory || {};
    var disk = host.disk || {};
    var load = host.load || [0, 0, 0];
    var hostSeries = data.host_series || [];
    var stats = h("div", { class: "stat-grid" },
      statCard("CPU 使用率", String(Math.round(Number(host.cpu_percent) || 0)), "%",
        (host.cpu_count || "—") + " 核 · 负载 " + load.join(" / "),
        Number(host.cpu_percent) || 0, percentTone(host.cpu_percent)),
      statCard("内存使用率", String(Math.round(Number(memory.percent) || 0)), "%",
        formatBytes(memory.used) + " / " + formatBytes(memory.total),
        Number(memory.percent) || 0, percentTone(memory.percent)),
      statCard("系统盘使用率", String(Math.round(Number(disk.percent) || 0)), "%",
        formatBytes(disk.used) + " / " + formatBytes(disk.total),
        Number(disk.percent) || 0, percentTone(disk.percent)),
      statCard("负载", String(Number(load[0] || 0).toFixed(2)), "",
        "1 / 5 / 15 分钟", null, ""),
      statCard("网络接收", formatRate(network.rx_bps), "",
        "发送 " + formatRate(network.tx_bps), null, ""),
      statCard("磁盘读取", formatRate(diskio.read_bps), "",
        "写入 " + formatRate(diskio.write_bps), null, ""),
      statCard("TCP 连接", String(live.tcp_connections || 0), "个",
        "已建立连接", null, ""),
      statCard("进程数", String(live.processes || 0), "个",
        "当前运行进程", null, "")
    );

    var cpuChart = chartBlock({
      label: "CPU 与内存使用率",
      series: [
        { name: "CPU", className: "chart-line-a", values: hostSeries.map(function (item) { return item.cpu; }) },
        { name: "内存", className: "chart-line-b", values: hostSeries.map(function (item) { return item.memory; }) }
      ],
      max: 100,
      unit: "%"
    });
    var networkChart = chartBlock({
      label: "网络吞吐",
      series: [
        { name: "接收", className: "chart-line-a", values: hostSeries.map(function (item) { return item.rx_bps; }) },
        { name: "发送", className: "chart-line-b", values: hostSeries.map(function (item) { return item.tx_bps; }) }
      ],
      formatMax: formatRate
    });
    var diskChart = chartBlock({
      label: "磁盘吞吐",
      series: [
        { name: "读取", className: "chart-line-a", values: hostSeries.map(function (item) { return item.disk_read_bps; }) },
        { name: "写入", className: "chart-line-b", values: hostSeries.map(function (item) { return item.disk_write_bps; }) }
      ],
      formatMax: formatRate
    });
    var loadChart = chartBlock({
      label: "系统负载",
      series: [
        { name: "负载", className: "chart-line-c", values: hostSeries.map(function (item) { return item.load1; }) }
      ]
    });

    var serviceSeries = data.services || [];
    var availabilityBody = serviceSeries.length
      ? h("div", { class: "metric-list" }, serviceSeries.map(function (item) {
          var series = item.series || [];
          var latest = series.length ? series[series.length - 1] : null;
          var pct = latest && Number.isFinite(Number(latest.pct)) ? Number(latest.pct) : 0;
          return h("div", { class: "metric-row" },
            h("span", { class: "metric-name" }, item.name),
            meter(pct),
            h("b", { class: "metric-value" }, pct.toFixed(1) + "%")
          );
        }))
      : emptyBlock("暂无采样", "监控服务启动后开始记录可用率");

    var processes = live.top_processes || [];
    var processBody = processes.length
      ? h("table", { class: "data-table" },
          h("thead", {}, h("tr", {},
            h("th", {}, "进程"), h("th", {}, "PID"), h("th", {}, "CPU"), h("th", {}, "内存")
          )),
          h("tbody", {}, processes.map(function (item) {
            return h("tr", {},
              h("td", {}, item.name || "—"),
              h("td", {}, String(item.pid || "—")),
              h("td", {}, String(item.cpu || 0) + "%"),
              h("td", {}, String(item.memory || 0) + "%")
            );
          }))
        )
      : emptyBlock("暂无进程信息");

    var page = h("div", {},
      pageHead("指标", "主机资源、网络、磁盘和服务可用率的历史采样",
        [metricRangeBar(), button("刷新", "btn-sm", refreshView)]
      ),
      stats,
      h("div", { class: "overview-grid" },
        h("div", {},
          panel("CPU 与内存", "使用率，最近 " + data.hours + " 小时", cpuChart),
          panel("服务可用率", "按采样点计算", availabilityBody)
        ),
        h("div", {},
          panel("网络吞吐", "每秒收发字节", networkChart),
          panel("磁盘吞吐", "每秒读写字节", diskChart),
          panel("系统负载", "1 分钟平均负载", loadChart),
          panel("进程", "CPU 占用最高的进程", processBody, { flush: true })
        )
      ),
      h("p", { class: "section-note" }, "更新 " + formatDate(data.as_of))
    );
    container.replaceChildren(page);
  }

  // ---------- proxies ----------

  function proxyProbeState(proxy) {
    var probe = proxy.probe || {};
    if (!probe.ok) {
      return { tone: "down", label: "不可访问", detail: probe.error || "探测失败" };
    }
    var status = Number(probe.status);
    if (proxy.id === "docker" && status === 401) {
      return { tone: "up", label: "可访问", detail: "HTTP 401，镜像客户端需要认证" };
    }
    if (status === 403 && proxy.id === "gateway") {
      return { tone: "up", label: "可访问", detail: "HTTP 403，根路径不返回内容" };
    }
    return { tone: "up", label: "可访问", detail: "HTTP " + status };
  }

  function trafficRows(traffic) {
    var counts = (traffic && traffic.status) || {};
    var rows = [
      ["请求数", traffic && traffic.requests !== null && traffic.requests !== undefined ? String(traffic.requests) : "—"],
      ["流量", traffic && traffic.bytes !== null && traffic.bytes !== undefined ? formatBytes(traffic.bytes) : "—"],
      ["状态码", "2xx " + (counts["2xx"] || 0) + " · 3xx " + (counts["3xx"] || 0) +
        " · 4xx " + (counts["4xx"] || 0) + " · 5xx " + (counts["5xx"] || 0)]
    ];
    if (traffic && traffic.since) {
      rows.push(["统计起点", formatDate(traffic.since)]);
    }
    return rows;
  }

  function topPathList(paths) {
    if (!paths || !paths.length) {
      return h("p", { class: "muted" }, "暂无路径统计。");
    }
    return h("div", { class: "path-list" }, paths.map(function (item) {
      return h("div", { class: "path-row" },
        h("code", { title: item.path }, clip(item.path, 64)),
        h("b", {}, String(item.requests || 0))
      );
    }));
  }

  function proxyCard(proxy) {
    var probe = proxy.probe || {};
    var probeState = proxyProbeState(proxy);
    var traffic = proxy.traffic || {};
    var stub = proxy.stub || {};
    var details = [
      ["端点", proxy.endpoint || "—"],
      ["探测", probeState.detail],
      ["延迟", probe.latency_ms !== null && probe.latency_ms !== undefined ? String(probe.latency_ms) + " ms" : "—"],
      ["测试数据", probe.bytes !== null && probe.bytes !== undefined ? formatBytes(probe.bytes) : "—"],
      ["测试速度", probe.speed_bps !== null && probe.speed_bps !== undefined ? formatRate(probe.speed_bps) : "—"]
    ];
    if (proxy.test_url) {
      details.push(["测试路径", proxy.test_url]);
    }
    if (proxy.id === "gateway") {
      details.push(["连接数", stub.active !== null && stub.active !== undefined ? String(stub.active) : "—"]);
      details.push(["请求总数", stub.requests !== null && stub.requests !== undefined ? String(stub.requests) : "—"]);
    }
    if (proxy.stats_error) {
      details.push(["统计", proxy.stats_error]);
    }
    return h("article", { class: "proxy-card" },
      h("header", { class: "proxy-head" },
        h("div", {},
          h("h3", {}, proxy.name),
          h("p", { class: "proxy-kind" }, proxy.kind || "")
        ),
        statusPill(probeState.tone, probeState.label)
      ),
      h("div", { class: "proxy-url", title: proxy.endpoint || "" }, proxy.endpoint || "—"),
      h("div", { class: "proxy-grid" },
        h("div", {},
          h("h4", {}, "探测"),
          infoList(details)
        ),
        h("div", {},
          h("h4", {}, "请求统计"),
          infoList(trafficRows(traffic))
        )
      ),
      h("div", { class: "proxy-paths" },
        h("h4", {}, "高频路径"),
        topPathList(traffic.top_paths || [])
      ),
      h("footer", { class: "proxy-foot" }, "更新 " + formatDate(proxy.updated_at))
    );
  }

  async function loadProxies(options) {
    var opts = options || {};
    var container = byId("proxies-content");
    if (!state.proxies && container) {
      skeleton(container);
    }
    try {
      var data = await api("/api/proxies");
      state.proxies = data;
      if (state.view === "proxies") {
        renderProxies();
      }
    } catch (error) {
      if (!state.authenticated) {
        return;
      }
      if (state.proxies) {
        if (opts.notify !== false) {
          toast(error.message, "err");
        }
      } else if (container) {
        errorState(container, error.message, function () {
          loadProxies();
        });
      }
    }
  }

  function renderProxies() {
    var container = byId("proxies-content");
    if (!container || !state.proxies) {
      if (container) {
        skeleton(container);
      }
      return;
    }
    var data = state.proxies;
    var proxies = data.proxies || [];
    var page = h("div", {},
      pageHead("代理", "Docker 镜像、GitHub 下载和网关的探测结果与请求统计",
        [button("重新测试", "btn-sm", function () { loadProxies(); })]
      ),
      h("div", { class: "proxy-grid-page" }, proxies.map(proxyCard)),
      h("p", { class: "section-note" }, "更新 " + formatDate(data.as_of))
    );
    container.replaceChildren(page);
  }

  bind();
  setClock();
  setInterval(setClock, 15000);
  api("/api/session", { allow401: true }).then(function (session) {
    if (session && session.authenticated) {
      applySession(session);
      return showApp();
    }
    showLogin(false);
  }).catch(function (error) {
    showLogin(false);
    setLoginError(error.message || "无法连接到面板服务");
  }).finally(function () {
    var boot = byId("boot");
    if (boot) {
      boot.hidden = true;
    }
  });
})();
