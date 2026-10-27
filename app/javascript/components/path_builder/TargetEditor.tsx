import React, { useState } from "react"
import { Pattern, Category, PathBuilderProps } from "./types"
import { parseSourceInput, isUrlLike, triggerFlash } from "./utils/patternUtils"
import { PatternBuilder } from "./PatternBuilder"

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

export const TargetEditor: React.FC<PathBuilderProps> = (props) => {
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
  const [isSaving, setIsSaving] = useState(false)
  const [patternRevision, setPatternRevision] = useState(0)
  const persisted = targetId !== undefined && targetId !== null && String(targetId) !== ""
  const targetCreateEndpoint = props.targetCreateEndpoint || "/targets.json"
  const targetUpdateEndpoint = props.targetUpdateEndpoint || (persisted ? `/targets/${targetId}.json` : "")

  const initialCancelPath = props.cancelPath || props.redirectPath || "/categories"
  const [returnPath, setReturnPath] = useState(initialCancelPath)

  const handleSourceChange = (value: string) => {
    setSourceWasEdited(true)
    setSourceInput(value)
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
      triggerFlash(parseError instanceof Error ? parseError.message : "Unable to parse the URL.", "error")
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

    if (!categoryId) {
      triggerFlash("Select a category before saving the target.", "error")
      return
    }

    let finalDomain = domain.trim()
    let parsedPatterns = pendingPatterns
    const sourceWasLeftUntouched = persisted && !sourceWasEdited && sourceInput.trim() === (props.targetDomain || "").trim()
    try {
      if (!sourceWasLeftUntouched) {
        const parsed = parseSourceInput(sourceInput || domain)
        finalDomain = parsed.domain
        if (parsed.patterns.length) {
          parsedPatterns = [...new Set([...pendingPatterns, ...parsed.patterns])]
        }
      }
    } catch (parseError) {
      triggerFlash(parseError instanceof Error ? parseError.message : "Please enter a valid domain or URL.", "error")
      return
    }
    if (!finalDomain) {
      triggerFlash("Domain is required.", "error")
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
        if (savedTarget.category_url) {
          setReturnPath(savedTarget.category_url)
        } else {
          setReturnPath(`/categories/${categoryId}`)
        }
      } else {
        setReturnPath(`/categories/${categoryId}`)
      }

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
          triggerFlash("Target saved. Some parsed patterns could not be saved; retry by saving again or add them below.", "error")
        } else {
          triggerFlash(persisted ? "Target updated successfully." : "Target created successfully.", "notice")
          setSourceInput(finalDomain)
          setSourceWasEdited(false)
        }
      } else {
        triggerFlash(persisted ? "Target updated successfully." : "Target created successfully.", "notice")
        setSourceInput(finalDomain)
        setSourceWasEdited(false)
      }
    } catch (saveError) {
      triggerFlash(saveError instanceof Error ? saveError.message : "An unexpected error occurred while saving the target.", "error")
    } finally {
      setIsSaving(false)
    }
  }

  return (
    <div className="max-w-7xl mx-auto space-y-5 font-sans">
      <div className="bg-breeze-view border border-breeze-border rounded-xl p-4 sm:p-6 shadow-sm flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
        <div>
          <a href={returnPath} className="inline-flex items-center gap-1.5 text-xs font-semibold text-breeze-muted hover:text-breeze-text transition bg-breeze-bg/50 px-2.5 py-1 rounded-md border border-breeze-border/60">
            <span>⬅️</span><span>Back</span>
          </a>
          <h1 className="text-xl sm:text-2xl font-bold text-breeze-text mt-3">{persisted ? `Edit Target Site${targetName ? `: ${targetName}` : ""}` : "Add New Target Site"}</h1>
          <p className="text-xs text-breeze-muted mt-1">Configure the target, attach it to searches, and manage its URL path patterns in one place.</p>
        </div>
        {persisted && <span className={`text-xs font-mono font-bold px-3 py-1 rounded-full border ${isActive ? "bg-emerald-500/10 text-emerald-400 border-emerald-500/20" : "bg-gray-500/10 text-gray-400 border-breeze-border"}`}>{isActive ? "Active Pipeline" : "Inactive"}</span>}
      </div>

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