export type SegmentMode = "exact" | "folder_wildcard" | "suffix_wildcard"

export interface Segment {
  mode: SegmentMode
  value: string
}

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
