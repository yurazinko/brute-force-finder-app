import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]

  get linkElement(): HTMLAnchorElement | null {
    return this.hasLinkTarget ? (this.linkTarget as HTMLAnchorElement) : null
  }

  declare readonly linkTarget: HTMLElement
  declare readonly hasLinkTarget: boolean

  private observer!: IntersectionObserver
  private resizeObserver!: ResizeObserver
  private isLoading: boolean = false

  connect(): void {
    this.isLoading = false

    this.observer = new IntersectionObserver(this.handleIntersect.bind(this), {
      rootMargin: "300px",
    })

    if (this.linkElement) {
      this.observer.observe(this.linkElement)
    }
    this.resizeObserver = new ResizeObserver(() => {
      this.checkVisibility()
    })

    this.resizeObserver.observe(document.body)
  }

  disconnect(): void {
    if (this.observer) {
      this.observer.disconnect()
    }
    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
    }
  }

  private handleIntersect(entries: IntersectionObserverEntry[]): void {
    entries.forEach((entry: IntersectionObserverEntry) => {
      if (entry.isIntersecting) {
        this.triggerLoad()
      }
    })
  }

  private checkVisibility(): void {
    if (!this.linkElement || this.isLoading) return

    const rect = this.linkElement.getBoundingClientRect()

    if (rect.top <= window.innerHeight + 300 && rect.bottom >= 0) {
      this.triggerLoad()
    }
  }

  private triggerLoad(): void {
    if (this.linkElement && !this.isLoading) {
      this.isLoading = true

      const listContainer = document.getElementById("results_pool_list")
      if (listContainer) {
        const visibleCards = listContainer.querySelectorAll(":scope > div[id^='result_']:not(.hidden)")
        const currentVisibleCount = visibleCards.length

        const calculatedNextPage = Math.floor(currentVisibleCount / 20) + 1

        try {
          const url = new URL(this.linkElement.href)
          url.searchParams.set("page", calculatedNextPage.toString())

          this.linkElement.href = url.toString()
        } catch (e) {
        }
      }

      this.linkElement.click()
    }
  }
}