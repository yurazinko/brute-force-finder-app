import React, { useState, useRef, useEffect } from "react"
import { Pattern, Segment, SegmentMode, PathBuilderProps } from "./types"
import {
  parsePatternSegments,
  serializePatternSegments,
  triggerFlash
} from "./utils/patternUtils"

export const PatternBuilder: React.FC<PathBuilderProps> = ({
  targetDomain,
  initialPatterns,
  categories,
  searches = [],
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
  const [selectedSearchIds, setSelectedSearchIds] = useState<string[]>([])
  const [allowQueryStrings, setAllowQueryStrings] = useState<boolean>(false)
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
  const canAttachToSearches = Boolean(resultUrl?.trim()) && !matchedTargetId

  const toggleSearch = (id: number | string) => {
    const searchId = String(id)
    setSelectedSearchIds((current) =>
      current.includes(searchId)
        ? current.filter((value) => value !== searchId)
        : [...current, searchId]
    )
  }

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
      triggerFlash("Category or Target can't be blank", "error")
      return
    }
    setIsSubmitting(true)

    try {
      const payload: Record<string, any> = {
        path_pattern: currentPatternString,
        allow_query_strings: allowQueryStrings ? "1" : "0",
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

      if (canAttachToSearches) {
        payload.search_ids = selectedSearchIds
      }

      const response = await fetch(createEndpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": authenticityToken,
          Accept: "application/json, text/vnd.turbo-stream.html",
        },
        body: JSON.stringify({
          target_pattern: payload,
        }),
      })

      if (response.ok) {
        const contentType = response.headers.get("content-type")
        if (contentType && contentType.includes("application/json")) {
          const data = await response.json()
          const savedPattern: Pattern = data.pattern || {
            id: data.id || Date.now(),
            path_pattern: currentPatternString,
            is_active: true,
          }
          commitPatterns([...patterns, savedPattern])
          setIsAccordionOpen(false)
          setSegments([{ mode: "exact", value: "" }])
          setNewCategoryName("")
          setSelectedCategory("")
          triggerFlash("Pattern created successfully.", "notice")
        } else {
          window.location.reload()
        }
      } else {
        triggerFlash("Failed to create pattern.", "error")
      }
    } catch (err) {
      console.error("Failed to create pattern:", err)
      triggerFlash("Failed to create pattern.", "error")
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
      const value =
        mode === "exact" && segment.mode === "folder_wildcard" && !segment.value ? "new" : segment.value
      return { ...segment, mode, value }
    })
    updateEditingSegments(nextSegments)
    setActiveEditDropdownIndex(null)
  }

  const handleEditSegmentInput = (index: number, rawValue: string) => {
    const value = rawValue.trim()
    if (!value) return

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
      } catch {}
    }

    const nextSegments = editingSegments.map((segment, segmentIndex) =>
      segmentIndex === index ? { mode: "exact" as const, value } : segment
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
            Accept: "application/json",
          },
          body: JSON.stringify({ target_pattern: { path_pattern: pathPattern } }),
        })

        if (!response.ok) throw new Error(`HTTP ${response.status}`)

        commitPatterns(
          patterns.map((p) => (p.id === pattern.id ? { ...p, path_pattern: pathPattern } : p))
        )
        cancelPatternEdit()
        triggerFlash("Pattern updated successfully.", "notice")
      } catch (err) {
        console.error("Failed to update pattern", err)
        setPatternEditError("Could not save this pattern. Your edits have been kept; please try again.")
        triggerFlash("Could not save this pattern.", "error")
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
          Accept: "application/json",
        },
        body: JSON.stringify({
          target_pattern: { is_active: nextState },
        }),
      })

      if (response.ok) {
        commitPatterns(
          patterns.map((p) => (p.id === pattern.id ? { ...p, is_active: nextState } : p))
        )
        triggerFlash("Pattern status updated.", "notice")
      }
    } catch (err) {
      console.error("Failed to toggle status", err)
      triggerFlash("Failed to update pattern status.", "error")
    }
  }

  const handleDeletePattern = async (id: number | string) => {
    if (!confirm("Are you sure you want to delete this pattern?")) return
    try {
      const response = await fetch(`/target_patterns/${id}`, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": authenticityToken,
          Accept: "application/json",
        },
      })

      if (response.ok) {
        commitPatterns(patterns.filter((p) => p.id !== id))
        triggerFlash("Pattern deleted.", "notice")
      }
    } catch (err) {
      console.error("Failed to delete pattern", err)
      triggerFlash("Failed to delete pattern.", "error")
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

            {canAttachToSearches && (
              <div className="space-y-2 rounded-lg border border-breeze-border/60 bg-breeze-bg/50 p-3.5">
                <label className="block text-xs font-semibold text-breeze-text">Attach to Active Searches</label>
                {searches.length > 0 ? (
                  <div className="max-h-30 overflow-y-auto space-y-1.5 pr-1 [scrollbar-width:thin]">
                    {searches.map((search) => (
                      <label key={search.id} className="flex items-center gap-2.5 text-xs text-breeze-text cursor-pointer bg-breeze-view/70 hover:bg-breeze-view p-2 rounded-md border border-breeze-border/40 transition">
                        <input
                          type="checkbox"
                          checked={selectedSearchIds.includes(String(search.id))}
                          onChange={() => toggleSearch(search.id)}
                          className="h-3.5 w-3.5 rounded border-breeze-border bg-breeze-view text-breeze-accent focus:ring-breeze-accent cursor-pointer"
                        />
                        <span className="truncate">{search.title}</span>
                      </label>
                    ))}
                  </div>
                ) : (
                  <p className="text-[11px] text-breeze-muted italic">No searches available yet.</p>
                )}
                <p className="text-[10px] text-breeze-muted">The selected searches will receive a prompt for this new target. This option is shown only when creating a target from a result URL.</p>
              </div>
            )}

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