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

export const DorkBuilder: React.FC<DorkBuilderProps> = ({ initialValue = '', inputName }) => {
  const [isRawMode, setIsRawMode] = useState<boolean>(false)
  const [rawQuery, setRawQuery] = useState<string>(initialValue)

  const [groups, setGroups] = useState<DorkGroup[]>([
    { id: '1', tags: ['ruby', 'ruby on rails'], inputValue: '' },
    { id: '2', tags: ['backend', 'fullstack', 'developer'], inputValue: '' }
  ])

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
    <div className="bg-gray-50 p-4 border border-gray-200 rounded-xl space-y-4">
      <input type="hidden" name={inputName} value={rawQuery} />

      <div className="flex justify-between items-center border-b border-gray-200 pb-2">
        <span className="text-sm font-bold text-gray-800">Dork Query Configurator</span>
        <div className="bg-white p-0.5 rounded-lg border border-gray-200 text-xs flex">
          <button
            type="button"
            className={`px-3 py-1 rounded-md font-medium transition ${!isRawMode ? 'bg-blue-600 text-white shadow-sm' : 'text-gray-600 hover:text-gray-900'}`}
            onClick={() => setIsRawMode(false)}
          >
            🧙‍♂️ Wizard Constructor
          </button>
          <button
            type="button"
            className={`px-3 py-1 rounded-md font-medium transition ${isRawMode ? 'bg-blue-600 text-white shadow-sm' : 'text-gray-600 hover:text-gray-900'}`}
            onClick={() => setIsRawMode(true)}
          >
            ⌨️ Raw Expert Mode
          </button>
        </div>
      </div>

      {!isRawMode && (
        <div className="space-y-4">
          {groups.map((group, index) => (
            <div key={group.id} className="bg-white p-3 border border-gray-200 rounded-lg shadow-sm relative">
              {index > 0 && (
                <button
                  type="button"
                  onClick={() => removeGroup(group.id)}
                  className="absolute top-2 right-2 text-gray-400 hover:text-red-500 text-xs"
                >
                  ✕ Remove Group
                </button>
              )}
              <span className="text-[10px] font-bold text-blue-600 tracking-wider uppercase block mb-2">
                {index === 0 ? "🎯 Condition Group 1 (Must match any of these)" : `➕ AND MUST ALSO match any of Group ${index + 1}`}
              </span>

              <div className="flex flex-wrap gap-1.5 mb-2">
                {group.tags.map((tag, tIdx) => (
                  <span key={tIdx} className="inline-flex items-center text-xs bg-gray-100 text-gray-800 px-2 py-1 rounded font-medium border border-gray-200 shadow-sm">
                    {tag.includes(' ') ? `"${tag}"` : tag}
                    <button type="button" onClick={() => removeTag(group.id, tIdx)} className="ml-1 text-gray-400 hover:text-red-500 font-bold">×</button>
                  </span>
                ))}
              </div>

              <div className="flex max-w-xs">
                <input
                  type="text"
                  value={group.inputValue}
                  placeholder="e.g., ruby, engineer, 'remote'"
                  className="w-full text-xs rounded-l-md border-gray-300 py-1.5 px-2 focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
                  onChange={(e) => setGroups(groups.map(g => g.id === group.id ? { ...g, inputValue: e.target.value } : g))}
                  onKeyDown={(e) => e.key === 'Enter' && (e.preventDefault(), addTag(group.id))}
                />
                <button
                  type="button"
                  onClick={() => addTag(group.id)}
                  className="bg-gray-800 hover:bg-gray-900 text-white text-xs px-3 rounded-r-md font-medium"
                >
                  Add
                </button>
              </div>
            </div>
          ))}

          <button
            type="button"
            onClick={addGroup}
            className="w-full py-2 bg-dashed border-2 border-dashed border-gray-300 hover:border-blue-400 rounded-lg text-xs font-semibold text-gray-500 hover:text-blue-600 transition"
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
            className="w-full font-mono text-sm rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 p-2 h-24"
            placeholder='e.g., (ruby OR "ruby on rails") (backend OR fullstack)'
          />
        </div>
      )}

      <div className="bg-blue-50/50 p-3 rounded-lg border border-blue-100 text-xs text-blue-900 space-y-1.5">
        <span className="font-bold block text-blue-800">🔍 Human Interpretation:</span>
        <p className="leading-relaxed">
          Looking for web pages where{' '}
          {groups.filter(g => g.tags.length > 0).length === 0 ? (
            <span className="text-gray-400 italic">you haven't defined parameters yet</span>
          ) : (
            groups
              .filter(g => g.tags.length > 0)
              .map((g, i) => (
                <span key={g.id}>
                  {i > 0 && <span className="font-bold text-indigo-600"> AND </span>}
                  any of these keywords appear: (<span className="font-medium underline">{g.tags.join(', ')}</span>)
                </span>
              ))
          )}
          .
        </p>
      </div>

      <div className="space-y-1">
        <div className="flex justify-between text-[10px] font-bold text-gray-500">
          <span>DORK LIVE OUTPUT ({totalLength} chars)</span>
          <span className={totalLength > 400 ? 'text-red-500' : 'text-gray-400'}>
            {totalLength > 400 ? '⚠️ Query is getting dangerously long!' : '✓ Safe length'}
          </span>
        </div>
        <div className="w-full font-mono text-xs bg-white border border-gray-200 rounded p-2 text-gray-600 select-all overflow-x-auto truncate">
          {rawQuery || <span className="text-gray-400 italic">...waiting for generator data...</span>}
        </div>
        <div className="w-full bg-gray-200 h-1.5 rounded-full overflow-hidden">
          <div
            className={`h-full transition-all duration-300 ${totalLength > 400 ? 'bg-red-500' : 'bg-green-500'}`}
            style={{ width: `${lengthPercentage}%` }}
          />
        </div>
      </div>
    </div>
  )
}