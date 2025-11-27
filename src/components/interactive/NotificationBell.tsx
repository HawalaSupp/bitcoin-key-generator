import { Bell } from 'lucide-react'
import { useMemo } from 'react'
import { useNotifications } from '@context/NotificationContext'
import { cn } from '@utils/cn'

export function NotificationBell() {
  const { notifications, history, centerOpen, setCenterOpen } = useNotifications()
  const unread = useMemo(() => {
    const centerUnread = history.filter((item) => !item.read).length
    return centerUnread + notifications.length
  }, [history, notifications])

  return (
    <button
      className={cn(
        'relative rounded-full p-2 text-foreground transition hover:bg-background-secondary dark:text-dark-foreground dark:hover:bg-dark-background-secondary',
        centerOpen && 'bg-background-secondary dark:bg-dark-background-secondary'
      )}
      aria-label="Open notification center"
      onClick={() => setCenterOpen(!centerOpen)}
    >
      <Bell size={20} />
      {unread > 0 && (
        <span className="absolute -right-0.5 -top-0.5 inline-flex h-4 min-w-[1rem] items-center justify-center rounded-full bg-rose-500 px-1 text-[10px] font-semibold text-white">
          {unread > 9 ? '9+' : unread}
        </span>
      )}
    </button>
  )
}

