import { createBrowserClient } from '@supabase/ssr'

import { getSupabasePublicEnv } from './env'

/** Use only from Client Components or other browser-only code. */
export function createClient() {
  const { url, publishableKey } = getSupabasePublicEnv()

  return createBrowserClient(url, publishableKey)
}
