// App Store Server Notifications V2. Apple signs the outer notification and
// the embedded transaction. No Supabase user token is expected here.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { Environment, SignedDataVerifier } from 'npm:@apple/app-store-server-library@3.1.0'
import { Buffer } from 'node:buffer'
import { appleRootDER } from '../apple-iap/apple_roots.ts'

const roots = appleRootDER.map((encoded) => Buffer.from(encoded, 'base64'))

function environmentOf(jws: string): Environment {
  const payload = jws.split('.')[1]
  if (!payload) throw new Error('Malformed notification')
  const claim = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'))
  const environment = claim.data?.environment
  if (environment === 'Production') return Environment.PRODUCTION
  if (environment === 'Sandbox') return Environment.SANDBOX
  throw new Error('Unknown App Store environment')
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return new Response('Use POST', { status: 405 })
  const body = await request.json().catch(() => null)
  const signed = typeof body?.signedPayload === 'string' ? body.signedPayload : ''
  if (!signed || signed.length > 60_000) return new Response('Bad notification', { status: 400 })
  try {
    const environment = environmentOf(signed)
    const verifier = new SignedDataVerifier(
      roots, false, environment, 'com.jewelindia.app',
      environment === Environment.PRODUCTION ? 6810498921 : undefined,
    )
    const notification = await verifier.verifyAndDecodeNotification(signed)
    if (notification.notificationType !== 'REFUND') return new Response('OK')
    const transactionJWS = notification.data?.signedTransactionInfo
    if (!transactionJWS) throw new Error('Refund is missing a signed transaction')
    const transaction = await verifier.verifyAndDecodeTransaction(transactionJWS)
    if (!transaction.transactionId || !transaction.revocationDate) {
      throw new Error('Refund transaction is incomplete')
    }

    const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data, error } = await admin.rpc('record_apple_credit_refund', {
      p_transaction_id: transaction.transactionId,
      p_notification: {
        notificationUUID: notification.notificationUUID,
        notificationType: notification.notificationType,
        signedDate: notification.signedDate,
      },
    })
    if (error || !data?.ok) {
      console.error('apple-iap-notifications refund pending', {
        transactionId: transaction.transactionId,
        error: error?.message ?? data?.error,
      })
      return new Response('Retry later', { status: 503 })
    }
    return new Response('OK')
  } catch (error) {
    console.error('apple-iap-notifications rejected', String(error))
    return new Response('Invalid notification', { status: 400 })
  }
})
