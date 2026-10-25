import { Controller } from "@hotwired/stimulus"
import React from "react"
import { createRoot, type Root } from "react-dom/client"
import { PathBuilder, type Category, type PathBuilderProps, type SearchOption } from "../components/PathBuilder"

type Pattern = {
  id: number | string
  path_pattern: string
  is_active: boolean
}

export default class extends Controller<HTMLElement> {
  static values = {
    mode: String,
    targetId: String,
    targetName: String,
    targetDomain: String,
    targetCategoryId: String,
    targetIsActive: Boolean,
    targetAllowQueryStrings: Boolean,
    initialPatterns: Array,
    categories: Array,
    searches: Array,
    initialSearchIds: Array,
    resultUrl: String,
    matchedTargetId: String,
    resultId: String,
    authenticityToken: String,
    createEndpoint: String,
    redirectPath: String,
    targetCreateEndpoint: String,
    targetUpdateEndpoint: String,
    cancelPath: String,
  }

  declare readonly modeValue: string
  declare readonly hasModeValue: boolean
  declare readonly targetIdValue: string
  declare readonly targetNameValue: string
  declare readonly targetDomainValue: string
  declare readonly targetCategoryIdValue: string
  declare readonly targetIsActiveValue: boolean
  declare readonly targetAllowQueryStringsValue: boolean
  declare readonly initialPatternsValue: Pattern[]
  declare readonly categoriesValue: Category[]
  declare readonly searchesValue: SearchOption[]
  declare readonly initialSearchIdsValue: Array<string | number>
  declare readonly resultUrlValue: string
  declare readonly matchedTargetIdValue: string
  declare readonly resultIdValue: string
  declare readonly authenticityTokenValue: string
  declare readonly createEndpointValue: string
  declare readonly redirectPathValue: string
  declare readonly targetCreateEndpointValue: string
  declare readonly targetUpdateEndpointValue: string
  declare readonly cancelPathValue: string

  private root?: Root

  connect() {
    this.root = createRoot(this.element)

    const props: PathBuilderProps = {
      mode: this.hasModeValue ? (this.modeValue as PathBuilderProps["mode"]) : "pattern",
      targetId: this.targetIdValue || undefined,
      targetName: this.targetNameValue || "",
      targetDomain: this.targetDomainValue || "",
      targetCategoryId: this.targetCategoryIdValue || undefined,
      targetIsActive: this.targetIsActiveValue,
      targetAllowQueryStrings: this.targetAllowQueryStringsValue,
      initialPatterns: this.initialPatternsValue || [],
      categories: this.categoriesValue || [],
      searches: this.searchesValue || [],
      initialSearchIds: this.initialSearchIdsValue || [],
      resultUrl: this.resultUrlValue || undefined,
      matchedTargetId: this.matchedTargetIdValue ? Number(this.matchedTargetIdValue) : undefined,
      resultId: this.resultIdValue || undefined,
      authenticityToken: this.authenticityTokenValue,
      createEndpoint: this.createEndpointValue,
      redirectPath: this.redirectPathValue || window.location.pathname,
      targetCreateEndpoint: this.targetCreateEndpointValue || undefined,
      targetUpdateEndpoint: this.targetUpdateEndpointValue || undefined,
      cancelPath: this.cancelPathValue || undefined,
    }

    this.root.render(React.createElement(PathBuilder, props))
  }

  disconnect() {
    this.root?.unmount()
    this.root = undefined
  }
}
