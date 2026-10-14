import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "segment",
    "label",
    "input",
    "categorySelect",
    "categoryInput",
    "error",
    "interpretation",
    "segmentsContainer",
    "template"
  ]

  declare readonly segmentTargets: HTMLElement[]
  declare readonly inputTarget: HTMLInputElement
  declare readonly hasInputTarget: boolean
  declare readonly hasInterpretationTarget: boolean
  declare readonly interpretationTarget: HTMLElement
  declare readonly templateTarget: HTMLTemplateElement
  declare readonly segmentsContainerTarget: HTMLElement

  connect(): void {
    this.updateInput()
    this.updateSuffixWildcardAvailability()
  }

  stopPropagation(event: Event): void {
    event.stopPropagation()
  }

  setExact(event: Event): void {
    this.setSegmentMode(event, "exact", (val) => val)
  }

  setWildcardFolder(event: Event): void {
    this.setSegmentMode(event, "folder_wildcard", () => "✨ Any value")
  }

  setWildcardSuffix(event: Event): void {
    const currentTarget = event.currentTarget as HTMLElement
    const container = currentTarget.closest(".segment-container") as HTMLElement | null
    if (!container) return

    const containers = Array.from(this.element.querySelectorAll(".segment-container")) as HTMLElement[]
    const isLast = containers[containers.length - 1] === container

    if (!isLast) return

    this.setSegmentMode(event, "suffix_wildcard", (val) => `${val}... (starts with)`)
  }

  private setSegmentMode(event: Event, mode: string, labelFn: (val: string) => string): void {
    const currentTarget = event.currentTarget as HTMLElement
    const container = currentTarget.closest(".segment-container") as HTMLElement | null
    if (!container) return

    const segment = container.querySelector("[data-path-builder-target='segment']") as HTMLElement | null
    const label = segment?.querySelector("[data-path-builder-target='label']") as HTMLElement | null
    if (!segment || !label) return

    segment.dataset.mode = mode
    const rawVal = segment.dataset.originalValue || "new"
    label.textContent = labelFn(rawVal)
    this.closeDropdown(container)
    this.updateInput()
  }

  applyCustomInput(event: KeyboardEvent): void {
    if (event.key !== "Enter") return
    event.preventDefault()

    const input = event.target as HTMLInputElement
    const val = input.value.trim()
    if (!val) return

    if (val.startsWith("http://") || val.startsWith("https://") || val.includes("://")) {
      try {
        const urlObj = new URL(val)
        this.populateSegmentsFromPath(urlObj.pathname)
        input.value = ""
        return
      } catch (e) {
      }
    }

    const currentTarget = event.currentTarget as HTMLElement
    const container = currentTarget.closest(".segment-container") as HTMLElement | null
    if (!container) return

    const segment = container.querySelector("[data-path-builder-target='segment']") as HTMLElement | null
    const label = segment?.querySelector("[data-path-builder-target='label']") as HTMLElement | null
    if (!segment || !label) return

    segment.dataset.mode = "exact"
    segment.dataset.originalValue = val
    segment.setAttribute("title", val)
    label.textContent = val
    input.value = ""
    this.closeDropdown(container)
    this.updateInput()
  }

  populateSegmentsFromPath(pathname: string): void {
    const cleanPath = pathname.replace(/^\/+/, "").replace(/\/+$/, "")
    const segments = cleanPath ? cleanPath.split("/") : [""]

    const plusButton = this.segmentsContainerTarget.querySelector("button[data-action*='addSegment']")
    this.segmentsContainerTarget.innerHTML = ""

    segments.forEach((seg) => {
      const clone = this.templateTarget.content.cloneNode(true) as DocumentFragment
      const segEl = clone.querySelector("[data-path-builder-target='segment']") as HTMLElement | null
      const labelEl = clone.querySelector("[data-path-builder-target='label']") as HTMLElement | null

      if (segEl && labelEl) {
        segEl.dataset.originalValue = seg
        segEl.setAttribute("title", seg)
        labelEl.textContent = seg
      }
      this.segmentsContainerTarget.appendChild(clone)
    })

    if (plusButton) {
      this.segmentsContainerTarget.appendChild(plusButton)
    }

    this.updateInput()
    this.updateSuffixWildcardAvailability()
  }

  removeSegment(event: Event): void {
    const currentTarget = event.currentTarget as HTMLElement
    const container = currentTarget.closest(".segment-container") as HTMLElement | null
    if (!container) return

    const slash = container.previousElementSibling
    if (slash && slash.classList.contains("segment-slash")) {
      slash.remove()
    } else {
      const nextSlash = container.nextElementSibling
      if (nextSlash && nextSlash.classList.contains("segment-slash")) {
        nextSlash.remove()
      }
    }

    container.remove()
    this.updateInput()
    this.updateSuffixWildcardAvailability()
  }

  addSegment(): void {
    const clone = this.templateTarget.content.cloneNode(true) as DocumentFragment
    const plusButton = this.segmentsContainerTarget.querySelector("button[data-action*='addSegment']")

    if (plusButton) {
      this.segmentsContainerTarget.insertBefore(clone, plusButton)
    } else {
      this.segmentsContainerTarget.appendChild(clone)
    }

    this.updateInput()
    this.updateSuffixWildcardAvailability()
  }

  private updateSuffixWildcardAvailability(): void {
    const containers = Array.from(this.element.querySelectorAll(".segment-container")) as HTMLElement[]

    containers.forEach((container, index) => {
      const suffixBtn = container.querySelector("[data-path-builder-target='suffixWildcardButton']") as HTMLElement | null
      if (!suffixBtn) return

      if (index === containers.length - 1) {
        suffixBtn.classList.remove("hidden")
      } else {
        suffixBtn.classList.add("hidden")
      }
    })
  }

  private closeDropdown(container: HTMLElement): void {
    const dropdownCtrl = this.application.getControllerForElementAndIdentifier(container, "dropdown") as any
    if (dropdownCtrl?.menuTarget) dropdownCtrl.menuTarget.classList.add("hidden")
  }

  updateInput(): void {
    const parts: string[] = []
    const containers = Array.from(this.element.querySelectorAll(".segment-container")) as HTMLElement[]

    containers.forEach((item) => {
      const segment = item.querySelector("[data-path-builder-target='segment']") as HTMLElement | null
      if (!segment) return

      const mode = segment.dataset.mode || "exact"
      const val = segment.dataset.originalValue || "new"

      if (mode === "exact") {
        parts.push(val)
      } else if (mode === "folder_wildcard") {
        parts.push("*")
      } else if (mode === "suffix_wildcard") {
        const baseVal = val === "new" ? "item" : val
        parts.push(`${baseVal}*`)
      }
    })

    if (this.hasInputTarget) {
      let result = "/" + parts.join("/")
      if (result.endsWith("/*/*")) result = result.replace("/*/*", "/*")
      this.inputTarget.value = result
      this.updateInterpretation(result)
    }
  }

  private updateInterpretation(pattern: string): void {
    if (!this.hasInterpretationTarget) return

    let text = `Will match exact path: ${pattern}`
    if (pattern.includes("*")) {
      text = `Will dynamically match any URL starting or matching with pattern structure: ${pattern}`
    }
    this.interpretationTarget.textContent = text
  }

  validate(event: Event): void {
    const targetIdInput = this.element.closest("form")?.querySelector("input[name='target_pattern[target_id]']")
    if (targetIdInput && (targetIdInput as HTMLInputElement).value) return

    const selectEl = this.element.querySelector("[data-path-builder-target='categorySelect']") as HTMLSelectElement
    const inputEl = this.element.querySelector("[data-path-builder-target='categoryInput']") as HTMLInputElement

    const selectVal = selectEl ? selectEl.value.trim() : ""
    const inputVal = inputEl ? inputEl.value.trim() : ""

    if (!selectVal && !inputVal) {
      event.preventDefault()
      event.stopPropagation()
      const err = this.element.querySelector("[data-path-builder-target='error']")
      err?.classList.remove("hidden")
    }
  }
}