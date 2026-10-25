import React, { useState, useRef, useEffect } from "react"

export interface Pattern {
  id: number | string
  path_pattern: string
  is_active: boolean
}

export interface Category {
  id: number | string
  name: string
}

export interface SearchOption {
  id: number | string
  title: string
  status?: string
}

export interface PathBuilderProps {
  /** `pattern` preserves the result-modal flow; `target` uses the unified target editor. */
  mode?: "pattern" | "target"
  targetDomain: string
  initialPatterns: Pattern[]
  categories: Category[]
  searches?: SearchOption[]
  targetId?: number | string
  targetName?: string
  targetCategoryId?: number | string
  targetIsActive?: boolean
  targetAllowQueryStrings?: boolean
  initialSearchIds?: Array<number | string>
  targetCreateEndpoint?: string
  targetUpdateEndpoint?: string
  cancelPath?: string
  resultUrl?: string
  matchedTargetId?: number
  resultId?: number | string
  authenticityToken: string
  createEndpoint: string
  redirectPath: string
  onPatternsChange?: (patterns: Pattern[]) => void
}

type SegmentMode = "exact" | "folder_wildcard" | "suffix_wildcard"

interface Segment {
  mode: SegmentMode
  value: string
}

/** Parse a saved pattern into editable controls without rewriting unfamiliar wildcard syntax. */
const parsePatternSegments = (pattern: string): Segment[] => {
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

/** Segment editor serialization keeps blank segments intact while a user is typing. */
const serializePatternSegments = (segments: Segment[]): string => {
  const parts = segments.map((segment) => {
    if (segment.mode === "folder_wildcard") return "*"
    if (segment.mode === "suffix_wildcard") return `${segment.value || "item"}*`
    return segment.value
  })
  return `/${parts.join("/")}`
}

const PatternBuilder: React.FC<PathBuilderProps> = ({
  targetDomain,
  initialPatterns,
  categories,
  resultUrl,
  matchedTargetId,
  resultId,
  authenticityToken,
  createEndpoint,
  onPatternsChange,
}) => {
  const [patterns, setPatterns] = useState<Pattern[]>(initialPatterns)
  const commitPatterns = (next: Pattern[]) => {
    setPatterns(next)
    onPatternsChange?.(next)
  }
  const [editingId, setEditingId] = useState<number | string | null>(null)
  const [editingValue, setEditingValue] = useState<string>("")
  const [editingSegments, setEditingSegments] = useState<Segment[]>([{ mode: "exact", value: "" }])
  const [activeEditDropdownIndex, setActiveEditDropdownIndex] = useState<number | null>(null)
  const [isSavingEdit, setIsSavingEdit] = useState(false)
  const [patternEditError, setPatternEditError] = useState("")

  const [isAccordionOpen, setIsAccordionOpen] = useState<boolean>(false)

  const [segments, setSegments] = useState<Segment[]>([{ mode: "exact", value: "" }])
  const [selectedCategory, setSelectedCategory] = useState<string>("")
  const [newCategoryName, setNewCategoryName] = useState<string>("")
  const [allowQueryStrings, setAllowQueryStrings] = useState<boolean>(false)
  const [error, setError] = useState<boolean>(false)
  const [isSubmitting, setIsSubmitting] = useState<boolean>(false)

  const [activeDropdownIndex, setActiveDropdownIndex] = useState<number | null>(null)
  const dropdownRef = useRef<HTMLDivElement>(null)
  const editingDropdownRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setActiveDropdownIndex(null)
      }
      if (editingDropdownRef.current && !editingDropdownRef.current.contains(e.target as Node)) {
        setActiveEditDropdownIndex(null)
      }
    }
    document.addEventListener("mousedown", handleClickOutside)
    return () => document.removeEventListener("mousedown", handleClickOutside)
  }, [])

  const computePatternString = (segs: Segment[]): string => {
    const parts = segs.map((seg) => {
      if (seg.mode === "exact") return seg.value || "new"
      if (seg.mode === "folder_wildcard") return "*"
      if (seg.mode === "suffix_wildcard") {
        const baseVal = seg.value === "new" || !seg.value ? "item" : seg.value
        return `${baseVal}*`
      }
      return seg.value
    })
    let res = "/" + parts.join("/")
    if (res.endsWith("/*/*")) res = res.replace("/*/*", "/*")
    return res
  }

  const currentPatternString = computePatternString(segments)

  const getInterpretationText = (pattern: string) => {
    if (pattern.includes("*")) {
      return `Will dynamically match any URL starting or matching with pattern structure: ${pattern}`
    }
    return `Will match exact path: ${pattern}`
  }

  const handleOpenAccordion = () => {
    if (resultUrl && resultUrl.trim() !== "") {
      try {
        const urlObj = new URL(resultUrl)
        const cleanPath = urlObj.pathname.replace(/^\/+/, "").replace(/\/+$/, "")
        const pathSegments = cleanPath ? cleanPath.split("/") : [""]
        setSegments(pathSegments.map((seg) => ({ mode: "exact", value: seg })))
      } catch (e) {
        setSegments([{ mode: "exact", value: "" }])
      }
    } else {
      setSegments([{ mode: "exact", value: "" }])
    }
    setIsAccordionOpen(true)
    setError(false)
  }

  const handleAddSegment = () => {
    setSegments([...segments, { mode: "exact", value: "new" }])
    setActiveDropdownIndex(null)
  }

  const handleCutFromHere = (index: number) => {
    setSegments(segments.slice(0, index + 1))
    setActiveDropdownIndex(null)
  }

  const handleSetMode = (index: number, mode: SegmentMode) => {
    const updated = [...segments]
    updated[index].mode = mode
    setSegments(updated)
    setActiveDropdownIndex(null)
  }

  const handleCustomInputSubmit = (index: number, text: string) => {
    const val = text.trim()
    if (!val) return

    if (val.startsWith("http://") || val.startsWith("https://") || val.includes("://")) {
      try {
        const urlObj = new URL(val)
        const cleanPath = urlObj.pathname.replace(/^\/+/, "").replace(/\/+$/, "")
        const pathSegments = cleanPath ? cleanPath.split("/") : [""]
        setSegments(pathSegments.map((seg) => ({ mode: "exact", value: seg })))
        setActiveDropdownIndex(null)
        return
      } catch (e) {}
    }

    const updated = [...segments]
    updated[index] = { mode: "exact", value: val }
    setSegments(updated)
    setActiveDropdownIndex(null)
  }

  const handleCreatePattern = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!matchedTargetId && !selectedCategory && !newCategoryName.trim()) {
      setError(true)
      return
    }
    setError(false)
    setIsSubmitting(true)

    try {
      const payload: Record<string, any> = {
        path_pattern: currentPatternString,
        allow_query_strings: allowQueryStrings ? "1" : "0"
      }

      if (matchedTargetId) {
        payload.target_id = matchedTargetId
      } else {
        payload.domain = targetDomain
        if (selectedCategory) {
          payload.category_id = selectedCategory
        } else if (newCategoryName.trim()) {
          payload.category_name = newCategoryName.trim()
        }
      }

      if (resultId) {
        payload.result_id = resultId
      }

      const response = await fetch(createEndpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": authenticityToken,
          "Accept": "application/json, text/vnd.turbo-stream.html"
        },
        body: JSON.stringify({
          target_pattern: payload
        })
      })

      if (response.ok) {
        const contentType = response.headers.get("content-type")
        if (contentType && contentType.includes("application/json")) {
          const data = await response.json()
          const savedPattern: Pattern = data.pattern || {
            id: data.id || Date.now(),
            path_pattern: currentPatternString,
            is_active: true
          }
          commitPatterns([...patterns, savedPattern])
          setIsAccordionOpen(false)
          setSegments([{ mode: "exact", value: "" }])
          setNewCategoryName("")
          setSelectedCategory("")
        } else {
          window.location.reload()
        }
      } else {
        setError(true)
      }
    } catch (err) {
      console.error("Failed to create pattern:", err)
      setError(true)
    } finally {
      setIsSubmitting(false)
    }
  }

  const updateEditingSegments = (nextSegments: Segment[]) => {
    const safeSegments = nextSegments.length ? nextSegments : [{ mode: "exact" as const, value: "" }]
    setEditingSegments(safeSegments)
    setEditingValue(serializePatternSegments(safeSegments))
    setPatternEditError("")
  }

  const handleEditSegmentMode = (index: number, mode: SegmentMode) => {
    const nextSegments = editingSegments.map((segment, segmentIndex) => {
      if (segmentIndex !== index) return segment
      const value = mode === "exact" && segment.mode === "folder_wildcard" && !segment.value
        ? "new"
        : segment.value
      return { ...segment, mode, value }
    })
    updateEditingSegments(nextSegments)
    setActiveEditDropdownIndex(null)
  }

  const handleEditSegmentInput = (index: number, rawValue: string) => {
    const value = rawValue.trim()
    if (!value) return

    // If a full URL is pasted here, use only its pathname as the pattern source.
    if (/^(https?:\/\/|[a-z][a-z\d+.-]*:\/\/)/i.test(value)) {
      try {
        const url = new URL(value)
        const pathname = url.pathname.replace(/^\/+/, "").replace(/\/+$/, "")
        const nextSegments = (pathname ? pathname.split("/") : [""]).map((part) => ({
          mode: "exact" as const,
          value: part,
        }))
        updateEditingSegments(nextSegments)
        setActiveEditDropdownIndex(null)
        return
      } catch {
        // Invalid URL-like input can still be entered as a literal segment.
      }
    }

    const nextSegments = editingSegments.map((segment, segmentIndex) =>
      segmentIndex === index ? { mode: "exact" as const, value } : segment,
    )
    updateEditingSegments(nextSegments)
    setActiveEditDropdownIndex(null)
  }

  const cancelPatternEdit = () => {
    setEditingId(null)
    setActiveEditDropdownIndex(null)
    setPatternEditError("")
  }

  const handleToggleEdit = async (pattern: Pattern) => {
    if (editingId === pattern.id) {
      const pathPattern = editingValue.trim()
      if (!pathPattern) {
        setPatternEditError("Pattern cannot be empty.")
        return
      }

      setIsSavingEdit(true)
      setPatternEditError("")
      try {
        const response = await fetch(`/target_patterns/${pattern.id}`, {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": authenticityToken,
            "Accept": "application/json"
          },
          body: JSON.stringify({ target_pattern: { path_pattern: pathPattern } })
        })

        if (!response.ok) throw new Error(`HTTP ${response.status}`)

        commitPatterns(
          patterns.map((p) => (p.id === pattern.id ? { ...p, path_pattern: pathPattern } : p))
        )
        cancelPatternEdit()
      } catch (err) {
        console.error("Failed to update pattern", err)
        setPatternEditError("Could not save this pattern. Your edits have been kept; please try again.")
      } finally {
        setIsSavingEdit(false)
      }
    } else {
      setEditingId(pattern.id)
      setEditingValue(pattern.path_pattern)
      setEditingSegments(parsePatternSegments(pattern.path_pattern))
      setActiveEditDropdownIndex(null)
      setPatternEditError("")
    }
  }

  const handleToggleActive = async (pattern: Pattern) => {
    const nextState = !pattern.is_active
    try {
      const response = await fetch(`/target_patterns/${pattern.id}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": authenticityToken,
          "Accept": "application/json"
        },
        body: JSON.stringify({
          target_pattern: { is_active: nextState }
        })
      })

      if (response.ok) {
        commitPatterns(
          patterns.map((p) => (p.id === pattern.id ? { ...p, is_active: nextState } : p))
        )
      }
    } catch (err) {
      console.error("Failed to toggle status", err)
    }
  }

  const handleDeletePattern = async (id: number | string) => {
    if (!confirm("Are you sure you want to delete this pattern?")) return
    try {
      const response = await fetch(`/target_patterns/${id}`, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": authenticityToken,
          "Accept": "application/json"
        }
      })

      if (response.ok) {
        commitPatterns(patterns.filter((p) => p.id !== id))
      }
    } catch (err) {
      console.error("Failed to delete pattern", err)
    }
  }

  return (
    <div className="space-y-6 font-sans">
      <div className="bg-breeze-view p-4 shadow-sm border border-breeze-border rounded-xl space-y-4">
        <div className="flex items-center justify-between border-b border-breeze-border/60 pb-3">
          <div>
            <h2 className="text-xs font-bold text-breeze-muted uppercase tracking-wider flex items-center gap-1.5">
              <span>🛤️</span>
              <span>Configured URL Path Patterns</span>
            </h2>
            <p className="text-[11px] text-breeze-muted mt-0.5">
              If no patterns are added, all paths under <strong>{targetDomain}</strong> are accepted.
            </p>
          </div>
          <span className="bg-breeze-accent/15 text-breeze-accent border border-breeze-accent/20 text-xs font-mono font-bold px-2.5 py-0.5 rounded-full">
            {patterns.length}
          </span>
        </div>

        <div className="space-y-2">
          {patterns.length > 0 ? (
            patterns.map((pattern) => {
              const isEditing = editingId === pattern.id
              return (
                <div
                  key={pattern.id}
                  className={`${isEditing ? "flex flex-col items-stretch" : "flex items-center justify-between"} bg-breeze-bg p-3 rounded-lg border border-breeze-border/60 font-mono text-xs gap-4`}
                >
                  <div className={isEditing ? "w-full min-w-0 space-y-3" : "flex items-center flex-1 min-w-0"}>
                    {isEditing ? (
                      <>
                        <div className="space-y-1.5">
                          <label className="block text-[10px] font-sans font-semibold uppercase tracking-wider text-breeze-muted">Pattern text (editable)</label>
                          <input
                            type="text"
                            value={editingValue}
                            onChange={(event) => {
                              const value = event.target.value
                              setEditingValue(value)
                              setEditingSegments(parsePatternSegments(value))
                              setPatternEditError("")
                            }}
                            className="w-full text-xs font-mono bg-breeze-view text-breeze-text px-2.5 py-2 rounded border border-breeze-accent outline-none font-sans"
                            autoFocus
                            aria-label={`Edit pattern text ${pattern.path_pattern}`}
                            onKeyDown={(event) => {
                              if (event.key === "Enter") {
                                event.preventDefault()
                                void handleToggleEdit(pattern)
                              }
                              if (event.key === "Escape") cancelPatternEdit()
                            }}
                          />
                          <p className="text-[10px] font-sans text-breeze-muted">Edit the path directly, or use the segment controls below. Changes are synchronized.</p>
                          {patternEditError && <p role="alert" className="text-[10px] font-sans text-red-400">{patternEditError}</p>}
                        </div>

                        <div className="space-y-1.5">
                          <label className="block text-[10px] font-sans font-semibold uppercase tracking-wider text-breeze-muted">Edit by segments</label>
                          <div className="flex flex-wrap items-center gap-1.5 p-2.5 bg-breeze-view rounded-lg border border-breeze-border/60 font-mono text-xs">
                            {editingSegments.map((segment, index) => {
                              const isLast = index === editingSegments.length - 1
                              const isOpen = activeEditDropdownIndex === index
                              let labelText = segment.value || "segment"
                              if (segment.mode === "folder_wildcard") labelText = "✨ Any value"
                              if (segment.mode === "suffix_wildcard") labelText = `${segment.value || "item"}* (starts with)`
                              const inputId = `pattern-edit-segment-${String(pattern.id)}-${index}`

                              return (
                                <React.Fragment key={`${String(pattern.id)}-${index}`}>
                                  <span className="text-breeze-muted shrink-0">/</span>
                                  <div className="relative inline-block" ref={isOpen ? editingDropdownRef : null}>
                                    <button
                                      type="button"
                                      onClick={() => setActiveEditDropdownIndex(isOpen ? null : index)}
                                      className="px-2.5 py-1.5 rounded bg-breeze-bg hover:bg-breeze-border/40 text-breeze-text border border-breeze-border transition flex items-center gap-2 shadow-2xs font-semibold truncate min-w-[90px] max-w-[200px]"
                                      title={labelText}
                                      aria-expanded={isOpen}
                                    >
                                      <span className="truncate">{labelText}</span>
                                      <span className="text-[10px] text-breeze-muted shrink-0">▼</span>
                                    </button>

                                    {isOpen && (
                                      <div className="absolute left-0 top-full mt-1 z-50 bg-breeze-view border border-breeze-border rounded-lg shadow-2xl py-1 text-[11px] font-sans" style={{ width: "300px" }}>
                                        <div className="p-2.5 border-b border-breeze-border/40 bg-breeze-bg/40 space-y-1.5">
                                          <div className="flex items-center gap-1.5">
                                            <input
                                              id={inputId}
                                              type="text"
                                              placeholder="Segment text or full URL..."
                                              defaultValue={segment.mode === "exact" ? segment.value : ""}
                                              onKeyDown={(event) => {
                                                if (event.key === "Enter") {
                                                  event.preventDefault()
                                                  handleEditSegmentInput(index, (event.target as HTMLInputElement).value)
                                                }
                                              }}
                                              className="w-full text-[11px] px-2.5 py-1.5 bg-breeze-view text-breeze-text rounded border border-breeze-border outline-none focus:border-breeze-accent"
                                              autoFocus
                                            />
                                            <button
                                              type="button"
                                              onClick={() => {
                                                const input = document.getElementById(inputId) as HTMLInputElement | null
                                                if (input) handleEditSegmentInput(index, input.value)
                                              }}
                                              className="px-3 py-1.5 bg-breeze-accent text-white font-bold rounded hover:opacity-95 transition shrink-0 text-xs"
                                            >Apply</button>
                                          </div>
                                        </div>
                                        <button type="button" onClick={() => handleEditSegmentMode(index, "exact")} className="w-full text-left px-3 py-2 hover:bg-breeze-accent/20 text-breeze-text font-semibold truncate">🔒 Exact match</button>
                                        <button type="button" onClick={() => handleEditSegmentMode(index, "folder_wildcard")} className="w-full text-left px-3 py-2 hover:bg-breeze-accent/20 text-breeze-accent truncate">✨ Any value</button>
                                        {isLast && <button type="button" onClick={() => handleEditSegmentMode(index, "suffix_wildcard")} className="w-full text-left px-3 py-2 hover:bg-breeze-accent/20 text-breeze-accent truncate">🔤 Starts with this text</button>}
                                        <button
                                          type="button"
                                          onClick={() => {
                                            updateEditingSegments(editingSegments.slice(0, index + 1))
                                            setActiveEditDropdownIndex(null)
                                          }}
                                          className="w-full text-left px-3 py-2 hover:bg-red-500/20 text-red-400 truncate border-t border-breeze-border/40"
                                        >🛑 Cut path from here</button>
                                      </div>
                                    )}
                                  </div>
                                </React.Fragment>
                              )
                            })}
                            <button
                              type="button"
                              onClick={() => updateEditingSegments([...editingSegments, { mode: "exact", value: "new" }])}
                              className="shrink-0 w-8 h-8 rounded-lg bg-breeze-bg hover:bg-breeze-accent/20 text-breeze-accent border border-breeze-border flex items-center justify-center font-bold text-sm shadow-2xs transition"
                              title="Add path segment"
                            >+</button>
                          </div>
                        </div>
                      </>
                    ) : (
                      <span className="text-breeze-accent font-bold truncate">{pattern.path_pattern}</span>
                    )}
                  </div>

                  <div className={`${isEditing ? "flex items-center justify-between gap-3 w-full pt-2 border-t border-breeze-border/50" : "flex items-center gap-3 shrink-0"} font-sans`}>
                    <span
                      className={`text-[10px] px-2 py-0.5 rounded font-sans ${
                        pattern.is_active
                          ? "bg-green-500/10 text-green-400 border border-green-500/20"
                          : "bg-gray-500/10 text-gray-400"
                      }`}
                    >
                      {pattern.is_active ? "Active" : "Disabled"}
                    </span>

                    <span>|</span>

                    <div className="flex items-center gap-2">
                      <button
                        type="button"
                        onClick={() => void handleToggleEdit(pattern)}
                        disabled={isSavingEdit}
                        className={`text-[11px] px-2 py-1 rounded transition cursor-pointer border disabled:opacity-50 ${
                          isEditing
                            ? "bg-gradient-to-r from-blue-600 to-indigo-600 text-white font-bold border-transparent"
                            : "bg-breeze-view hover:bg-breeze-border/40 text-breeze-muted hover:text-breeze-text border-breeze-border"
                        }`}
                      >
                        {isEditing && isSavingEdit ? "Saving..." : isEditing ? "Save" : "Edit"}
                      </button>
                      {isEditing && (
                        <button type="button" onClick={cancelPatternEdit} disabled={isSavingEdit} className="text-[11px] px-2 py-1 rounded border border-breeze-border bg-breeze-view hover:bg-breeze-border/40 text-breeze-muted disabled:opacity-50">Cancel</button>
                      )}

                      <button
                        type="button"
                        onClick={() => handleToggleActive(pattern)}
                        className="text-[11px] px-2 py-1 bg-breeze-view hover:bg-breeze-border/40 text-breeze-muted hover:text-breeze-text border border-breeze-border rounded transition cursor-pointer"
                      >
                        {pattern.is_active ? "Disable" : "Enable"}
                      </button>

                      <button
                        type="button"
                        onClick={() => handleDeletePattern(pattern.id)}
                        className="text-[11px] px-2 py-1 bg-red-500/10 hover:bg-red-500/20 text-red-400 border border-red-500/30 rounded transition cursor-pointer"
                      >
                        Delete
                      </button>
                    </div>
                  </div>
                </div>
              )
            })
          ) : (
            <div className="text-center py-4 bg-breeze-bg/40 rounded-lg border border-dashed border-breeze-border/60 text-xs text-breeze-muted italic">
              No custom path patterns configured yet.
            </div>
          )}
        </div>
      </div>

      <div>
        {!isAccordionOpen ? (
          <button
            type="button"
            onClick={handleOpenAccordion}
            className="w-full py-3 px-4 bg-breeze-view hover:bg-breeze-border/30 border border-dashed border-breeze-border rounded-xl text-xs font-bold text-breeze-accent flex items-center justify-center gap-2 transition cursor-pointer shadow-2xs"
          >
            <span className="text-sm">+</span>
            <span>Add New Pattern</span>
          </button>
        ) : (
          <form
            onSubmit={handleCreatePattern}
            className="bg-breeze-view p-5 rounded-xl border border-breeze-border shadow-sm space-y-5 mt-4"
          >
            {error && (
              <div className="p-3 bg-red-500/10 border border-red-500/30 rounded-lg text-xs text-red-400 font-semibold flex items-center gap-2">
                <span>⚠️</span>
                <span>Category or Target can't be blank</span>
              </div>
            )}

            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 p-3.5 bg-breeze-bg rounded-lg border border-breeze-border/60">
              <div className="flex items-center gap-2 truncate">
                <span className="text-xs font-semibold text-breeze-muted shrink-0">Target Site:</span>
                <span className="text-xs font-mono font-bold text-breeze-accent bg-breeze-accent/10 px-2.5 py-1 rounded border border-breeze-accent/20 truncate">
                  {targetDomain}
                </span>
              </div>

              {matchedTargetId ? (
                <div className="flex items-center gap-1.5 text-[11px] text-emerald-400 shrink-0 font-medium">
                  <span>🔗 Linking to existing target</span>
                </div>
              ) : (
                <div className="flex items-center gap-2 shrink-0">
                  <span className="text-[11px] text-breeze-muted">Category:</span>
                  <select
                    value={selectedCategory}
                    onChange={(e) => setSelectedCategory(e.target.value)}
                    className="text-xs font-sans bg-breeze-view text-breeze-text rounded-md border border-breeze-border px-2.5 py-1.5 focus:border-breeze-accent outline-none cursor-pointer"
                  >
                    <option value="">Select category...</option>
                    {categories.map((cat) => (
                      <option key={cat.id} value={cat.id}>
                        {cat.name}
                      </option>
                    ))}
                  </select>
                  <span className="text-[11px] text-breeze-muted">or</span>
                  <input
                    type="text"
                    placeholder="New category name..."
                    value={newCategoryName}
                    onChange={(e) => setNewCategoryName(e.target.value)}
                    className="text-xs font-sans bg-breeze-view text-breeze-text rounded-md border border-breeze-border px-2.5 py-1.5 outline-none w-36"
                  />
                </div>
              )}
            </div>

            <div className="space-y-2">
              <label className="block text-xs font-semibold text-breeze-text">Add New Path Pattern:</label>
              <p className="text-[11px] text-breeze-muted">
                Click segments to configure matching rules, type custom text, or paste a full URL to auto-fill.
              </p>

              <div className="flex flex-wrap items-center gap-1.5 p-3.5 bg-breeze-bg rounded-lg border border-breeze-border font-mono text-xs">
                {segments.map((segment, index) => {
                  const isLast = index === segments.length - 1
                  const isOpen = activeDropdownIndex === index

                  let labelText = segment.value || "segment"
                  if (segment.mode === "folder_wildcard") labelText = "✨ Any value"
                  if (segment.mode === "suffix_wildcard") labelText = `${segment.value || "item"}... (starts with)`

                  const inputId = `dropdown-input-${index}`

                  return (
                    <React.Fragment key={index}>
                      <span className="text-breeze-muted shrink-0">/</span>
                      <div className="relative inline-block segment-container" ref={isOpen ? dropdownRef : null}>
                        <button
                          type="button"
                          onClick={() => setActiveDropdownIndex(isOpen ? null : index)}
                          className="px-2.5 py-1.5 rounded bg-breeze-view hover:bg-breeze-border/40 text-breeze-text border border-breeze-border transition flex items-center justify-between gap-2 shadow-2xs font-semibold truncate min-w-[90px] max-w-[200px]"
                          title={labelText}
                        >
                          <span className="truncate">{labelText}</span>
                          <span className="text-[10px] text-breeze-muted shrink-0">▼</span>
                        </button>

                        {isOpen && (
                          <div
                            className="absolute left-0 top-full mt-1 z-50 bg-breeze-view border border-breeze-border rounded-lg shadow-2xl py-1 text-[11px] font-sans"
                            style={{ width: "340px" }}
                          >
                            <div className="p-2.5 border-b border-breeze-border/40 bg-breeze-bg/40 space-y-1.5" onClick={(e) => e.stopPropagation()}>
                              <div className="flex items-center gap-1.5">
                                <input
                                  id={inputId}
                                  type="text"
                                  placeholder="Type value or paste URL..."
                                  defaultValue={segment.mode === "exact" ? segment.value : ""}
                                  onKeyDown={(e) => {
                                    if (e.key === "Enter") {
                                      e.preventDefault()
                                      handleCustomInputSubmit(index, (e.target as HTMLInputElement).value)
                                    }
                                  }}
                                  className="w-full text-[11px] font-sans px-2.5 py-1.5 bg-breeze-view text-breeze-text rounded border border-breeze-border outline-none focus:border-breeze-accent"
                                  autoFocus
                                />
                                <button
                                  type="button"
                                  onClick={() => {
                                    const inputEl = document.getElementById(inputId) as HTMLInputElement
                                    if (inputEl) {
                                      handleCustomInputSubmit(index, inputEl.value)
                                    }
                                  }}
                                  className="px-3 py-1.5 bg-breeze-accent text-white font-bold rounded hover:opacity-95 transition cursor-pointer shrink-0 text-xs"
                                >
                                  Add
                                </button>
                              </div>
                              <div className="text-[9px] text-breeze-muted">Press Enter, click Add, or paste full URL</div>
                            </div>

                            <button
                              type="button"
                              onClick={() => handleSetMode(index, "exact")}
                              className="w-full text-left px-3 py-2 hover:bg-breeze-accent/20 text-breeze-text font-semibold truncate cursor-pointer"
                            >
                              🔒 Exact match
                            </button>
                            <button
                              type="button"
                              onClick={() => handleSetMode(index, "folder_wildcard")}
                              className="w-full text-left px-3 py-2 hover:bg-breeze-accent/20 text-breeze-accent truncate cursor-pointer"
                            >
                              ✨ Any value
                            </button>

                            {isLast && (
                              <button
                                type="button"
                                onClick={() => handleSetMode(index, "suffix_wildcard")}
                                className="w-full text-left px-3 py-2 hover:bg-breeze-accent/20 text-breeze-accent truncate cursor-pointer"
                              >
                                🔤 Starts with this text
                              </button>
                            )}

                            <button
                              type="button"
                              onClick={() => handleCutFromHere(index)}
                              className="w-full text-left px-3 py-2 hover:bg-red-500/20 text-red-400 truncate border-t border-breeze-border/40 cursor-pointer"
                            >
                              🛑 Cut path from here
                            </button>
                          </div>
                        )}
                      </div>
                    </React.Fragment>
                  )
                })}

                <button
                  type="button"
                  onClick={handleAddSegment}
                  className="shrink-0 w-8 h-8 rounded-lg bg-breeze-view hover:bg-breeze-accent/20 text-breeze-accent border border-breeze-border flex items-center justify-center font-bold text-sm shadow-2xs transition cursor-pointer ml-1"
                  title="Add path segment"
                >
                  +
                </button>
              </div>

              {/* Human Interpretation */}
              <div className="p-3 bg-blue-500/10 border border-blue-500/30 rounded-lg text-xs text-blue-300 flex items-start gap-2 mt-2">
                <span>💡</span>
                <div>
                  <span className="font-bold">Human Interpretation:</span>
                  <p className="font-mono text-[11px] mt-0.5 text-blue-200">
                    {getInterpretationText(currentPatternString)}
                  </p>
                </div>
              </div>
            </div>

            {/* Footer Actions */}
            <div className="pt-4 border-t border-breeze-border flex items-center justify-end gap-3 py-3">
              <button
                type="button"
                onClick={() => setIsAccordionOpen(false)}
                className="px-4 py-2 text-xs font-semibold text-breeze-muted hover:text-breeze-text transition cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={isSubmitting}
                className="py-2 px-5 bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-500 hover:to-indigo-500 text-white font-bold text-xs rounded-lg shadow-sm transition cursor-pointer disabled:opacity-50"
              >
                {isSubmitting ? "Saving..." : "Save Pattern"}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  )
}


const normalizeDomain = (hostname: string): string => hostname.toLowerCase().replace(/^www\./i, "")

const pathFromUrl = (url: URL): string | null => {
  const pathname = url.pathname.replace(/\/+$/, "")
  return pathname && pathname !== "/" ? pathname.startsWith("/") ? pathname : `/${pathname}` : null
}

interface ParsedSource {
  domain: string
  patterns: string[]
}

const parseSourceInput = (raw: string): ParsedSource => {
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

const isUrlLike = (value: string): boolean =>
  value.includes("://") || /^\s*[^\s/]+\.[^\s/]+\/.+/m.test(value)

const PatternManager: React.FC<{
  targetDomain: string
  targetId: number | string
  initialPatterns: Pattern[]
  categories: Category[]
  authenticityToken: string
  createEndpoint: string
  onPatternsChange: (patterns: Pattern[]) => void
}> = ({ targetDomain, targetId, initialPatterns, categories, authenticityToken, createEndpoint, onPatternsChange }) => (
  <PatternBuilder
    targetDomain={targetDomain}
    initialPatterns={initialPatterns}
    categories={categories}
    matchedTargetId={Number(targetId)}
    authenticityToken={authenticityToken}
    createEndpoint={createEndpoint}
    redirectPath={window.location.pathname}
    onPatternsChange={onPatternsChange}
  />
)

const TargetEditor: React.FC<PathBuilderProps> = (props) => {
  const [targetId, setTargetId] = useState<number | string | undefined>(props.targetId)
  const [targetName, setTargetName] = useState(props.targetName || "")
  const [domain, setDomain] = useState(props.targetDomain || "")
  const [sourceInput, setSourceInput] = useState(props.targetDomain || "")
  const [sourceWasEdited, setSourceWasEdited] = useState(false)
  const [categoryId, setCategoryId] = useState(String(props.targetCategoryId ?? ""))
  const [isActive, setIsActive] = useState(props.targetIsActive ?? true)
  const [allowQueryStrings, setAllowQueryStrings] = useState(props.targetAllowQueryStrings ?? false)
  const [selectedSearchIds, setSelectedSearchIds] = useState<string[]>(
    (props.initialSearchIds || []).map(String),
  )
  const [patterns, setPatterns] = useState<Pattern[]>(props.initialPatterns || [])
  const [pendingPatterns, setPendingPatterns] = useState<string[]>([])
  const [error, setError] = useState("")
  const [notice, setNotice] = useState("")
  const [isSaving, setIsSaving] = useState(false)
  const [patternRevision, setPatternRevision] = useState(0)
  const persisted = targetId !== undefined && targetId !== null && String(targetId) !== ""
  const targetCreateEndpoint = props.targetCreateEndpoint || "/targets.json"
  const targetUpdateEndpoint = props.targetUpdateEndpoint || (persisted ? `/targets/${targetId}.json` : "")
  const cancelPath = props.cancelPath || props.redirectPath || "/categories"
  const [returnPath, setReturnPath] = useState(cancelPath)

  const handleSourceChange = (value: string) => {
    setSourceWasEdited(true)
    setSourceInput(value)
    setError("")
    if (!isUrlLike(value)) {
      setDomain(value.trim())
      setPendingPatterns([])
      return
    }

    try {
      const parsed = parseSourceInput(value)
      setDomain(parsed.domain)
      setPendingPatterns(parsed.patterns.filter((pattern) => !patterns.some((saved) => saved.path_pattern === pattern)))
    } catch (parseError) {
      setError(parseError instanceof Error ? parseError.message : "Unable to parse the URL.")
    }
  }

  const toggleSearch = (id: number | string) => {
    const value = String(id)
    setSelectedSearchIds((current) => current.includes(value) ? current.filter((item) => item !== value) : [...current, value])
  }

  const createParsedPatterns = async (savedTargetId: number | string, requestedPatterns: string[]): Promise<{ created: Pattern[]; failed: string[] }> => {
    const toCreate = requestedPatterns.filter((pattern) => !patterns.some((saved) => saved.path_pattern === pattern))
    const created: Pattern[] = []
    const failed: string[] = []

    for (const pathPattern of toCreate) {
      try {
        const response = await fetch(props.createEndpoint, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": props.authenticityToken,
            "Accept": "application/json",
          },
          body: JSON.stringify({ target_pattern: { target_id: savedTargetId, path_pattern: pathPattern } }),
        })
        if (!response.ok) throw new Error(`HTTP ${response.status}`)

        const contentType = response.headers.get("content-type") || ""
        const data = contentType.includes("application/json") ? await response.json() : {}
        const savedPattern: Pattern = data.pattern || data.target_pattern || {
          id: data.id || `${Date.now()}-${created.length}`,
          path_pattern: pathPattern,
          is_active: true,
        }
        created.push({ ...savedPattern, path_pattern: savedPattern.path_pattern || pathPattern, is_active: savedPattern.is_active ?? true })
      } catch (createError) {
        console.error("Failed to create parsed target pattern", createError)
        failed.push(pathPattern)
      }
    }

    return { created, failed }
  }

  const handleSaveTarget = async (event: React.FormEvent) => {
    event.preventDefault()
    setError("")
    setNotice("")

    if (!categoryId) {
      setError("Select a category before saving the target.")
      return
    }

    let finalDomain = domain.trim()
    let parsedPatterns = pendingPatterns
    const sourceWasLeftUntouched = persisted && !sourceWasEdited && sourceInput.trim() === (props.targetDomain || "").trim()
    try {
      // Preserve legacy targets whose `domain` already contains a path unless the
      // user explicitly edits the source input. Pasting a URL opts into the new
      // host + path-pattern representation.
      if (!sourceWasLeftUntouched) {
        const parsed = parseSourceInput(sourceInput || domain)
        finalDomain = parsed.domain
        if (parsed.patterns.length) {
          parsedPatterns = [...new Set([...pendingPatterns, ...parsed.patterns])]
        }
      }
    } catch (parseError) {
      setError(parseError instanceof Error ? parseError.message : "Please enter a valid domain or URL.")
      return
    }
    if (!finalDomain) {
      setError("Domain is required.")
      return
    }

    const inferredName = finalDomain.split(".")[0] || finalDomain
    const finalName = targetName.trim() || inferredName.charAt(0).toUpperCase() + inferredName.slice(1)
    setTargetName(finalName)
    setDomain(finalDomain)
    setPendingPatterns(parsedPatterns.filter((pattern) => !patterns.some((saved) => saved.path_pattern === pattern)))
    setIsSaving(true)
    try {
      const payload = {
        target: {
          name: finalName,
          domain: finalDomain,
          category_id: categoryId,
          is_active: isActive,
          allow_query_strings: allowQueryStrings,
          search_ids: selectedSearchIds,
        },
      }
      const response = await fetch(persisted ? targetUpdateEndpoint : targetCreateEndpoint, {
        method: persisted ? "PATCH" : "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": props.authenticityToken,
          "Accept": "application/json",
        },
        body: JSON.stringify(payload),
      })

      if (!response.ok) {
        const responseData = await response.json().catch(() => ({}))
        const errors = responseData.errors || responseData.error || responseData.message
        throw new Error(Array.isArray(errors) ? errors.join(", ") : (errors || `Unable to save target (HTTP ${response.status}).`))
      }

      let savedId = targetId
      if (!persisted) {
        const data = await response.json()
        const savedTarget = data.target || data
        savedId = savedTarget.id
        if (savedId === undefined || savedId === null) throw new Error("Target was saved but the server did not return its ID.")
        setTargetId(savedId)
        if (savedTarget.edit_url) window.history.replaceState({}, "", savedTarget.edit_url)
        if (savedTarget.category_url) setReturnPath(savedTarget.category_url)
      }

      if (persisted) setReturnPath(`/categories/${categoryId}`)

      if (savedId !== undefined && parsedPatterns.length) {
        const toSave = parsedPatterns.filter((pattern) => !patterns.some((saved) => saved.path_pattern === pattern))
        setPendingPatterns(toSave)
        const result = await createParsedPatterns(savedId, toSave)
        if (result.created.length) {
          setPatterns((current) => {
            const merged = [...current, ...result.created.filter((candidate) => !current.some((saved) => saved.path_pattern === candidate.path_pattern))]
            return merged
          })
          setPatternRevision((revision) => revision + 1)
        }
        setPendingPatterns(result.failed)
        if (result.failed.length) {
          setNotice("Target saved. Some parsed patterns could not be saved; retry by saving again or add them below.")
        } else {
          setNotice(persisted ? "Target updated successfully." : "Target created successfully.")
          setSourceInput(finalDomain)
          setSourceWasEdited(false)
        }
      } else {
        setNotice(persisted ? "Target updated successfully." : "Target created successfully.")
        setSourceInput(finalDomain)
        setSourceWasEdited(false)
      }
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : "An unexpected error occurred while saving the target.")
    } finally {
      setIsSaving(false)
    }
  }

  return (
    <div className="max-w-7xl mx-auto space-y-5 font-sans">
      <div className="bg-breeze-view border border-breeze-border rounded-xl p-4 sm:p-6 shadow-sm flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
        <div>
          <a href={returnPath} className="inline-flex items-center gap-1.5 text-xs font-semibold text-breeze-muted hover:text-breeze-text transition bg-breeze-bg/50 px-2.5 py-1 rounded-md border border-breeze-border/60">
            <span>⬅️</span><span>{persisted ? "Back to Category" : "Back"}</span>
          </a>
          <h1 className="text-xl sm:text-2xl font-bold text-breeze-text mt-3">{persisted ? `Edit Target Site${targetName ? `: ${targetName}` : ""}` : "Add New Target Site"}</h1>
          <p className="text-xs text-breeze-muted mt-1">Configure the target, attach it to searches, and manage its URL path patterns in one place.</p>
        </div>
        {persisted && <span className={`text-xs font-mono font-bold px-3 py-1 rounded-full border ${isActive ? "bg-emerald-500/10 text-emerald-400 border-emerald-500/20" : "bg-gray-500/10 text-gray-400 border-breeze-border"}`}>{isActive ? "Active Pipeline" : "Inactive"}</span>}
      </div>

      {error && <div role="alert" className="p-3 bg-red-500/10 border border-red-500/30 rounded-lg text-xs text-red-300 font-semibold">⚠️ {error}</div>}
      {notice && <div role="status" className="p-3 bg-emerald-500/10 border border-emerald-500/30 rounded-lg text-xs text-emerald-300 font-semibold">✓ {notice}</div>}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 sm:gap-6 items-start">
        <section className="lg:col-span-1 bg-breeze-view p-4 sm:p-6 border border-breeze-border rounded-xl space-y-5 shadow-sm">
          <form onSubmit={handleSaveTarget} className="space-y-5">
          <div className="border-b border-breeze-border/60 pb-3">
            <h2 className="text-xs font-bold text-breeze-muted uppercase tracking-wider">🛠️ Target configuration</h2>
            <p className="text-[11px] text-breeze-muted mt-1">A target can exist without path patterns.</p>
          </div>

          <div>
            <label htmlFor="target-name" className="block text-xs font-semibold text-breeze-muted uppercase tracking-wider mb-1.5">Site Name</label>
            <input id="target-name" value={targetName} onChange={(event) => setTargetName(event.target.value)} placeholder="e.g., Workable (defaults to domain name)" className="w-full text-sm bg-breeze-bg text-breeze-text rounded-lg border border-breeze-border px-3 py-2.5 outline-none focus:border-breeze-accent" />
          </div>

          <div>
            <label htmlFor="target-source" className="block text-xs font-semibold text-breeze-muted uppercase tracking-wider mb-1.5">Domain or full URL</label>
            <textarea id="target-source" value={sourceInput} onChange={(event) => handleSourceChange(event.target.value)} placeholder={'example.com\nor https://example.com/careers/123'} rows={3} required className="w-full text-sm font-mono bg-breeze-bg text-breeze-text rounded-lg border border-breeze-border px-3 py-2.5 outline-none focus:border-breeze-accent" />
            <p className="text-[10px] text-breeze-muted mt-1.5 leading-relaxed">Enter just a domain to create a target only. Paste one or more URLs from the same domain to extract the domain and queue their paths as patterns.</p>
            {domain && <p className="text-[11px] text-breeze-accent mt-2">Parsed target domain: <strong className="font-mono">{domain}</strong></p>}
            {pendingPatterns.length > 0 && <div className="mt-2 p-2.5 bg-blue-500/10 border border-blue-500/20 rounded-lg"><p className="text-[10px] text-blue-200 font-semibold mb-1">Patterns to create on save:</p><ul className="text-[11px] text-blue-100 font-mono space-y-0.5">{pendingPatterns.map((pattern) => <li key={pattern}>{pattern}</li>)}</ul></div>}
            <p className="text-[10px] text-amber-400/90 mt-2 leading-relaxed">⚠️ Changing the domain synchronizes the existing search queries associated with this target.</p>
          </div>

          <div>
            <label htmlFor="target-category" className="block text-xs font-semibold text-breeze-muted uppercase tracking-wider mb-1.5">Category</label>
            <select id="target-category" value={categoryId} onChange={(event) => setCategoryId(event.target.value)} required className="w-full text-sm bg-breeze-bg text-breeze-text rounded-lg border border-breeze-border px-3 py-2.5 outline-none focus:border-breeze-accent">
              <option value="">Select category...</option>
              {props.categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}
            </select>
          </div>

          <div className="p-3.5 bg-breeze-bg rounded-lg border border-breeze-border/60 space-y-3">
            <label className="flex items-center gap-3 text-xs font-semibold text-breeze-text cursor-pointer"><input type="checkbox" checked={isActive} onChange={(event) => setIsActive(event.target.checked)} className="h-4 w-4 rounded border-breeze-border bg-breeze-view text-breeze-accent" /> Enabled for scraping</label>
            <label className="flex items-center gap-3 text-xs font-semibold text-breeze-text cursor-pointer"><input type="checkbox" checked={allowQueryStrings} onChange={(event) => setAllowQueryStrings(event.target.checked)} className="h-4 w-4 rounded border-breeze-border bg-breeze-view text-breeze-accent" /> Keep URL query parameters</label>
            <p className="text-[10px] text-breeze-muted pl-7">Preserves parameters such as <code>?jk=...</code> for tracking-heavy sites.</p>
          </div>

          <div className="pt-3 border-t border-breeze-border/60">
            <label className="block text-xs font-semibold text-breeze-muted uppercase tracking-wider mb-2">Attach to Active Searches</label>
            {props.searches && props.searches.length > 0 ? (
              <div className="max-h-60 overflow-y-auto space-y-1.5 pr-1 [scrollbar-width:thin]">
                {props.searches.map((search) => <label key={search.id} className="flex items-center gap-2.5 text-xs text-breeze-text cursor-pointer bg-breeze-bg/50 hover:bg-breeze-bg p-2 rounded-md border border-breeze-border/40 transition"><input type="checkbox" checked={selectedSearchIds.includes(String(search.id))} onChange={() => toggleSearch(search.id)} className="h-3.5 w-3.5 rounded border-breeze-border bg-breeze-view text-breeze-accent" /><span className="truncate">{search.title}</span></label>)}
              </div>
            ) : <p className="text-[11px] text-breeze-muted italic">No searches available yet.</p>}
            <p className="text-[10px] text-breeze-muted mt-2">Selected searches will get a prompt for this target. Unchecking an existing search removes its target prompt.</p>
          </div>

          <div className="flex items-center gap-3 pt-2 border-t border-breeze-border/60">
            <button type="submit" disabled={isSaving} className="flex-1 py-2.5 px-4 bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-500 hover:to-indigo-500 text-white font-bold text-xs rounded-lg shadow-md transition disabled:opacity-50">{isSaving ? "Saving..." : persisted ? "Save Target" : "Create Target"}</button>
            <a href={returnPath} className="px-4 py-2.5 border border-breeze-border hover:bg-breeze-bg text-breeze-muted hover:text-breeze-text text-xs font-semibold rounded-lg transition">Cancel</a>
          </div>
          </form>
        </section>

        <section className="lg:col-span-2 bg-breeze-view p-4 sm:p-6 border border-breeze-border rounded-xl shadow-sm">
          <div className="border-b border-breeze-border/60 pb-3 mb-4">
            <h2 className="text-xs font-bold text-breeze-muted uppercase tracking-wider">✨ Path patterns</h2>
            <p className="text-[11px] text-breeze-muted mt-1">Manage exact paths and wildcard rules. No patterns means all paths for this domain remain eligible.</p>
          </div>
          {!persisted ? (
            <div className="text-center py-12 bg-breeze-bg/40 rounded-lg border border-dashed border-breeze-border/60"><p className="text-sm text-breeze-text font-semibold">Save the target first</p><p className="text-xs text-breeze-muted mt-1">Any paths parsed from the pasted URL will be saved with the target. You can add more patterns after the target is created.</p></div>
          ) : (
            <PatternManager key={`${targetId}-${patternRevision}`} targetDomain={domain} targetId={targetId!} initialPatterns={patterns} categories={props.categories} authenticityToken={props.authenticityToken} createEndpoint={props.createEndpoint} onPatternsChange={setPatterns} />
          )}
        </section>
      </div>
    </div>
  )
}

export const PathBuilder: React.FC<PathBuilderProps> = (props) => {
  if (props.mode === "target") return <TargetEditor {...props} />
  return <PatternBuilder {...props} />
}
