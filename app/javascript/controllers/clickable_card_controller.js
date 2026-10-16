import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.element.addEventListener("click", this.openCard)
    this.element.addEventListener("keydown", this.openFromKeyboard)
  }

  disconnect() {
    this.element.removeEventListener("click", this.openCard)
    this.element.removeEventListener("keydown", this.openFromKeyboard)
  }

  openCard = (event) => {
    if (event.target.closest("a, button, form, details, summary, input, textarea, select, label, dialog")) return
    window.location.assign(this.urlValue)
  }

  openFromKeyboard = (event) => {
    if (event.target !== this.element || !["Enter", " "].includes(event.key)) return
    event.preventDefault()
    window.location.assign(this.urlValue)
  }
}
