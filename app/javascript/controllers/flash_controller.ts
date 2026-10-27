import { Controller } from "@hotwired/stimulus"

export default class extends Controller<HTMLElement> {
  connect() {
    (window as any).showGlobalFlash = (message: string, type: "notice" | "error" = "notice") => {
      this.show(message, type)
    }

    this.setupAutoDismiss(this.element.querySelectorAll(".flash-message"))
  }

  show(message: string, type: string = "notice") {
    let container = document.getElementById("flash-container")
    if (!container) {
      container = document.createElement("div")
      container.id = "flash-container"
      container.className = "fixed top-5 right-5 z-50 flex flex-col gap-2 max-w-md w-full pointer-events-none px-4 sm:px-0"
      document.body.appendChild(container)
    }

    const colorClasses = type === "error" || type === "alert"
      ? "bg-red-950/90 border-red-500/30 text-red-200"
      : "bg-green-950/90 border-green-500/30 text-green-200"

    const el = document.createElement("div")
    el.className = `flash-message pointer-events-auto transition-all duration-300 transform translate-y-0 opacity-100 p-4 rounded-xl border shadow-lg flex items-start justify-between gap-3 backdrop-blur-md ${colorClasses}`
    el.innerHTML = `
      <div class="flex items-center space-x-3">
        <span class="text-sm font-medium">${message}</span>
      </div>
      <button type="button" data-action="click->flash#dismiss" class="text-gray-400 hover:text-white transition p-1 shrink-0">✕</button>
    `

    container.appendChild(el)
    this.scheduleDismiss(el)
  }

  dismiss(event: Event) {
    const target = (event.currentTarget as HTMLElement).closest(".flash-message")
    if (target) {
      this.removeElement(target as HTMLElement)
    }
  }

  private setupAutoDismiss(elements: NodeListOf<Element>) {
    elements.forEach((el) => {
      this.scheduleDismiss(el as HTMLElement)
    })
  }

  private scheduleDismiss(el: HTMLElement) {
    setTimeout(() => {
      this.removeElement(el)
    }, 5000)
  }

  private removeElement(el: HTMLElement) {
    if (!el.isConnected) return
    el.style.transition = "opacity 0.5s ease, transform 0.5s ease"
    el.style.opacity = "0"
    el.style.transform = "translateY(-10px)"
    setTimeout(() => el.remove(), 500)
  }
}
