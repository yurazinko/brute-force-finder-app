import React, { useState, useEffect } from 'react'

interface DorkGroup {
  id: string
  tags: string[]
  inputValue: string
}

interface DorkBuilderProps {
  initialValue?: string
  inputName: string
}

const parseInitialValueToGroups = (value: string): DorkGroup[] => {
  if (!value || !value.trim()) {
    return [{ id: '1', tags: [], inputValue: '' }]
  }

  try {
    const groupMatches = value.match(/\(([^)]+)\)/g)

    if (!groupMatches) {
      return [{ id: '1', tags: [], inputValue: '' }]
    }

    return groupMatches.map((groupStr, index) => {
      const innerContent = groupStr.slice(1, -1)

      const rawTags = innerContent.split(/\s+[oO][rR]\s+/)

      const tags = rawTags
        .map(tag => {
          let cleaned = tag.trim()
          if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
            cleaned = cleaned.slice(1, -1)
          }
          return cleaned.toLowerCase()
        })
        .filter(tag => tag.length > 0)

      return {
        id: `init-${index}-${Date.now()}`,
        tags,
        inputValue: ''
      }
    })
  } catch (e) {
    return [{ id: '1', tags: [], inputValue: '' }]
  }
}

export const DorkBuilder: React.FC<DorkBuilderProps> = ({ initialValue = '', inputName }) => {
  const [groups, setGroups] = useState<DorkGroup[]>(() => parseInitialValueToGroups(initialValue))
  const [rawQuery, setRawQuery] = useState<string>(initialValue)
  const [isRawMode, setIsRawMode] = useState<boolean>(false)

  useEffect(() => {
    if (initialValue && groups.length === 1 && groups[0].tags.length === 0) {
      setIsRawMode(true)
    }
  }, [initialValue])

  useEffect(() => {
    if (!isRawMode) {
      const generated = groups
        .filter(g => g.tags.length > 0)
        .map(g => {
          const formattedTags = g.tags.map(t => t.includes(' ') ? `"${t}"` : t)
          return `(${formattedTags.join(' OR ')})`
        })
        .join(' ')
      setRawQuery(generated)
    }
  }, [groups, isRawMode])

  const addTag = (groupId: string) => {
    setGroups(groups.map(g => {
      if (g.id === groupId && g.inputValue.trim()) {
        const nextTags = [...g.tags, g.inputValue.trim().toLowerCase()]
        return { ...g, tags: nextTags, inputValue: '' }
      }
      return g
    }))
  }

  const removeTag = (groupId: string, tagIndex: number) => {
    setGroups(groups.map(g => {
      if (g.id === groupId) {
        return { ...g, tags: g.tags.filter((_, i) => i !== tagIndex) }
      }
      return g
    }))
  }

  const addGroup = () => {
    setGroups([...groups, { id: Date.now().toString(), tags: [], inputValue: '' }])
  }

  const removeGroup = (groupId: string) => {
    setGroups(groups.filter(g => g.id !== groupId))
  }

  const totalLength = rawQuery.length
  const lengthPercentage = Math.min((totalLength / 500) * 100, 100)

  return (
    <div className="bg-breeze-bg p-4 border border-breeze-border rounded-xl space-y-4 text-breeze-text">
      <input type="hidden" name={inputName} value={rawQuery} />

      <div className="flex justify-between items-center border-b border-breeze-border pb-2">
        <span className="text-sm font-bold">Dork Query Configurator</span>
        <div className="bg-breeze-view p-0.5 rounded-lg border border-breeze-border text-xs flex">
          <button
            type="button"
            className={`px-3 py-1 rounded-md font-medium transition cursor-pointer ${!isRawMode ? 'bg-breeze-accent text-breeze-view shadow-sm' : 'text-breeze-muted hover:text-breeze-text'}`}
            onClick={() => setIsRawMode(false)}
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
                {index === 0 ? "🎯 Condition Group 1 (Must match any of these)" : `➕ AND MUST ALSO match any of Group ${index + 1}`}
              </span>

              <div className="flex flex-wrap gap-1.5 mb-2">
                {group.tags.map((tag, tIdx) => (
                  <span key={tIdx} className="inline-flex items-center text-xs bg-breeze-bg text-breeze-text px-2 py-1 rounded font-medium border border-breeze-border shadow-sm">
                    {tag.includes(' ') ? `"${tag}"` : tag}
                    <button type="button" onClick={() => removeTag(group.id, tIdx)} className="ml-1 text-breeze-muted hover:text-red-400 font-bold cursor-pointer">×</button>
                  </span>
                ))}
              </div>

              <div className="flex max-w-xs">
                <input
                  type="text"
                  value={group.inputValue}
                  placeholder="e.g., ruby, engineer, 'remote'"
                  className="w-full text-xs rounded-l-md border-breeze-border py-1.5 px-2 bg-breeze-bg focus:ring-1 focus:ring-breeze-accent focus:border-breeze-accent text-breeze-text"
                  onChange={(e) => setGroups(groups.map(g => g.id === group.id ? { ...g, inputValue: e.target.value } : g))}
                  onKeyDown={(e) => e.key === 'Enter' && (e.preventDefault(), addTag(group.id))}
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
            onChange={(e) => setRawQuery(e.target.value)}
            className="w-full font-mono text-sm rounded-md border-breeze-border shadow-sm focus:border-breeze-accent focus:ring-breeze-accent p-2 h-24 bg-breeze-view text-breeze-text"
            placeholder='e.g., (ruby OR "ruby on rails") (backend OR fullstack)'
          />
        </div>
      )}

      <div className="bg-breeze-view p-3 rounded-lg border border-breeze-border text-xs text-breeze-text space-y-1.5">
        <span className="font-bold block text-breeze-accent">🔍 Human Interpretation:</span>
        <p className="leading-relaxed text-breeze-muted">
          Looking for web pages where{' '}
          {groups.filter(g => g.tags.length > 0).length === 0 ? (
            <span className="text-breeze-muted italic">you haven't defined parameters yet</span>
          ) : (
            groups
              .filter(g => g.tags.length > 0)
              .map((g, i) => (
                <span key={g.id}>
                  {i > 0 && <span className="font-bold text-breeze-accent"> AND </span>}
                  any of these keywords appear: (<span className="font-medium underline text-breeze-text">{g.tags.join(', ')}</span>)
                </span>
              ))
          )}
          .
        </p>
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