import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  appendVisibleIds(event) {
    const form = event.target

    form.querySelectorAll('input[name="visible_ids[]"]').forEach(el => el.remove())

    const visibleCards = document.querySelectorAll('[data-result-card-id]')

    visibleCards.forEach(card => {
      const id = card.dataset.resultCardId
      if (id) {
        const input = document.createElement('input')
        input.type = 'hidden'
        input.name = 'visible_ids[]'
        input.value = id
        form.appendChild(input)
      }
    })
  }
}
