import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'
import 'server-only'

import { getSupabasePublicEnv } from './env'

/** Use only from Server Components, Server Actions, or Route Handlers. */
export async function createClient() {
  const cookieStore = await cookies()
  const { url, publishableKey } = getSupabasePublicEnv()

  return createServerClient(url, publishableKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll()
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) => {
            cookieStore.set(name, value, options)
          })
        } catch {
          // Server Components can read request cookies but cannot write them.
          // A future auth phase will add a Next.js proxy to refresh sessions.
        }
      },
    },
  })
}
