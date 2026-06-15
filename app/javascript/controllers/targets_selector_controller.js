import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "checkbox", "groupButton", "group" ]

  toggleGlobal(event) {
    const status = event.params.status

    this.checkboxTargets.forEach(cb => cb.checked = status)

    this.groupButtonTargets.forEach(btn => {
      this.updateButtonVisual(btn, status)
    })
  }

  toggleGroup(event) {
    const button = event.currentTarget
    const isCurrentlyChecked = button.dataset.status === "true"
    const nextStatus = !isCurrentlyChecked

    const groupCard = button.closest('[data-targets-selector-target="group"]')
    if (!groupCard) return

    const groupCheckboxes = groupCard.querySelectorAll('[data-targets-selector-target="checkbox"]')
    groupCheckboxes.forEach(cb => cb.checked = nextStatus)

    this.updateButtonVisual(button, nextStatus)
  }

  updateButtonVisual(button, isSelected) {
    button.dataset.status = isSelected ? "true" : "false"
    button.innerText = isSelected ? "Clear Group" : "Select All Group"

    if (isSelected) {
      button.className = "category-bulk-btn text-[11px] bg-gray-200 border border-gray-400 text-gray-800 px-2 py-0.5 rounded shadow-inner font-medium transition cursor-pointer"
    } else {
      button.className = "category-bulk-btn text-[11px] bg-white border border-gray-300 text-gray-700 hover:bg-gray-100 px-2 py-0.5 rounded shadow-sm font-medium transition cursor-pointer"
    }
  }
}