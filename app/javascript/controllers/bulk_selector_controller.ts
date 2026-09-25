import { Controller } from "@hotwired/stimulus"

export default class BulkSelectorController extends Controller {
  declare readonly checkboxTargets: HTMLInputElement[]
  declare readonly groupButtonTargets: HTMLButtonElement[]
  declare readonly groupTargets: HTMLDivElement[]

  declare readonly hasCheckboxTarget: boolean
  declare readonly hasGroupButtonTarget: boolean

  static targets = ["checkbox", "groupButton", "group"]

  protected getActiveClasses(): string { return "" }
  protected getInactiveClasses(): string { return "" }
  protected getActiveText(): string { return "Clear Group" }
  protected getInactiveText(): string { return "Select Group" }

  toggleGlobal(event: CustomEvent | any): void {
    if (event) event.preventDefault()

    const statusParam = event?.params?.status ?? event?.currentTarget?.dataset[`${this.identifier}StatusParam`]
    const isSelected: boolean = statusParam === true || statusParam === "true"

    const checkboxes = this.getAllCheckboxes()

    checkboxes.forEach((cb: HTMLInputElement) => {
      cb.checked = isSelected
      cb.dispatchEvent(new Event("change", { bubbles: true }))
    })

    this.getAllGroupButtons().forEach((btn: HTMLButtonElement) => {
      this.updateButtonState(btn, isSelected)
    })
  }

  toggleGroup(event: Event): void {
    event.preventDefault()
    const button = event.currentTarget as HTMLButtonElement
    const shouldSelect: boolean = button.dataset.status !== "true"

    const groupTargetName = `data-${this.identifier}-target`
    const groupContainer = button.closest(`[${groupTargetName}="group"]`) as HTMLDivElement | null
    if (!groupContainer) return

    const groupCheckboxes = groupContainer.querySelectorAll<HTMLInputElement>(
      `[${groupTargetName}="checkbox"], input[type="checkbox"].target-item-checkbox`
    )

    groupCheckboxes.forEach((cb: HTMLInputElement) => {
      cb.checked = shouldSelect
      cb.dispatchEvent(new Event("change", { bubbles: true }))
    })

    this.updateButtonState(button, shouldSelect)
  }

  protected updateButtonState(button: HTMLButtonElement, isSelected: boolean): void {
    button.dataset.status = isSelected ? "true" : "false"
    button.innerText = isSelected ? this.getActiveText() : this.getInactiveText()
    button.className = isSelected ? this.getActiveClasses() : this.getInactiveClasses()
  }

  private getAllCheckboxes(): HTMLInputElement[] {
    if (this.hasCheckboxTarget) {
      const targets = this.checkboxTargets
      if (Array.isArray(targets) && targets.length > 0) {
        return targets
      }
    }
    const selector = `[data-${this.identifier}-target="checkbox"], input[type="checkbox"].target-item-checkbox`
    return Array.from(this.element.querySelectorAll<HTMLInputElement>(selector))
  }

  private getAllGroupButtons(): HTMLButtonElement[] {
    if (this.hasGroupButtonTarget) {
      const targets = this.groupButtonTargets
      if (Array.isArray(targets) && targets.length > 0) {
        return targets
      }
    }
    const selector = `[data-${this.identifier}-target="groupButton"], button.category-bulk-btn`
    return Array.from(this.element.querySelectorAll<HTMLButtonElement>(selector))
  }
}