import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  declare readonly segmentTargets: HTMLElement[]
  declare readonly inputTarget: HTMLInputElement
  declare readonly hasInputTarget: boolean

  static targets = ["segment", "label", "input"]

  connect(): void {
    this.updateInput()
  }

  setExact(event: Event): void {
    const currentTarget = event.currentTarget as HTMLElement
    const container = currentTarget.closest(".segment-container") as HTMLElement | null
    if (!container) return

    const segment = container.querySelector("[data-path-builder-target='segment']") as HTMLElement | null
    const label = segment?.querySelector("[data-path-builder-target='label']") as HTMLElement | null
    if (!segment || !label) return

    segment.dataset.mode = "exact"
    label.textContent = segment.dataset.originalValue || ""
    this.closeDropdown(container)
    this.updateInput()
  }

  setAnything(event: Event): void {
    const currentTarget = event.currentTarget as HTMLElement
    const container = currentTarget.closest(".segment-container") as HTMLElement | null
    if (!container) return

    const segment = container.querySelector("[data-path-builder-target='segment']") as HTMLElement | null
    const label = segment?.querySelector("[data-path-builder-target='label']") as HTMLElement | null
    if (!segment || !label) return

    segment.dataset.mode = "anything"
    label.textContent = "{anything}"
    this.closeDropdown(container)
    this.updateInput()
  }

  removeSegment(event: Event): void {
    const currentTarget = event.currentTarget as HTMLElement
    const container = currentTarget.closest(".segment-container") as HTMLElement | null
    if (!container) return

    const containers = Array.from(this.element.querySelectorAll(".segment-container")) as HTMLElement[]
    const index = containers.indexOf(container)

    containers.forEach((item, idx) => {
      const segBtn = item.querySelector("[data-path-builder-target='segment']") as HTMLElement | null
      if (idx >= index && segBtn) {
        segBtn.dataset.mode = "removed"
        item.style.display = "none"
      }
    })

    this.closeDropdown(container)
    this.updateInput()
  }

  private closeDropdown(container: HTMLElement): void {
    const dropdownCtrl = this.application.getControllerForElementAndIdentifier(
      container,
      "dropdown"
    ) as any

    if (dropdownCtrl && typeof dropdownCtrl.menuTarget !== "undefined") {
      dropdownCtrl.menuTarget.classList.add("hidden")
    }
  }

  updateInput(): void {
    const parts: string[] = []
    const containers = Array.from(this.element.querySelectorAll(".segment-container")) as HTMLElement[]

    containers.forEach((item) => {
      const segment = item.querySelector("[data-path-builder-target='segment']") as HTMLElement | null
      const separator = item.nextElementSibling as HTMLElement | null
      if (!segment) return

      const mode = segment.dataset.mode || "exact"

      if (mode === "removed") {
        if (separator && separator.classList.contains("separator-slash")) {
          separator.style.display = "none"
        }
        return
      }

      if (separator && separator.classList.contains("separator-slash")) {
        separator.style.display = "inline"
      }

      if (mode === "exact") {
        const val = segment.dataset.originalValue
        if (val) parts.push(val)
      } else if (mode === "anything") {
        parts.push("*")
      }
    })

    if (this.hasInputTarget) {
      this.inputTarget.value = "/" + parts.join("/")
    }
  }
}