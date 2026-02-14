/**
 * LiveFilter hooks for Phoenix LiveView
 *
 * Usage:
 *   import { hooks } from "live_filter"
 *
 *   const liveSocket = new LiveSocket("/live", Socket, {
 *     hooks: { ...hooks }
 *   })
 */

const AutoOpenDropdown = {
  mounted() {
    const trigger = this.el.querySelector('[tabindex="0"]')
    if (trigger) {
      requestAnimationFrame(() => {
        trigger.focus()
        this.pushEventTo(this.el, "clear_newly_added", {})
      })
    }
  }
}

// Hook for dropdown triggers to handle keyboard navigation into dropdown
const DropdownTrigger = {
  mounted() {
    this.el.addEventListener('keydown', (e) => {
      const dropdown = this.el.closest('.dropdown')

      switch(e.key) {
        case 'ArrowDown':
        case 'Enter':
        case ' ':
          if (!dropdown?.matches(':focus-within') || e.target === this.el) {
            e.preventDefault()
            const dropdownContent = dropdown?.querySelector('.dropdown-content')
            const firstItem = dropdownContent?.querySelector('[phx-hook="DropdownItem"]')
            if (firstItem) {
              requestAnimationFrame(() => firstItem.focus())
            }
          }
          break

        case 'Escape':
          e.preventDefault()
          this.el.blur()
          break
      }
    })
  }
}

// Safari fix: Use mousedown instead of click for dropdown items
// Safari fires blur before click, closing the dropdown before the event registers
// Also handles keyboard navigation (arrow keys, Enter, Space, Escape)
const DropdownItem = {
  mounted() {
    this.el.addEventListener('mousedown', (e) => {
      e.preventDefault()
      this.triggerEvent()
    })

    this.el.addEventListener('keydown', (e) => {
      const dropdown = this.el.closest('.dropdown-content')
      const items = Array.from(dropdown?.querySelectorAll('[phx-hook="DropdownItem"]') || [])
      const currentIndex = items.indexOf(this.el)

      switch(e.key) {
        case 'Enter':
        case ' ':
          e.preventDefault()
          this.triggerEvent()
          break

        case 'ArrowDown':
          e.preventDefault()
          if (currentIndex < items.length - 1) {
            items[currentIndex + 1].focus()
          }
          break

        case 'ArrowUp':
          e.preventDefault()
          if (currentIndex > 0) {
            items[currentIndex - 1].focus()
          }
          break

        case 'Escape':
          e.preventDefault()
          this.closeDropdown()
          break

        case 'Home':
          e.preventDefault()
          items[0]?.focus()
          break

        case 'End':
          e.preventDefault()
          items[items.length - 1]?.focus()
          break
      }
    })
  },

  triggerEvent() {
    const event = this.el.dataset.event
    const params = {}
    for (const [key, value] of Object.entries(this.el.dataset)) {
      if (key !== 'event') {
        params[key] = value
      }
    }
    this.pushEventTo(this.el, event, params)
  },

  closeDropdown() {
    const dropdown = this.el.closest('.dropdown')
    const trigger = dropdown?.querySelector('[tabindex="0"]')
    if (trigger) {
      trigger.focus()
    }
  }
}

const DropdownFocus = {
  mounted() {
    this.setupObserver()
  },

  updated() {
    this.focusIfOpen()
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect()
    }
  },

  setupObserver() {
    const dropdown = this.el.closest(".dropdown")
    if (!dropdown) return

    this.wasOpen = false
    this.focusIfOpen()

    this.observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.attributeName === "class") {
          const isOpen = dropdown.classList.contains("dropdown-open") || dropdown.matches(":focus-within")
          if (isOpen && !this.wasOpen) {
            this.el.focus()
          }
          this.wasOpen = isOpen
        }
      }
    })

    this.observer.observe(dropdown, { attributes: true })
  },

  focusIfOpen() {
    const dropdown = this.el.closest(".dropdown")
    const isOpen = dropdown?.classList.contains("dropdown-open") || dropdown?.matches(":focus-within")
    if (isOpen && !this.wasOpen) {
      this.el.focus()
      this.wasOpen = true
    }
  },
}

export const hooks = {
  DropdownFocus,
  AutoOpenDropdown,
  DropdownItem,
  DropdownTrigger,
}

export { DropdownFocus, AutoOpenDropdown, DropdownItem, DropdownTrigger }
export default hooks
