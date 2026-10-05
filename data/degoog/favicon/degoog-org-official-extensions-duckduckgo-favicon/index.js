const HOST_PATTERN = /^[a-z0-9.-]+$/;
const MAX_HOST_LENGTH = 253;

const _cleanHost = (host) => {
  if (typeof host !== "string") return "";
  const value = host.trim().toLowerCase();
  if (!value || value.length > MAX_HOST_LENGTH) return "";
  if (!HOST_PATTERN.test(value)) return "";
  if (value.startsWith(".") || value.endsWith(".") || value.includes("..")) return "";
  return value;
};

export default class DuckDuckGoFaviconProvider {
  name = "DuckDuckGo Favicons";
  description = "DuckDuckGo's icon service. Some icons come back small.";

  configure() {}

  async getFavicon(host) {
    const clean = _cleanHost(host);
    if (!clean) return null;
    return { url: `https://icons.duckduckgo.com/ip3/${clean}.ico` };
  }
}
