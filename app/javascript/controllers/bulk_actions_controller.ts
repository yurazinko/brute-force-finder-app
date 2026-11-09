import { Controller } from "@hotwired/stimulus"

export default class extends Controller<HTMLFormElement> {
  prepareSubmit(event: SubmitEvent): void {
    const form = event.currentTarget as HTMLFormElement
    const submitter = event.submitter as HTMLButtonElement | null
    const confirmMessage = submitter?.dataset.confirm

    // Bulk actions intentionally use a native form submission, not Turbo Frames/Streams.
    if (confirmMessage && !window.confirm(confirmMessage)) {
      event.preventDefault()
      return
    }

    form.querySelectorAll('input[name="visible_ids[]"]').forEach(input => input.remove())

    const resultsFrame = form.closest("turbo-frame#results_pool")
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
}
