import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  private observer?: MutationObserver

  connect(): void {
    this.observer = new MutationObserver(() => this.sortResults())
    this.observer.observe(this.element, { childList: true, subtree: true })
    this.sortResults()
  }

  disconnect(): void {
    this.observer?.disconnect()
  }

  private sortResults(): void {
    const cards = Array.from(this.element.querySelectorAll<HTMLElement>("[data-quick-result]"))
    const sorted = cards.slice().sort((left, right) => this.compare(left, right))

    sorted.forEach((card, index) => {
      if (this.element.children[index] !== card) {
        this.element.insertBefore(card, this.element.children[index] ?? null)
      }
    })
  }

  private compare(left: HTMLElement, right: HTMLElement): number {
    const leftCaptcha = left.dataset.verificationStatus === "unverified_captcha" ? 1 : 0
    const rightCaptcha = right.dataset.verificationStatus === "unverified_captcha" ? 1 : 0
    if (leftCaptcha !== rightCaptcha) return leftCaptcha - rightCaptcha

    const scoreDifference = Number(right.dataset.relevanceScore) - Number(left.dataset.relevanceScore)
    if (scoreDifference !== 0) return scoreDifference

    return Number(right.dataset.matchedCount) - Number(left.dataset.matchedCount)
  }
}
