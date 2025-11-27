import { AnimatePresence, motion } from 'framer-motion'
import { Bell, CheckCircle2, Settings2, Shield, X } from 'lucide-react'
import { Fragment } from 'react'
import { Button } from '@components/ui/Button'
import { useNotifications } from '@context/NotificationContext'

const preferenceList = [
  { key: 'system', label: 'System Alerts', description: 'Critical wallet and security notices.' },
  { key: 'securityAlerts', label: 'Security Updates', description: 'Proactive security advisories.' },
  { key: 'productUpdates', label: 'Product Updates', description: 'New features and releases.' },
  { key: 'marketing', label: 'Insights & Marketing', description: 'Occasional news and inspiration.' },
  { key: 'sound', label: 'Sound Effects', description: 'Play a subtle chime for new notifications.' },
] as const

export function NotificationCenter() {
  const {
    centerOpen,
    setCenterOpen,
    history,
    preferences,
    markAllAsRead,
    updatePreferences,
    requestPushPermission,
  } = useNotifications()

  const unreadCount = history.filter((item) => !item.read).length

  return (
    <AnimatePresence>
      {centerOpen && (
        <Fragment>
          <motion.div
            className="fixed inset-0 z-[70] bg-black/40 backdrop-blur-sm"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={() => setCenterOpen(false)}
          />
          <motion.aside
            className="fixed right-0 top-0 z-[80] h-full w-full max-w-md bg-background/95 p-6 text-foreground shadow-2xl backdrop-blur-3xl dark:bg-dark-background/90 dark:text-dark-foreground"
            initial={{ x: '100%' }}
            animate={{ x: 0 }}
            exit={{ x: '100%' }}
            transition={{ type: 'spring', damping: 25, stiffness: 300 }}
          >
            <div className="mb-6 flex items-center justify-between">
              <div>
                <h2 className="text-xl font-semibold">Notification Center</h2>
                <p className="text-sm text-foreground-secondary dark:text-dark-foreground-secondary">
                  Stay updated across wallets, devices, and alerts.
                </p>
              </div>
              <button
                aria-label="Close notification center"
                className="rounded-full p-2 text-foreground-secondary hover:bg-background-secondary dark:text-dark-foreground-secondary dark:hover:bg-dark-background-secondary"
                onClick={() => setCenterOpen(false)}
              >
                <X />
              </button>
            </div>

            <div className="mb-6 space-y-3 rounded-2xl border border-white/10 bg-background-secondary/60 p-4 dark:bg-dark-background-secondary/40">
              <div className="flex items-center gap-3">
                <Bell className="text-blue-400" />
                <div className="flex-1">
                  <p className="text-sm font-medium">Notifications enabled</p>
                  <p className="text-xs text-foreground-secondary dark:text-dark-foreground-secondary">
                    {unreadCount > 0 ? `${unreadCount} unread` : 'All caught up'}
                  </p>
                </div>
                <Button variant="ghost" size="sm" onClick={markAllAsRead} disabled={unreadCount === 0}>
                  Mark read
                </Button>
              </div>
              <div className="flex items-center gap-3">
                <Shield className="text-emerald-400" />
                <div className="flex-1">
                  <p className="text-sm font-medium">Push protection</p>
                  <p className="text-xs text-foreground-secondary dark:text-dark-foreground-secondary">
                    {preferences.pushEnabled ? 'Push notifications active' : 'Enable push for instant alerts'}
                  </p>
                </div>
                <Button
                  variant="secondary"
                  size="sm"
                  onClick={async () => {
                    const permission = await requestPushPermission()
                    if (permission !== 'granted') {
                      updatePreferences({ pushEnabled: false })
                    }
                  }}
                >
                  {preferences.pushEnabled ? 'Enabled' : 'Enable'}
                </Button>
              </div>
            </div>

            <div className="space-y-4 overflow-y-auto pr-2">
              <section className="space-y-3 rounded-2xl border border-white/10 bg-background-secondary/50 p-4 dark:bg-dark-background-secondary/30">
                <div className="mb-3 flex items-center gap-2">
                  <Settings2 className="text-purple-400" />
                  <div>
                    <p className="text-sm font-semibold">Preferences</p>
                    <p className="text-xs text-foreground-secondary dark:text-dark-foreground-secondary">
                      Tailor alerts to your workflow.
                    </p>
                  </div>
                </div>
                <div className="space-y-3">
                  {preferenceList.map((pref) => (
                    <button
                      key={pref.key}
                      className={`w-full rounded-xl border border-white/5 p-3 text-left transition ${
                        preferences[pref.key]
                          ? 'bg-emerald-500/10 text-emerald-100'
                          : 'bg-background dark:bg-dark-background text-foreground-secondary dark:text-dark-foreground-secondary'
                      }`}
                      onClick={() => updatePreferences({ [pref.key]: !preferences[pref.key] })}
                    >
                      <div className="flex items-center justify-between">
                        <p className="text-sm font-medium">{pref.label}</p>
                        {preferences[pref.key] && <CheckCircle2 className="text-emerald-400" size={18} />}
                      </div>
                      <p className="text-xs opacity-80">{pref.description}</p>
                    </button>
                  ))}
                </div>
              </section>

              <section className="space-y-3 rounded-2xl border border-white/10 bg-background-secondary/50 p-4 dark:bg-dark-background-secondary/30">
                <div>
                  <p className="text-sm font-semibold">Activity</p>
                  <p className="text-xs text-foreground-secondary dark:text-dark-foreground-secondary">
                    Latest notifications across devices.
                  </p>
                </div>

                {history.length === 0 ? (
                  <div className="rounded-xl border border-dashed border-white/10 p-6 text-center text-sm text-foreground-secondary dark:text-dark-foreground-secondary">
                    Nothing yet. Actions you perform will show up here.
                  </div>
                ) : (
                  <div className="space-y-3">
                    {history.slice(0, 10).map((notification) => (
                      <div
                        key={notification.id}
                        className="rounded-xl border border-white/5 bg-background/60 p-3 dark:bg-dark-background/50"
                      >
                        <div className="flex items-center justify-between">
                          <div>
                            <p className="text-sm font-semibold">{notification.title}</p>
                            <p className="text-xs text-foreground-secondary dark:text-dark-foreground-secondary">
                              {notification.message}
                            </p>
                          </div>
                          <span className="text-xs text-foreground-muted dark:text-dark-foreground-muted">
                            {new Date(notification.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                          </span>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </section>
            </div>
          </motion.aside>
        </Fragment>
      )}
    </AnimatePresence>
  )
}

