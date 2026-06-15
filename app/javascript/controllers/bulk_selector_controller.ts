import { Controller } from "@hotwired/stimulus"

export default class BulkSelectorController extends Controller {
  readonly checkboxTargets!: HTMLInputElement[]
  readonly groupButtonTargets!: HTMLButtonElement[]
  readonly groupTargets!: HTMLDivElement[]

  static targets = [ "checkbox", "groupButton", "group" ]

  protected getActiveClasses(): string { return "" }
  protected getInactiveClasses(): string { return "" }
  protected getActiveText(): string { return "Clear Group" }
  protected getInactiveText(): string { return "Select Group" }

  toggleGlobal(event: any): void {
    const status: boolean = event.params.status === true || event.params.status === "true"

    this.checkboxTargets.forEach((cb: HTMLInputElement) => cb.checked = status)
    this.groupButtonTargets.forEach((btn: HTMLButtonElement) => this.updateButtonState(btn, status))
  }

  toggleGroup(event: Event): void {
    const button = event.currentTarget as HTMLButtonElement
    const shouldSelect: boolean = button.dataset.status !== "true"

    const groupTargetName = `data-${this.identifier}-target`
    const groupContainer = button.closest(`[${groupTargetName}="group"]`) as HTMLDivElement | null
    if (!groupContainer) return

    const groupCheckboxes = groupContainer.querySelectorAll<HTMLInputElement>(`[${groupTargetName}="checkbox"]`)
    groupCheckboxes.forEach((cb: HTMLInputElement) => cb.checked = shouldSelect)

    this.updateButtonState(button, shouldSelect)
  }

  private updateButtonState(button: HTMLButtonElement, isSelected: boolean): void {
    button.dataset.status = isSelected ? "true" : "false"
    button.innerText = isSelected ? this.getActiveText() : this.getInactiveText()
    button.className = isSelected ? this.getActiveClasses() : this.getInactiveClasses()
  }
}