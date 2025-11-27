import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useReducer,
  useRef,
  useState,
  type ReactNode,
} from 'react'

type NotificationType = 'info' | 'success' | 'warning' | 'error'
type NotificationPosition = 'top-left' | 'top-right' | 'bottom-left' | 'bottom-right'

export interface NotificationAction {
  label: string
  onClick?: () => void
  variant?: 'primary' | 'ghost'
}

export interface NotificationItem {
  id: string
  title: string
  message: string
  type: NotificationType
  position: NotificationPosition
  createdAt: number
  read: boolean
  autoDismiss: boolean
  duration: number
  actions?: NotificationAction[]
}

export interface NotificationPreferences {
  marketing: boolean
  productUpdates: boolean
  securityAlerts: boolean
  system: boolean
  pushEnabled: boolean
  sound: boolean
}

interface NotificationState {
  active: NotificationItem[]
  history: NotificationItem[]
}

type NotificationActionType =
  | { type: 'SHOW'; payload: NotificationItem }
  | { type: 'DISMISS'; payload: { id: string; markRead?: boolean } }
  | { type: 'MARK_ALL_READ' }
  | { type: 'CLEAR_ACTIVE' }

interface NotificationContextValue {
  notifications: NotificationItem[]
  history: NotificationItem[]
  preferences: NotificationPreferences
  centerOpen: boolean
  showNotification: (notification: Partial<Omit<NotificationItem, 'id' | 'createdAt'>>) => void
  dismissNotification: (id: string, markRead?: boolean) => void
  clearNotifications: () => void
  markAllAsRead: () => void
  setCenterOpen: (open: boolean) => void
  updatePreferences: (patch: Partial<NotificationPreferences>) => void
  requestPushPermission: () => Promise<NotificationPermission>
}

const NotificationContext = createContext<NotificationContextValue | undefined>(undefined)

const defaultPreferences: NotificationPreferences = {
  marketing: false,
  productUpdates: true,
  securityAlerts: true,
  system: true,
  pushEnabled: false,
  sound: false,
}

const initialState: NotificationState = {
  active: [],
  history: [],
}

function notificationReducer(state: NotificationState, action: NotificationActionType): NotificationState {
  switch (action.type) {
    case 'SHOW': {
      return {
        ...state,
        active: [...state.active, action.payload],
      }
    }
    case 'DISMISS': {
      const notification = state.active.find((item) => item.id === action.payload.id)
      return {
        active: state.active.filter((item) => item.id !== action.payload.id),
        history: notification
          ? [
              {
                ...notification,
                read: action.payload.markRead ?? true,
              },
              ...state.history,
            ]
          : state.history,
      }
    }
    case 'MARK_ALL_READ': {
      return {
        ...state,
        history: state.history.map((item) => ({ ...item, read: true })),
      }
    }
    case 'CLEAR_ACTIVE': {
      return {
        active: [],
        history: [...state.active, ...state.history],
      }
    }
    default:
      return state
  }
}

function generateId() {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) {
    return crypto.randomUUID()
  }
  return Math.random().toString(36).slice(2)
}

export function NotificationProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(notificationReducer, initialState)
  const [centerOpen, setCenterOpen] = useState(false)
  const [preferences, setPreferences] = useState<NotificationPreferences>(() => {
    if (typeof window === 'undefined') return defaultPreferences
    try {
      const stored = localStorage.getItem('hawala:notification-preferences')
      return stored ? { ...defaultPreferences, ...JSON.parse(stored) } : defaultPreferences
    } catch {
      return defaultPreferences
    }
  })
  const timeoutsRef = useRef<Record<string, number>>({})

  useEffect(() => {
    localStorage.setItem('hawala:notification-preferences', JSON.stringify(preferences))
  }, [preferences])

  useEffect(() => {
    state.active.forEach((notification) => {
      if (!notification.autoDismiss || timeoutsRef.current[notification.id]) return
      const timeout = window.setTimeout(() => {
        dismissNotification(notification.id)
      }, notification.duration)
      timeoutsRef.current[notification.id] = timeout
    })

    return () => {
      Object.values(timeoutsRef.current).forEach((timeoutId) => {
        window.clearTimeout(timeoutId)
      })
      timeoutsRef.current = {}
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.active])

  const dismissNotification = useCallback((id: string, markRead = true) => {
    const timeoutId = timeoutsRef.current[id]
    if (timeoutId) {
      window.clearTimeout(timeoutId)
      delete timeoutsRef.current[id]
    }
    dispatch({ type: 'DISMISS', payload: { id, markRead } })
  }, [])

  const showNotification = useCallback(
    (notification: Partial<Omit<NotificationItem, 'id' | 'createdAt'>>) => {
      const payload: NotificationItem = {
        id: generateId(),
        title: notification.title ?? 'Notification',
        message: notification.message ?? '',
        type: notification.type ?? 'info',
        position: notification.position ?? 'top-right',
        autoDismiss: notification.autoDismiss ?? true,
        duration: notification.duration ?? 5000,
        createdAt: Date.now(),
        read: false,
        actions: notification.actions,
      }
      dispatch({ type: 'SHOW', payload })
    },
    []
  )

  const clearNotifications = useCallback(() => {
    dispatch({ type: 'CLEAR_ACTIVE' })
  }, [])

  const markAllAsRead = useCallback(() => {
    dispatch({ type: 'MARK_ALL_READ' })
  }, [])

  const updatePreferences = useCallback((patch: Partial<NotificationPreferences>) => {
    setPreferences((prev) => ({ ...prev, ...patch }))
  }, [])

  const requestPushPermission = useCallback(async () => {
    if (!('Notification' in window)) {
      return 'denied'
    }
    const permission = await Notification.requestPermission()
    if (permission === 'granted') {
      updatePreferences({ pushEnabled: true })
    }
    return permission
  }, [updatePreferences])

  const value = useMemo<NotificationContextValue>(
    () => ({
      notifications: state.active,
      history: state.history,
      preferences,
      centerOpen,
      showNotification,
      dismissNotification,
      clearNotifications,
      markAllAsRead,
      setCenterOpen,
      updatePreferences,
      requestPushPermission,
    }),
    [
      centerOpen,
      clearNotifications,
      dismissNotification,
      markAllAsRead,
      preferences,
      requestPushPermission,
      showNotification,
      state.active,
      state.history,
      updatePreferences,
    ]
  )

  return <NotificationContext.Provider value={value}>{children}</NotificationContext.Provider>
}

export function useNotifications() {
  const context = useContext(NotificationContext)
  if (!context) {
    throw new Error('useNotifications must be used within a NotificationProvider')
  }
  return context
}

