import React from "react"
import { PathBuilderProps } from "./types"
import { TargetEditor } from "./TargetEditor"
import { PatternBuilder } from "./PatternBuilder"

export const PathBuilder: React.FC<PathBuilderProps> = (props) => {
  if (props.mode === "target") return <TargetEditor {...props} />
  return <PatternBuilder {...props} />
}

export default PathBuilder