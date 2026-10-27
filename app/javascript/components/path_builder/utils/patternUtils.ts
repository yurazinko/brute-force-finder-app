import { Segment, ParsedSource } from "../types"

export const triggerFlash = (message: string, type: "notice" | "error" = "notice") => {
  if (typeof window !== "undefined" && typeof (window as any).showGlobalFlash === "function") {
    (window as any).showGlobalFlash(message, type)
  }
}

export const parsePatternSegments = (pattern: string): Segment[] => {
  const withoutLeadingSlash = pattern.startsWith("/") ? pattern.slice(1) : pattern
  const parts = withoutLeadingSlash === "" ? [""] : withoutLeadingSlash.split("/")

  return parts.map((part): Segment => {
    if (part === "*") return { mode: "folder_wildcard", value: "" }
    if (part.length > 1 && part.endsWith("*") && !part.slice(0, -1).includes("*")) {
      return { mode: "suffix_wildcard", value: part.slice(0, -1) }
    }
    return { mode: "exact", value: part }
  })
}

export const serializePatternSegments = (segments: Segment[]): string => {
  const parts = segments.map((segment) => {
    if (segment.mode === "folder_wildcard") return "*"
    if (segment.mode === "suffix_wildcard") return `${segment.value || "item"}*`
    return segment.value
  })
  return `/${parts.join("/")}`
}

export const normalizeDomain = (hostname: string): string => hostname.toLowerCase().replace(/^www\./i, "")

export const pathFromUrl = (url: URL): string | null => {
  const pathname = url.pathname.replace(/\/+$/, "")
  return pathname && pathname !== "/" ? (pathname.startsWith("/") ? pathname : `/${pathname}`) : null
}

export const parseSourceInput = (raw: string): ParsedSource => {
  const lines = raw.split(/\r?\n/).map((line) => line.trim()).filter(Boolean)
  if (!lines.length) throw new Error("Enter a domain or paste a full URL.")

  const parsed = lines.map((line) => {
    const value = /^[a-z][a-z\d+.-]*:\/\//i.test(line) ? line : `https://${line}`
    const url = new URL(value)
    if (!["http:", "https:"].includes(url.protocol)) throw new Error("Only HTTP and HTTPS URLs are supported.")
    if (!url.hostname) throw new Error(`Could not read a domain from: ${line}`)
    return { domain: normalizeDomain(url.hostname), pattern: pathFromUrl(url) }
  })

  const domains = [...new Set(parsed.map((item) => item.domain))]
  if (domains.length > 1) {
    throw new Error("Use URLs from one domain per target. Create another target for a different domain.")
  }

  return {
    domain: domains[0],
    patterns: [...new Set(parsed.map((item) => item.pattern).filter((value): value is string => Boolean(value)))],
  }
}

export const isUrlLike = (value: string): boolean =>
  value.includes("://") || /^\s*[^\s/]+\.[^\s/]+\/.+/m.test(value)