import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  private mutationObserver?: MutationObserver

  connect(): void {
    const listEl = document.getElementById("results_pool_list")
    const emptyStateEl = document.getElementById("empty_state")

    if (!listEl || !emptyStateEl) return

    const checkState = () => {
      const hasCards = listEl.querySelectorAll('[data-controller~="result-card"]').length > 0

      if (hasCards) {
        emptyStateEl.classList.add("hidden")
        emptyStateEl.style.setProperty("display", "none", "important")
      } else {
        emptyStateEl.classList.remove("hidden")
        emptyStateEl.style.setProperty("display", "block", "important")
      }
    }

    checkState()

    this.mutationObserver = new MutationObserver(() => checkState())
    this.mutationObserver.observe(listEl, { childList: true })
  }

  disconnect(): void {
    this.mutationObserver?.disconnect()
  }
}