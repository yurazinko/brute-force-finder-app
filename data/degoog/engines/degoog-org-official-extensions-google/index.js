import * as cheerio from "cheerio";

const NOKIA_USER_AGENTS = [
  "Nokia7610/2.0 (5.0509.0) SymbianOS/7.0s Series60/2.1 Profile/MIDP-2.0 Configuration/CLDC-1.0",
  "Nokia7610/2.0 (7.0642.0) SymbianOS/7.0s Series60/2.1 Profile/MIDP-2.0 Configuration/CLDC-1.0",
  "Nokia6230/2.0 (05.50) Profile/MIDP-2.0 Configuration/CLDC-1.1",
  "Nokia6230i/2.0 (03.80) Profile/MIDP-2.0 Configuration/CLDC-1.1",
  "Nokia6280/2.0 (03.60) Profile/MIDP-2.0 Configuration/CLDC-1.1",
  "NokiaN72/2.0617.1.0.3 Series60/2.8 Profile/MIDP-2.0 Configuration/CLDC-1.1",
];

const _nokiaAgent = () =>
  NOKIA_USER_AGENTS[Math.floor(Math.random() * NOKIA_USER_AGENTS.length)];

const TBS_MAP = {
  hour: "qdr:h",
  day: "qdr:d",
  week: "qdr:w",
  month: "qdr:m",
  year: "qdr:y",
};

const _resolveTbs = (timeFilter) => {
  if (!timeFilter || timeFilter === "any" || timeFilter === "custom")
    return null;
  return TBS_MAP[timeFilter] ?? null;
};

const _resolveCustomTbs = (dateFrom, dateTo) => {
  if (!dateFrom && !dateTo) return null;
  const parts = ["cdr:1"];
  if (dateFrom) {
    const d = new Date(dateFrom);
    if (!isNaN(d.getTime()))
      parts.push(
        `cd_min:${d.getMonth() + 1}/${d.getDate()}/${d.getFullYear()}`,
      );
  }
  if (dateTo) {
    const d = new Date(dateTo);
    if (!isNaN(d.getTime()))
      parts.push(
        `cd_max:${d.getMonth() + 1}/${d.getDate()}/${d.getFullYear()}`,
      );
  }
  return parts.length > 1 ? parts.join(",") : null;
};

const _resolveHref = (href) => {
  if (!href.startsWith("/url?")) return href;
  try {
    const parsed = new URL(href, "https://www.google.com");
    return (
      parsed.searchParams.get("q") || parsed.searchParams.get("url") || href
    );
  } catch {
    return href;
  }
};

const MUTANT_SIGNATURES = [
  "/httpservice/retry/enablejs",
  'Please click <a href="/httpservice',
  "unusual traffic from your computer network",
  "/sorry/index?continue=",
];

const UDM_WEB_ONLY = "14";
const SERP_READY_SELECTOR = "#search h3, #rso h3";
const SERP_SORRY_PATH = "/sorry/";

const _isInterstitial = (html) => {
  const head = html.slice(0, 4000);
  return MUTANT_SIGNATURES.some((m) => head.includes(m));
};

const GOTO_PREFIX = "/goto?";
const GOTO_ORIGIN = "https://www.google.com";
const GOTO_TIMEOUT_MS = 5000;

const _isExternal = (url) =>
  url.startsWith("http") && !url.includes("google.com");

const _parseDesktop = ($, name) => {
  const results = [];
  const seen = new Set();
  $("a:has(h3)").each((_, el) => {
    const linkEl = $(el);
    const href = linkEl.attr("href") || "";
    const goto = href.startsWith(GOTO_PREFIX) ? `${GOTO_ORIGIN}${href}` : "";
    const url = goto || _resolveHref(href);
    if (!goto && !_isExternal(url)) return;
    const title = linkEl.find("h3").first().text().trim();
    if (!title || seen.has(url)) return;
    seen.add(url);
    const block = linkEl.closest("[data-hveid]");
    const snippet =
      block.find("[data-sncf]").first().text().trim() ||
      block.find(".VwiC3b").first().text().trim() ||
      "";
    results.push({ title, url, snippet, source: name });
  });
  return results;
};

const _followGoto = async (url, userAgent) => {
  try {
    const response = await fetch(url, {
      method: "GET",
      redirect: "manual",
      headers: { "User-Agent": userAgent },
      signal: AbortSignal.timeout(GOTO_TIMEOUT_MS),
    });
    await response.body?.cancel();
    const location = response.headers.get("location") || "";
    return _isExternal(location) ? location : "";
  } catch {
    return "";
  }
};

const _resolveGotos = async (results, userAgent) => {
  const resolved = await Promise.all(
    results.map(async (result) =>
      result.url.startsWith(GOTO_ORIGIN)
        ? { ...result, url: await _followGoto(result.url, userAgent) }
        : result,
    ),
  );
  const seen = new Set();
  return resolved.filter((result) => {
    if (!result.url || seen.has(result.url)) return false;
    seen.add(result.url);
    return true;
  });
};

const _parseWml = ($, name) => {
  const results = [];
  const seen = new Set();
  $("div.zMzFAb").each((_, el) => {
    const block = $(el);
    const linkEl = block.find("a.fuLhoc").first();
    const title = linkEl.find("span.CVA68e").first().text().trim();
    const url = _resolveHref(linkEl.attr("href") || "");
    if (!title || !url.startsWith("http") || seen.has(url)) return;
    seen.add(url);
    const snippet = block.find("div.taTFJ span.FrIlee").text().trim();
    results.push({ title, url, snippet, source: name });
  });
  return results;
};

export const description =
  "Google web search. Lite results come from Google's old mobile page and work over any transport, but Google rate-limits that page per IP and busy instances start getting CAPTCHAs. The [4play (lolcat)](https://github.com/degoog-org/official-extensions/tree/main/transports/lolcat-4play) transport is still the recommended way to run this engine. It fetches through a real Firefox session, and HTML results only work with it. Install 4play from the Store tab and select it as this engine's transport. If you can't run 4play, use lite results or the Google CSE engine.";

export default class GoogleEngine {
  isClientExposed = false;
  name = "Google";
  bangShortcut = "g";
  safeSearch = "off";
  resultsFormat = "lite";
  settingsSchema = [
    {
      key: "outgoingTransport",
      label: "Outgoing HTTP client transport",
      type: "select",
      options: ["fetch", "curl", "curl-fallback"],
      default: "curl",
      advanced: true,
    },
    {
      key: "resultsFormat",
      label: "Results format",
      type: "select",
      options: ["lite", "html"],
      optionLabels: ["Lite results", "HTML results"],
      default: "lite",
      description:
        "Lite results come from Google's old mobile page and work without 4play, though Google rate-limits them per IP. HTML results fetch the full desktop page for better titles and snippets, and they need the [4play (lolcat)](https://github.com/degoog-org/official-extensions/tree/main/transports/lolcat-4play) transport selected above. Use 4play for either mode if you can.",
    },
    {
      key: "safeSearch",
      label: "Safe Search",
      type: "select",
      options: ["off", "on"],
      description: "Filter explicit content from search results.",
    },
  ];

  configure(settings) {
    if (typeof settings.safeSearch === "string")
      this.safeSearch = settings.safeSearch;
    if (settings.resultsFormat === "lite" || settings.resultsFormat === "html")
      this.resultsFormat = settings.resultsFormat;
  }

  _buildParams(query, page, timeFilter, context) {
    const start = (page - 1) * 10;
    const lang = context?.lang || "en";
    const params = new URLSearchParams({
      q: query,
      hl: lang,
      lr: `lang_${lang}`,
      ie: "utf8",
      oe: "utf8",
      start: String(start),
      filter: "0",
      udm: UDM_WEB_ONLY,
    });

    const tbs =
      timeFilter === "custom"
        ? _resolveCustomTbs(context?.dateFrom, context?.dateTo)
        : _resolveTbs(timeFilter);
    if (tbs) params.set("tbs", tbs);
    if (this.safeSearch === "on") params.set("safe", "active");
    return params;
  }

  async _request(params, userAgent, context) {
    const doFetch = context?.fetch ?? fetch;
    const response = await doFetch(
      `https://www.google.com/search?${params.toString()}`,
      {
        headers: {
          "User-Agent": userAgent,
          Accept:
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
          "Accept-Language":
            context?.buildAcceptLanguage?.() || "en-US,en;q=0.9",
          Cookie: "CONSENT=YES+",
        },
        match: {
          domMatch: SERP_READY_SELECTOR,
          failUrlMatch: SERP_SORRY_PATH,
        },
        redirect: "follow",
      },
    );

    context?.sentinel?.(response, this.name);
    const html = await response.text();

    if (_isInterstitial(html)) {
      if (context?.engineError) {
        throw context.engineError(
          "interstitial",
          `${this.name} returned a JavaScript/consent interstitial`,
          { engine: this.name },
        );
      }
      throw new Error(
        `${this.name} returned a JavaScript/consent interstitial`,
      );
    }
    return html;
  }

  async executeSearch(query, page = 1, timeFilter, context) {
    if (this.resultsFormat === "html") {
      return this._searchHtml(query, page, timeFilter, context);
    }
    return this._searchLite(query, page, timeFilter, context);
  }

  async _searchHtml(query, page, timeFilter, context) {
    const params = this._buildParams(query, page, timeFilter, context);
    const userAgent = context?.userAgent?.() || _nokiaAgent();
    const html = await this._request(params, userAgent, context);
    return _resolveGotos(
      _parseDesktop(cheerio.load(html), this.name),
      userAgent,
    );
  }

  async _searchLite(query, page = 1, timeFilter, context) {
    const start = (page - 1) * 10;
    const lang = context?.lang || "en";
    const params = new URLSearchParams({
      q: query,
      sca_esv: "1",
      hl: lang,
      lr: `lang_${lang}`,
      ie: "utf8",
      oe: "utf8",
    });
    if (start) params.set("start", String(start));

    const tbs =
      timeFilter === "custom"
        ? _resolveCustomTbs(context?.dateFrom, context?.dateTo)
        : _resolveTbs(timeFilter);
    if (tbs) params.set("tbs", tbs);
    if (this.safeSearch === "on") params.set("safe", "active");

    const doFetch = context?.fetch ?? fetch;
    const response = await doFetch(
      `https://www.google.com/wml/search?${params.toString()}`,
      {
        headers: {
          "User-Agent": _nokiaAgent(),
          Accept: "*/*",
          "Accept-Language":
            context?.buildAcceptLanguage?.() || "en-US,en;q=0.9",
          Cookie: "CONSENT=YES+",
        },
        redirect: "follow",
      },
    );

    if ((response.url || "").includes(SERP_SORRY_PATH)) {
      if (context?.engineError) {
        throw context.engineError(
          "captcha",
          `${this.name} returned a CAPTCHA page`,
          { httpStatus: response.status, engine: this.name },
        );
      }
      throw new Error(`${this.name} returned a CAPTCHA page`);
    }

    context?.sentinel?.(response, this.name);
    const html = await response.text();

    if (_isInterstitial(html)) {
      if (context?.engineError) {
        throw context.engineError(
          "interstitial",
          `${this.name} returned a JavaScript/consent interstitial`,
          { engine: this.name },
        );
      }
      throw new Error(
        `${this.name} returned a JavaScript/consent interstitial`,
      );
    }

    return _parseWml(cheerio.load(html), this.name);
  }
}
