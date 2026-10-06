import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "emptyState"]

  declare readonly listTarget: HTMLElement
  declare readonly emptyStateTarget: HTMLElement
  declare readonly hasListTarget: boolean
  declare readonly hasEmptyStateTarget: boolean

  private mutationObserver?: MutationObserver

  connect(): void {
    if (this.hasListTarget) {
      this.mutationObserver = new MutationObserver(() => this.toggleEmptyState())
      this.mutationObserver.observe(this.listTarget, { childList: true })
    }
    this.toggleEmptyState()
  }

  disconnect(): void {
    this.mutationObserver?.disconnect()
  }

  private toggleEmptyState(): void {
    if (!this.hasListTarget || !this.hasEmptyStateTarget) return

    const hasChildren = this.listTarget.children.length > 0
    this.emptyStateTarget.classList.toggle("hidden", hasChildren)
  }
}