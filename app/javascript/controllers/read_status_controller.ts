import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, currentStatus: String }
  declare readonly urlValue: string
  declare readonly currentStatusValue: string

  markAsRead(event: MouseEvent) {
    if (this.currentStatusValue !== "unread" && this.currentStatusValue !== "") return

    if (event.button === 2) return

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": this.getCsrfToken(),
        "Content-Type": "application/json",
        "Accept": "application/json"
      },
      body: JSON.stringify({ status: "watched" })
    })
    .then(response => {
      if (response.ok) {
        this.element.classList.add("opacity-60")
      }
    })
    .catch(error => console.error("Error marking as read:", error))
  }

  private getCsrfToken(): string {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.getAttribute("content") || "" : ""
  }
}