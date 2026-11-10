import { Controller } from "@hotwired/stimulus"

type BulkScope = "visible" | "all_matching"

export default class extends Controller<HTMLElement> {
  static targets = ["scope"]

  declare readonly scopeTarget: HTMLSelectElement

  syncScope(event: Event): void {
    const selectedScope = (event.currentTarget as HTMLSelectElement).value as BulkScope

    document.querySelectorAll<HTMLSelectElement>("[data-bulk-actions-scope-select]").forEach(select => {
      select.value = selectedScope
    })

    document.querySelectorAll<HTMLAnchorElement>("[data-bulk-actions-show-more-link]").forEach(link => {
      this.updateScopeInLink(link, selectedScope)
    })
  }

  prepareSubmit(event: SubmitEvent): void {
    const form = event.currentTarget as HTMLFormElement
    const submitter = event.submitter as HTMLButtonElement | null
    const scope = this.scopeTarget.value as BulkScope
    const confirmMessage = scope === "all_matching"
      ? submitter?.dataset.confirmAllMatching
      : submitter?.dataset.confirmVisible

    if (confirmMessage && !window.confirm(confirmMessage)) {
      event.preventDefault()
      return
    }

    form.querySelectorAll('input[name="visible_ids[]"]').forEach(input => input.remove())

    let scopeInput = form.querySelector<HTMLInputElement>('input[name="bulk_scope"]')
    if (!scopeInput) {
      scopeInput = document.createElement("input")
      scopeInput.type = "hidden"
      scopeInput.name = "bulk_scope"
      form.appendChild(scopeInput)
    }
    scopeInput.value = scope

    // The server builds the complete unpaginated Results::Query scope itself.
    // Client IDs are only sent for the explicitly page-limited mode.
    if (scope === "all_matching") return

    const resultsFrame = this.element.closest("turbo-frame#results_pool")
    const resultsList = resultsFrame?.querySelector<HTMLElement>("#results_pool_list")

    if (!resultsList) {
      event.preventDefault()
      return
    }

    const visibleCards = Array.from(
      resultsList.querySelectorAll<HTMLElement>("[data-result-card-id]")
    ).filter(card => card.getClientRects().length > 0 && getComputedStyle(card).visibility !== "hidden")

    if (visibleCards.length === 0) {
      event.preventDefault()
      return
    }

    visibleCards.forEach(card => {
      const id = card.dataset.resultCardId
      if (!id) return

      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "visible_ids[]"
      input.value = id
      form.appendChild(input)
    })
  }

  private updateScopeInLink(link: HTMLAnchorElement, scope: BulkScope): void {
    try {
      const url = new URL(link.href, window.location.origin)
      if (scope === "visible") {
        url.searchParams.delete("bulk_scope")
      } else {
        url.searchParams.set("bulk_scope", scope)
      }
      link.href = url.toString()
    } catch {
      // Ignore links that are not valid URLs; bulk submission remains unaffected.
    }
  }
}
