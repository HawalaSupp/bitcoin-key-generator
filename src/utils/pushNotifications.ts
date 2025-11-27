export function isPushSupported() {
  return typeof window !== 'undefined' && 'serviceWorker' in navigator && 'PushManager' in window
}

export async function registerPushServiceWorker() {
  if (!isPushSupported()) return null
  try {
    const registration = await navigator.serviceWorker.register('/sw.js')
    return registration
  } catch (error) {
    console.error('Push registration failed', error)
    return null
  }
}

export async function subscribeUserToPush(applicationServerKey?: Uint8Array) {
  if (!isPushSupported()) return null
  try {
    const registration = await registerPushServiceWorker()
    if (!registration) return null

    let subscription = await registration.pushManager.getSubscription()
    if (!subscription) {
      subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey,
      })
    }
    return subscription
  } catch (error) {
    console.error('Push subscription failed', error)
    return null
  }
}

export async function unsubscribeFromPush() {
  if (!isPushSupported()) return false
  try {
    const registration = await navigator.serviceWorker.ready
    const subscription = await registration.pushManager.getSubscription()
    if (subscription) {
      await subscription.unsubscribe()
    }
    return true
  } catch (error) {
    console.error('Push unsubscribe failed', error)
    return false
  }
}

