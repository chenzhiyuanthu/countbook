/**
 * The sync server this build points at by default, so signing in is just an
 * email and a password with nothing to paste. It is the box the user runs the
 * server on; overridable in the UI for anyone self-hosting elsewhere.
 *
 * sslip.io resolves the dotted-IP hostname straight to the server's address, so
 * a valid Let's Encrypt certificate is issued with no DNS record to create. If
 * a nicer name (count.czylsy911.art) is later pointed at the same box, either
 * works — the certificate covers both.
 */
export const DEFAULT_SERVER_URL = 'https://43-162-121-196.sslip.io'
