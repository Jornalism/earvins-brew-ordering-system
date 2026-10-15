/**
 * Supabase browser clients use the project URL and publishable key only.
 * Keep service-role and other secret keys out of NEXT_PUBLIC_ variables and
 * out of this application until a server-only backend use case requires them.
 */
export function getSupabasePublicEnv() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY

  if (!url || !publishableKey) {
    throw new Error(
      'Supabase is not configured. Add NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY to .env.local.'
    )
  }

  return { url, publishableKey }
}
