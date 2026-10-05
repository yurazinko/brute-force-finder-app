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

export default class GoogleFaviconProvider {
  name = "Google Favicons";
  description = "Google's favicon service, the icons degoog has always shown.";

  configure() {}

  async getFavicon(host, context) {
    const clean = _cleanHost(host);
    if (!clean) return null;
    const size = Number(context?.size) || 32;
    return { url: `https://www.google.com/s2/favicons?domain=${clean}&sz=${size}` };
  }
}
