import { Controller } from "@hotwired/stimulus"
import React from "react"
import { createRoot } from "react-dom/client"
import { DorkBuilder } from "../components/DorkBuilder"

export default class extends Controller {
  static values = {
    initialValue: String,
    inputName: String
  }

  declare readonly initialValueValue: string
  declare readonly inputNameValue: string

  connect() {
    const root = createRoot(this.element)
    root.render(
      React.createElement(DorkBuilder, {
        initialValue: this.initialValueValue,
        inputName: this.inputNameValue
      })
    )
  }
}
