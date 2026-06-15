import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "checkbox", "groupButton", "group" ]

  toggleGlobal(event) {
    const status = event.params.status

    this.checkboxTargets.forEach(cb => cb.checked = status)
    this.groupButtonTargets.forEach(btn => this.updateButtonState(btn, status))
  }

  toggleGroup(event) {
    const button = event.currentTarget
    const shouldSelect = button.dataset.status === "false"

    const groupContainer = button.closest('[data-pipeline-selector-target="group"]')
    if (!groupContainer) return

    const groupCheckboxes = groupContainer.querySelectorAll('[data-pipeline-selector-target="checkbox"]')
    groupCheckboxes.forEach(cb => cb.checked = shouldSelect)

    this.updateButtonState(button, shouldSelect)
  }

  updateButtonState(button, isSelected) {
    button.dataset.status = isSelected ? "true" : "false"
    button.innerText = isSelected ? "Clear Group" : "Select Group"

    if (isSelected) {
      button.className = "group-toggle-btn text-[10px] text-gray-500 hover:underline font-medium cursor-pointer"
    } else {
      button.className = "group-toggle-btn text-[10px] text-indigo-600 hover:underline font-semibold cursor-pointer"
    }
  }
}