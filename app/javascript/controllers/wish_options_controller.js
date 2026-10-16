import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["option", "addButton", "limit"]

  connect() {
    this.optionTargets.forEach((option, index) => {
      option.hidden = index > 0 && !Array.from(option.querySelectorAll("input")).some(input => input.value.trim() !== "")
    })
    this.refresh()
  }

  add() {
    const option = this.optionTargets.find(option => option.hidden)
    if (!option) return
    option.hidden = false
    this.refresh()
    option.querySelector("input").focus()
  }

  remove(event) {
    const option = event.currentTarget.closest("[data-wish-options-target='option']")
    option.querySelectorAll("input").forEach(input => { input.value = "" })
    option.hidden = true
    this.refresh()
    if (!this.addButtonTarget.hidden) this.addButtonTarget.focus()
  }

  refresh() {
    const full = this.optionTargets.every(option => !option.hidden)
    this.addButtonTarget.hidden = full
    this.limitTarget.hidden = !full
    let number = 0
    this.optionTargets.filter(option => !option.hidden).forEach(option => {
      number += 1
      option.querySelector("[data-option-label]").textContent = `Option ${number}`
      const remove = option.querySelector("button")
      if (remove) remove.setAttribute("aria-label", `Remove option ${number}`)
    })
  }
}
