import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]

  connect() {
    this.loading = false

    this.observer = new IntersectionObserver(this.handleIntersect.bind(this), {
      rootMargin: "300px",
    })

    if (this.hasLinkTarget) {
      this.observer.observe(this.linkTarget)
    }
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }

  handleIntersect(entries) {
    entries.forEach((entry) => {
      if (entry.isIntersecting && !this.loading) {
        this.loadMore()
      }
    })
  }

  loadMore() {
    if (!this.hasLinkTarget || this.loading) return

    this.loading = true

    const resetLoading = () => {
      setTimeout(() => { this.loading = false }, 200)
      this.linkTarget.removeEventListener("turbo:click-end", resetLoading)
    }
    this.linkTarget.addEventListener("turbo:click-end", resetLoading)

    requestAnimationFrame(() => {
      if (this.hasLinkTarget) {
        this.linkTarget.click()
      } else {
        this.loading = false
      }
    })
  }
}