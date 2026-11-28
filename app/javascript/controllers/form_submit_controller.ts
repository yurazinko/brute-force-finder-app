import { Controller } from "@hotwired/stimulus"

export default class extends Controller<HTMLFormElement> {
  submit(): void {
    this.element.requestSubmit()
  }

  validateAndSubmit(event: Event): void {
    const input = event.currentTarget as HTMLInputElement
    const minimumLength = Number(input.dataset.minimumLength || 0)

    if (minimumLength > 0 && input.value.length > 0 && input.value.length < minimumLength) {
      input.setCustomValidity(`Min ${minimumLength} chars`)
      return
    }

    input.setCustomValidity("")

    if (input.value.length === 0) {
      this.submit()
    }
  }
}
