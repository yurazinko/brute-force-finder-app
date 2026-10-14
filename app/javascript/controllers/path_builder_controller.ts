import { Controller } from "@hotwired/stimulus"
import React from "react"
import { createRoot, Root } from "react-dom/client"
import { PathBuilder } from "../components/PathBuilder"

export default class extends Controller {
  static values = {
    targetDomain: String,
    initialPatterns: Array,
    categories: Array,
    resultUrl: String,
    matchedTargetId: Number,
    authenticityToken: String,
    createEndpoint: String,
    redirectPath: String
  }

  declare readonly targetDomainValue: string
  declare readonly initialPatternsValue: any[]
  declare readonly categoriesValue: any[]
  declare readonly resultUrlValue: string
  declare readonly matchedTargetIdValue: number
  declare readonly authenticityTokenValue: string
  declare readonly createEndpointValue: string
  declare readonly redirectPathValue: string

  private root: Root | null = null

  connect(): void {
    this.root = createRoot(this.element)
    this.root.render(
      React.createElement(PathBuilder, {
        targetDomain: this.targetDomainValue,
        initialPatterns: this.initialPatternsValue,
        categories: this.categoriesValue,
        resultUrl: this.resultUrlValue,
        matchedTargetId: this.matchedTargetIdValue,
        authenticityToken: this.authenticityTokenValue,
        createEndpoint: this.createEndpointValue,
        redirectPath: this.redirectPathValue
      })
    )
  }

  disconnect(): void {
    if (this.root) {
      this.root.unmount()
      this.root = null
    }
  }
}