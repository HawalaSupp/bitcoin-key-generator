import { AnimatePresence, motion } from 'framer-motion'
import { CheckCircle2, Info, ShieldAlert, XCircle } from 'lucide-react'
import { useMemo } from 'react'
import { useNotifications, type NotificationItem } from '@context/NotificationContext'
import { Button } from '@components/ui/Button'

const positionClasses: Record<string, string> = {
  'top-right': 'top-4 right-4 items-end',
  'top-left': 'top-4 left-4 items-start',
  'bottom-right': 'bottom-4 right-4 items-end',
  'bottom-left': 'bottom-4 left-4 items-start',
}

const iconMap = {
  info: Info,
  success: CheckCircle2,
  warning: ShieldAlert,
  error: XCircle,
}

export function NotificationToasts() {
  const { notifications, dismissNotification } = useNotifications()

  const grouped = useMemo(() => {
    return notifications.reduce<Record<string, NotificationItem[]>>((acc, notification) => {
      if (!acc[notification.position]) {
        acc[notification.position] = []
      }
      acc[notification.position].push(notification)
      return acc
    }, {})
  }, [notifications])

  return (
    <div className="pointer-events-none fixed inset-0 z-[60]">
      {Object.entries(grouped).map(([position, items]) => (
        <div
          key={position}
          className={`absolute flex w-full max-w-sm flex-col gap-3 ${positionClasses[position] ?? positionClasses['top-right']}`}
        >
          <AnimatePresence initial={false}>
            {items.map((notification) => {
              const Icon = iconMap[notification.type] ?? Info
              return (
                <motion.div
                  key={notification.id}
                  initial={{ opacity: 0, y: 20, scale: 0.9 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={{ opacity: 0, y: 20, scale: 0.95 }}
                  transition={{ duration: 0.2 }}
                  className="pointer-events-auto overflow-hidden rounded-2xl border border-white/10 bg-background/90 p-4 shadow-2xl backdrop-blur-xl dark:bg-dark-background/80"
                >
                  <div className="flex items-start gap-3">
                    <div
                      className={`rounded-xl p-2 ${
                        notification.type === 'success'
                          ? 'bg-emerald-500/10 text-emerald-400'
                          : notification.type === 'warning'
                            ? 'bg-amber-500/10 text-amber-400'
                            : notification.type === 'error'
                              ? 'bg-rose-500/10 text-rose-400'
                              : 'bg-blue-500/10 text-blue-400'
                      }`}
                    >
                      <Icon size={20} />
                    </div>
                    <div className="flex-1">
                      <p className="text-sm font-semibold text-foreground dark:text-dark-foreground">
                        {notification.title}
                      </p>
                      <p className="text-sm text-foreground-secondary dark:text-dark-foreground-secondary">
                        {notification.message}
                      </p>

                      {notification.actions && notification.actions.length > 0 && (
                        <div className="mt-3 flex gap-2">
                          {notification.actions.map((action) => (
                            <Button
                              key={`${notification.id}-${action.label}`}
                              size="sm"
                              variant={action.variant === 'ghost' ? 'ghost' : 'secondary'}
                              onClick={() => {
                                action.onClick?.()
                                dismissNotification(notification.id)
                              }}
                            >
                              {action.label}
                            </Button>
                          ))}
                        </div>
                      )}
                    </div>
                    <button
                      aria-label="Dismiss notification"
                      className="text-foreground-secondary transition hover:text-foreground dark:text-dark-foreground-secondary dark:hover:text-dark-foreground"
                      onClick={() => dismissNotification(notification.id)}
                    >
                      ×
                    </button>
                  </div>
                </motion.div>
              )
            })}
          </AnimatePresence>
        </div>
      ))}
    </div>
  )
}

