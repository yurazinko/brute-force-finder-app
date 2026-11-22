import React, { useEffect, useState } from 'react'

interface DorkGroup {
  id: string
  tags: string[]
  inputValue: string
}

interface DorkBuilderProps {
  initialValue?: string
  inputName: string
}

interface ParsedQuery {
  groups: DorkGroup[]
  supported: boolean
}

const DORK_OPERATORS = new Set([
  'site', 'tld', 'from', 'inurl', 'allinurl', 'intitle', 'allintitle',
  'intext', 'allintext', 'filetype', 'ext', 'after', 'before', 'cache',
  'related', 'define'
])

const EMPTY_GROUP = (): DorkGroup => ({
  id: `group-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
  tags: [],
  inputValue: ''
})

const makeGroup = (tags: string[], index: number): DorkGroup => ({
  id: `initial-${index}`,
  tags,
  inputValue: ''
})

const unquote = (token: string): string => {
  const trimmed = token.trim()
  if (trimmed.startsWith('"') && trimmed.endsWith('"') && trimmed.length >= 2) {
    return trimmed.slice(1, -1).replace(/\\"/g, '"').replace(/\\\\/g, '\\').trim()
  }

  return trimmed
}

/**
 * Parses the subset of the query language that the visual builder can represent:
 * whitespace means AND, OR joins tags in a group, and parentheses explicitly
 * define an OR group. Search-engine operators remain in Raw Expert Mode so that
 * switching to the wizard cannot silently discard them.
 */
const parseQuery = (value: string): ParsedQuery => {
  const input = value.trim()
  if (!input) return { groups: [EMPTY_GROUP()], supported: true }

  const tokens = input.match(/"(?:\\.|[^"\\])*"|\(|\)|[^\s()]+/g) || []
  const groups: DorkGroup[] = []
  let currentTags: string[] = []
  let parenthesisDepth = 0
  let pendingOr = false
  let supported = true

  const flushGroup = () => {
    if (currentTags.length > 0) {
      groups.push(makeGroup(currentTags, groups.length))
      currentTags = []
    }
    pendingOr = false
  }

  tokens.forEach((token) => {
    if (token === '(') {
      if (parenthesisDepth === 0) {
        if (pendingOr) supported = false
        flushGroup()
      }
      parenthesisDepth += 1
      return
    }

    if (token === ')') {
      if (parenthesisDepth === 0) {
        supported = false
        return
      }

      parenthesisDepth -= 1
      if (parenthesisDepth === 0) flushGroup()
      return
    }

    const operator = token.toUpperCase()
    if (operator === 'OR') {
      if (currentTags.length === 0) supported = false
      pendingOr = true
      return
    }

    if (operator === 'AND') {
      if (parenthesisDepth > 0) supported = false
      flushGroup()
      return
    }

    if (operator === 'NOT') {
      supported = false
      pendingOr = false
      return
    }

    const dorkOperator = token.match(/^([a-z][a-z0-9]*):/i)?.[1]?.toLowerCase()
    if (dorkOperator && DORK_OPERATORS.has(dorkOperator)) {
      supported = false
      pendingOr = false
      return
    }

    if (token.startsWith('/') || token.includes('"') && !(token.startsWith('"') && token.endsWith('"'))) {
      supported = false
      pendingOr = false
      return
    }

    const tag = unquote(token).toLowerCase()
    if (!tag) return

    if (parenthesisDepth > 0 || pendingOr) {
      currentTags.push(tag)
    } else {
      flushGroup()
      currentTags = [tag]
    }
    pendingOr = false
  })

  if (parenthesisDepth > 0 || pendingOr) supported = false
  flushGroup()

  return {
    groups: groups.length > 0 ? groups : [EMPTY_GROUP()],
    supported
  }
}

const quoteTag = (tag: string): string => `"${tag.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`

const buildRawQuery = (groups: DorkGroup[]): string => groups
  .filter(group => group.tags.length > 0)
  .map(group => `(${group.tags.map(quoteTag).join(' OR ')})`)
  .join(' ')

const addEmptyGroup = (groups: DorkGroup[]): DorkGroup[] => [...groups, EMPTY_GROUP()]

export const DorkBuilder: React.FC<DorkBuilderProps> = ({ initialValue = '', inputName }) => {
  const initialParsed = parseQuery(initialValue)
  const [groups, setGroups] = useState<DorkGroup[]>(initialParsed.groups)
  const [rawQuery, setRawQuery] = useState<string>(initialValue)
  const [isRawMode, setIsRawMode] = useState<boolean>(initialValue.trim().length > 0 && !initialParsed.supported)

  // Keep the submitted hidden input synchronized with wizard edits. In Raw mode,
  // the textarea is authoritative and this effect deliberately does not overwrite it.
  useEffect(() => {
    if (!isRawMode) setRawQuery(buildRawQuery(groups))
  }, [groups, isRawMode])

  const parsedRawQuery = parseQuery(rawQuery)

  const addTag = (groupId: string) => {
    setGroups(current => current.map(group => {
      if (group.id !== groupId || !group.inputValue.trim()) return group

      return {
        ...group,
        tags: [...group.tags, group.inputValue.trim().toLowerCase()],
        inputValue: ''
      }
    }))
  }

  const removeTag = (groupId: string, tagIndex: number) => {
    setGroups(current => current.map(group => group.id === groupId
      ? { ...group, tags: group.tags.filter((_, index) => index !== tagIndex) }
      : group))
  }

  const addGroup = () => setGroups(current => addEmptyGroup(current))

  const removeGroup = (groupId: string) => {
    setGroups(current => {
      const remaining = current.filter(group => group.id !== groupId)
      return remaining.length > 0 ? remaining : [EMPTY_GROUP()]
    })
  }

  const switchToWizard = () => {
    const parsed = parseQuery(rawQuery)
    if (!parsed.supported) return

    setGroups(parsed.groups)
    setIsRawMode(false)
  }

  const totalLength = rawQuery.length
  const lengthPercentage = Math.min((totalLength / 500) * 100, 100)
  const visibleGroups = groups.filter(group => group.tags.length > 0)

  return (
    <div className="bg-breeze-bg p-4 border border-breeze-border rounded-xl space-y-4 text-breeze-text">
      <input type="hidden" name={inputName} value={rawQuery} />

      <div className="flex justify-between items-center border-b border-breeze-border pb-2">
        <span className="text-sm font-bold">Dork Query Configurator</span>
        <div className="bg-breeze-view p-0.5 rounded-lg border border-breeze-border text-xs flex">
          <button
            type="button"
            disabled={isRawMode && !parsedRawQuery.supported}
            title={isRawMode && !parsedRawQuery.supported ? 'This query contains operators that can only be edited in Raw Expert Mode.' : undefined}
            className={`px-3 py-1 rounded-md font-medium transition cursor-pointer ${!isRawMode ? 'bg-breeze-accent text-breeze-view shadow-sm' : 'text-breeze-muted hover:text-breeze-text'} disabled:opacity-40 disabled:cursor-not-allowed`}
            onClick={switchToWizard}
          >
            🧙‍♂️ Wizard Constructor
          </button>
          <button
            type="button"
            className={`px-3 py-1 rounded-md font-medium transition cursor-pointer ${isRawMode ? 'bg-breeze-accent text-breeze-view shadow-sm' : 'text-breeze-muted hover:text-breeze-text'}`}
            onClick={() => setIsRawMode(true)}
          >
            ⌨️ Raw Expert Mode
          </button>
        </div>
      </div>

      {!isRawMode && (
        <div className="space-y-4">
          {groups.map((group, index) => (
            <div key={group.id} className="bg-breeze-view p-3 border border-breeze-border rounded-lg shadow-sm relative">
              {index > 0 && (
                <button
                  type="button"
                  onClick={() => removeGroup(group.id)}
                  className="absolute top-2 right-2 text-breeze-muted hover:text-red-400 text-xs cursor-pointer"
                >
                  ✕ Remove Group
                </button>
              )}
              <span className="text-[10px] font-bold text-breeze-accent tracking-wider uppercase block mb-2">
                {index === 0 ? '🎯 Condition Group 1 (Must match any of these)' : `➕ AND MUST ALSO match any of Group ${index + 1}`}
              </span>

              <div className="flex flex-wrap gap-1.5 mb-2">
                {group.tags.map((tag, tagIndex) => (
                  <span key={`${group.id}-${tagIndex}`} className="inline-flex items-center text-xs bg-breeze-bg text-breeze-text px-2 py-1 rounded font-medium border border-breeze-border shadow-sm">
                    {tag.includes(' ') ? `"${tag}"` : tag}
                    <button
                      type="button"
                      onClick={() => removeTag(group.id, tagIndex)}
                      aria-label={`Remove ${tag}`}
                      className="ml-1 text-breeze-muted hover:text-red-400 font-bold cursor-pointer"
                    >
                      ×
                    </button>
                  </span>
                ))}
              </div>

              <div className="flex max-w-xs">
                <input
                  type="text"
                  value={group.inputValue}
                  placeholder="e.g., ruby, engineer, 'remote'"
                  className="w-full text-xs rounded-l-md border-breeze-border py-1.5 px-2 bg-breeze-bg focus:ring-1 focus:ring-breeze-accent focus:border-breeze-accent text-breeze-text"
                  onChange={event => setGroups(current => current.map(item => item.id === group.id
                    ? { ...item, inputValue: event.target.value }
                    : item))}
                  onKeyDown={event => event.key === 'Enter' && (event.preventDefault(), addTag(group.id))}
                />
                <button
                  type="button"
                  onClick={() => addTag(group.id)}
                  className="bg-breeze-border hover:bg-breeze-muted/30 text-breeze-text text-xs px-3 rounded-r-md font-medium border-y border-r border-breeze-border cursor-pointer"
                >
                  Add
                </button>
              </div>
            </div>
          ))}

          <button
            type="button"
            onClick={addGroup}
            className="w-full py-2 border-2 border-dashed border-breeze-border hover:border-breeze-accent rounded-lg text-xs font-semibold text-breeze-muted hover:text-breeze-accent transition cursor-pointer"
          >
            ➕ Add Intersecting Condition Group (AND)
          </button>
        </div>
      )}

      {isRawMode && (
        <div>
          <textarea
            value={rawQuery}
            onChange={event => {
              setRawQuery(event.target.value)
              setGroups(parseQuery(event.target.value).groups)
            }}
            className="w-full font-mono text-sm rounded-md border-breeze-border shadow-sm focus:border-breeze-accent focus:ring-breeze-accent p-2 h-24 bg-breeze-view text-breeze-text"
            placeholder='e.g., (ruby OR "ruby on rails") (backend OR fullstack)'
          />
        </div>
      )}

      <div className="bg-breeze-view p-3 rounded-lg border border-breeze-border text-xs text-breeze-text space-y-1.5">
        <span className="font-bold block text-breeze-accent">🔍 Human Interpretation:</span>
        {isRawMode && !parsedRawQuery.supported ? (
          <p className="leading-relaxed text-breeze-muted">
            This query contains search operators or syntax that are preserved in Raw Expert Mode.
          </p>
        ) : visibleGroups.length === 0 ? (
          <p className="leading-relaxed text-breeze-muted italic">You haven't defined parameters yet.</p>
        ) : (
          <p className="leading-relaxed text-breeze-muted">
            Looking for web pages where{' '}
            {visibleGroups.map((group, index) => (
              <React.Fragment key={group.id}>
                {index > 0 && <span className="font-bold text-breeze-accent"> AND </span>}
                any of these keywords appear: (<span className="font-medium underline text-breeze-text">{group.tags.join(', ')}</span>)
              </React.Fragment>
            ))}
            .
          </p>
        )}
      </div>

      <div className="space-y-1">
        <div className="flex justify-between text-[10px] font-bold text-breeze-muted">
          <span>DORK LIVE OUTPUT ({totalLength} chars)</span>
          <span className={totalLength > 400 ? 'text-red-400' : 'text-breeze-muted'}>
            {totalLength > 400 ? '⚠️ Query is dangerously long!' : '✓ Safe length'}
          </span>
        </div>
        <div className="w-full font-mono text-xs bg-breeze-view border border-breeze-border rounded p-2 text-breeze-text select-all overflow-x-auto truncate">
          {rawQuery || <span className="text-breeze-muted italic">...waiting for generator data...</span>}
        </div>
        <div className="w-full bg-breeze-border h-1.5 rounded-full overflow-hidden">
          <div
            className={`h-full transition-all duration-300 ${totalLength > 400 ? 'bg-red-400' : 'bg-breeze-accent'}`}
            style={{ width: `${lengthPercentage}%` }}
          />
        </div>
      </div>
    </div>
  )
}
