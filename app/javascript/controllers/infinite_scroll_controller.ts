import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]

  connect() {
    this.loading = false
    this.observer = new IntersectionObserver(this.handleIntersect.bind(this), {
      rootMargin: "200px",
    })

    if (this.hasLinkTarget) {
      this.observer.observe(this.linkTarget)
    }

    this.turboRenderHandler = () => { this.loading = false }
    document.addEventListener("turbo:render", this.turboRenderHandler)
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
    document.removeEventListener("turbo:render", this.turboRenderHandler)
  }

  handleIntersect(entries) {
    entries.forEach((entry) => {
      if (entry.isIntersecting && !this.loading) {
        this.loadMore()
      }
    })
  }

  loadMore() {
    this.loading = true

    requestAnimationFrame(() => {
      if (this.hasLinkTarget) {
        this.linkTarget.click()
      }
    })
  }
}