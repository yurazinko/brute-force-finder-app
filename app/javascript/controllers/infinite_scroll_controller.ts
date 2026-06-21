import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]

  // Використовуємо нативне API Stimulus для доступу до таргетів
  get linkElement(): HTMLAnchorElement | null {
    // Оскільки дебаг показав, що target існує, беремо його напряму
    return this.hasLinkTarget ? (this.linkTarget as HTMLAnchorElement) : null
  }

  // Оголошуємо нативні властивості Stimulus, щоб TS не сварився
  declare readonly linkTarget: HTMLElement
  declare readonly hasLinkTarget: boolean

  private observer!: IntersectionObserver

  connect(): void {
    this.observer = new IntersectionObserver(this.handleIntersect.bind(this), {
      rootMargin: "300px", // Збільшимо до 300px, щоб завантаження починалось трохи заздалегідь
    })

    if (this.linkElement) {
      this.observer.observe(this.linkElement)
    }
  }

  disconnect(): void {
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  private handleIntersect(entries: IntersectionObserverEntry[]): void {
    entries.forEach((entry: IntersectionObserverEntry) => {
      if (entry.isIntersecting && this.linkElement) {
        console.log("[InfiniteScroll] Клікаю по лінку, вантажу сторінку...")
        this.linkElement.click()
      }
    })
  }
}