import * as cheerio from "cheerio";

const FALLBACK_UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36";

const SAFE_SEARCH_MAP = { off: "-2", moderate: "-1", strict: "1" };
const TIME_FILTER_MAP = { hour: "h", day: "d", week: "w", month: "m", year: "y" };

const _extractVqd = (html) => {
  const match =
    html.match(/vqd=['"]([^'"]+)['"]/) ||
    html.match(/name=['"]vqd['"][^>]*value=['"]([^'"]+)['"]/);
  return match ? match[1] : null;
};

const _buildKl = (lang) => {
  if (!lang) return "wt-wt";
  return `${lang}-${lang}`;
};

const _resolveRedirect = (href) => {
  try {
    const parsed = new URL(href, "https://duckduckgo.com");
    if (parsed.searchParams.has("uddg")) return parsed.searchParams.get("uddg");
    if (parsed.pathname.endsWith("/y.js") && parsed.searchParams.has("u")) return parsed.searchParams.get("u");
  } catch {}
  return href;
};

const _isInternal = (url) => {
  try {
    const h = new URL(url).hostname;
    return h === "duckduckgo.com" || h.endsWith(".duckduckgo.com");
  } catch { return false; }
};

export default class DuckDuckGoEngine {
  isClientExposed = false;
  name = "DuckDuckGo";
  bangShortcut = "ddg";
  safeSearch = "off";

  settingsSchema = [
    {
      key: "safeSearch",
      label: "Safe Search",
      type: "select",
      options: ["off", "moderate", "strict"],
      description: "Filter explicit content from search results.",
    },
  ];

  configure(settings) {
    if (typeof settings.safeSearch === "string") this.safeSearch = settings.safeSearch;
  }

  async executeSearch(query, page = 1, timeFilter, context) {
    const doFetch = context?.fetch ?? fetch;
    const safe = SAFE_SEARCH_MAP[this.safeSearch];
    const headers = {
      "User-Agent": context?.userAgent?.() ?? FALLBACK_UA,
      Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
      "Accept-Language": context?.buildAcceptLanguage?.() || "en-US,en;q=0.9",
      "Accept-Encoding": "gzip, deflate, br",
      Referer: "https://duckduckgo.com/",
      "Sec-Fetch-Dest": "document",
      "Sec-Fetch-Mode": "navigate",
      "Sec-Fetch-Site": "same-origin",
      "Sec-Fetch-User": "?1",
      "Upgrade-Insecure-Requests": "1",
      ...(safe ? { Cookie: `p=${safe}` } : {}),
    };

    const params = new URLSearchParams({ q: query, kl: _buildKl(context?.lang) });
    if (safe) params.set("kp", safe);
    if (timeFilter && timeFilter !== "any" && timeFilter !== "custom" && TIME_FILTER_MAP[timeFilter]) {
      params.set("df", TIME_FILTER_MAP[timeFilter]);
    }

    const url = `https://html.duckduckgo.com/html/?${params.toString()}`;

    let response;
    if ((page || 1) <= 1) {
      response = await doFetch(url, { headers, redirect: "follow" });
    } else {
      const initRes = await doFetch(url, { headers, redirect: "follow" });
      context?.sentinel?.(initRes, this.name);
      const vqd = _extractVqd(await initRes.text());
      if (!vqd) return [];

      const s = 10 + (page - 2) * 15;
      const pageParams = new URLSearchParams(params);
      pageParams.set("s", String(s));
      pageParams.set("dc", String(s + 1));
      pageParams.set("vqd", vqd);
      pageParams.set("nextParams", "");
      pageParams.set("api", "d.js");
      pageParams.set("o", "json");
      pageParams.set("v", "l");

      response = await doFetch(`https://html.duckduckgo.com/html/?${pageParams.toString()}`, {
        headers,
        redirect: "follow",
      });
    }

    context?.sentinel?.(response, this.name);
    const html = await response.text();
    const $ = cheerio.load(html);
    const results = [];

    $(".result").each((_, el) => {
      const titleEl = $(el).find(".result__title a").first();
      const snippetEl = $(el).find(".result__snippet").first();
      const title = titleEl.text().trim();
      let href = titleEl.attr("href") || "";
      const snippet = snippetEl.text().trim();
      href = _resolveRedirect(href);
      if (title && href && href.startsWith("http") && !_isInternal(href)) {
        results.push({ title, url: href, snippet, source: this.name });
      }
    });

    return results;
  }
}
