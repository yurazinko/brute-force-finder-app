import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  closeBackground(event: MouseEvent): void {
    if (event.target === this.element) {
      this.dismiss()
    }
  }

  closeWithEsc(event: KeyboardEvent): void {
    if (event.key === "Escape") {
      this.dismiss()
    }
  }

  dismiss(): void {
    const frame = this.element.closest("turbo-frame") as HTMLElement | null
    if (frame) {
      frame.innerHTML = ""
    }
  }
}