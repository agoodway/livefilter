/**
 * LiveFilter hooks for Phoenix LiveView
 *
 * @description Functional JavaScript implementation of LiveFilter hooks
 * for keyboard navigation, dropdown focus management, and text input focus preservation.
 *
 * @example
 * ```javascript
 * import { hooks } from "live_filter"
 *
 * const liveSocket = new LiveSocket("/live", Socket, {
 *   hooks: { ...hooks }
 * })
 * ```
 */

// ============================================================================
// Pure Helper Functions
// ============================================================================

const querySelector = (parent, selector) =>
  parent?.querySelector(selector) ?? null

const querySelectorAll = (parent, selector) =>
  parent ? Array.from(parent.querySelectorAll(selector)) : []

const closestElement = (el, selector) =>
  el?.closest(selector) ?? null

const isFocused = (el) => document.activeElement === el

const isDropdownOpen = (dropdown) =>
  dropdown?.classList.contains("dropdown-open") ||
  dropdown?.matches(":focus-within") ||
  false

const getDatasetParams = (dataset) =>
  Object.entries(dataset)
    .filter(([key]) => key !== "event")
    .reduce((acc, [key, value]) => ({ ...acc, [key]: value ?? "" }), {})

const clamp = (value, min, max) =>
  Math.max(min, Math.min(max, value))

const focusElement = (el) => {
  el?.focus()
}

const focusElementDeferred = (el) => {
  if (el) {
    requestAnimationFrame(() => el.focus())
  }
}

const setInputValue = (input, value) => {
  if (input.value !== value) {
    input.value = value
  }
}

const setInputCursor = (input, pos) => {
  const safePos = clamp(pos, 0, input.value.length)
  input.setSelectionRange(safePos, safePos)
}

// ============================================================================
// Keyboard Navigation Handlers
// ============================================================================

const createKeydownHandler = (handlers) =>
  (event, context) => handlers[event.key]?.(event, context)

const preventAndRun = (event, fn) => {
  event.preventDefault()
  fn()
}

// ============================================================================
// AutoOpenDropdown Hook
// ============================================================================

const AutoOpenDropdown = {
  mounted() {
    const trigger = querySelector(this.el, '[tabindex="0"]')
    if (trigger) {
      focusElementDeferred(trigger)
      requestAnimationFrame(() => {
        this.pushEventTo(this.el, "clear_newly_added", {})
      })
    }
  },
}

// ============================================================================
// DropdownTrigger Hook
// ============================================================================

const handleDropdownOpen = (event, el) => {
  const dropdown = closestElement(el, ".dropdown")
  const shouldOpen = !isDropdownOpen(dropdown) || event.target === el

  if (shouldOpen) {
    event.preventDefault()
    const content = querySelector(dropdown, ".dropdown-content")
    const firstItem = querySelector(content, '[phx-hook="DropdownItem"]')
    focusElementDeferred(firstItem)
  }
}

const DropdownTrigger = {
  mounted() {
    const el = this.el
    const handleKeydown = createKeydownHandler({
      ArrowDown: (e) => handleDropdownOpen(e, el),
      Enter: (e) => handleDropdownOpen(e, el),
      " ": (e) => handleDropdownOpen(e, el),
      Escape: (e) => preventAndRun(e, () => el.blur()),
    })

    el.addEventListener("keydown", (e) => {
      handleKeydown(e, { el })
    })
  },
}

// ============================================================================
// DropdownItem Hook
// ============================================================================

const DropdownItem = {
  mounted() {
    const el = this.el
    const hook = this

    const triggerEvent = () => {
      const event = el.dataset.event
      if (event) {
        const params = getDatasetParams(el.dataset)
        hook.pushEventTo(el, event, params)
      }
      if (el.dataset.closeOnSelect === "true") {
        closeDropdown()
      }
    }

    const closeDropdown = () => {
      const dropdown = closestElement(el, ".dropdown")
      const trigger = querySelector(dropdown, '[tabindex="0"]')
      trigger?.blur()
    }

    const getDropdownItems = () =>
      querySelectorAll(
        closestElement(el, ".dropdown-content"),
        '[phx-hook="DropdownItem"]'
      )

    const getCurrentIndex = (items) => items.indexOf(el)

    const focusItemAt = (items, index) => {
      focusElement(items[index] ?? null)
    }

    // Mousedown handler (Safari fix: blur fires before click)
    el.addEventListener("mousedown", (e) => {
      e.preventDefault()
      triggerEvent()
    })

    // Keyboard navigation
    const handleKeydown = createKeydownHandler({
      Enter: (e) => preventAndRun(e, triggerEvent),
      " ": (e) => preventAndRun(e, triggerEvent),
      Escape: (e) => preventAndRun(e, closeDropdown),
      ArrowDown: (e) => {
        e.preventDefault()
        const items = getDropdownItems()
        const idx = getCurrentIndex(items)
        if (idx < items.length - 1) focusItemAt(items, idx + 1)
      },
      ArrowUp: (e) => {
        e.preventDefault()
        const items = getDropdownItems()
        const idx = getCurrentIndex(items)
        if (idx > 0) focusItemAt(items, idx - 1)
      },
      Home: (e) => {
        e.preventDefault()
        focusItemAt(getDropdownItems(), 0)
      },
      End: (e) => {
        e.preventDefault()
        const items = getDropdownItems()
        focusItemAt(items, items.length - 1)
      },
    })

    el.addEventListener("keydown", (e) => {
      handleKeydown(e, { el })
    })
  },
}

// ============================================================================
// MaintainFocus Hook
// ============================================================================

const createMaintainFocusHook = () => {
  const state = {
    input: null,
    wasFocused: false,
    cursorPos: null,
  }

  const findInput = (el) =>
    querySelector(el, 'input[type="text"]')

  const captureState = (input) => {
    if (input && isFocused(input)) {
      return {
        input,
        wasFocused: true,
        cursorPos: input.selectionStart,
      }
    }
    return { input, wasFocused: false, cursorPos: null }
  }

  const syncServerValue = (input) => {
    const serverValue = input.dataset.serverValue ?? ""
    setInputValue(input, serverValue)
  }

  const restoreFocus = (input, wasFocused, cursorPos) => {
    if (wasFocused) {
      focusElement(input)
      const serverValue = input.dataset.serverValue ?? ""
      const pos = cursorPos ?? serverValue.length
      setInputCursor(input, pos)
    }
  }

  return {
    mounted() {
      state.input = findInput(this.el)
    },

    beforeUpdate() {
      const input = findInput(this.el)
      const captured = captureState(input)
      state.input = captured.input
      state.wasFocused = captured.wasFocused
      state.cursorPos = captured.cursorPos
    },

    updated() {
      const input = findInput(this.el)
      if (input) {
        syncServerValue(input)
        restoreFocus(input, state.wasFocused, state.cursorPos)
      }
    },
  }
}

const MaintainFocus = createMaintainFocusHook()

// ============================================================================
// DropdownFocus Hook
// ============================================================================

const createDropdownFocusHook = () => {
  const state = {
    observer: null,
    wasOpen: false,
  }

  const checkAndFocus = (el) => {
    const dropdown = closestElement(el, ".dropdown")
    const isOpen = isDropdownOpen(dropdown)

    if (isOpen && !state.wasOpen) {
      focusElement(el)
    }
    state.wasOpen = isOpen
  }

  const createObserver = (el) =>
    new MutationObserver((mutations) => {
      const hasClassChange = mutations.some((m) => m.attributeName === "class")
      if (hasClassChange) {
        checkAndFocus(el)
      }
    })

  return {
    mounted() {
      const dropdown = closestElement(this.el, ".dropdown")
      if (!dropdown) return

      state.wasOpen = false
      checkAndFocus(this.el)

      state.observer = createObserver(this.el)
      state.observer.observe(dropdown, { attributes: true })
    },

    updated() {
      checkAndFocus(this.el)
    },

    destroyed() {
      state.observer?.disconnect()
      state.observer = null
    },
  }
}

const DropdownFocus = createDropdownFocusHook()

// ============================================================================
// Exports
// ============================================================================

export const hooks = {
  AutoOpenDropdown,
  DropdownTrigger,
  DropdownItem,
  MaintainFocus,
  DropdownFocus,
}

export {
  AutoOpenDropdown,
  DropdownTrigger,
  DropdownItem,
  MaintainFocus,
  DropdownFocus,
}

export default hooks
