import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  declare readonly menuTarget: HTMLElement
  declare readonly hasMenuTarget: boolean

  static targets = ["menu"]

  toggle(event: Event): void {
    event.stopPropagation()
    if (this.hasMenuTarget) {
      this.menuTarget.classList.toggle("hidden")
    }
  }

  hide(event: Event): void {
    if (this.hasMenuTarget && !this.element.contains(event.target as Node)) {
      this.menuTarget.classList.add("hidden")
    }
  }
}