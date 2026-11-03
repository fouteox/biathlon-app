/**
 * Compact JWS (RFC 7515) signing with WebCrypto, for the tokens the push services take: APNs
 * provider tokens (ES256) and Google service account assertions (RS256).
 */

/** The JWS algorithms of those tokens: WebCrypto signs ES256 as raw r||s, which is the JWS format. */
const ALGORITHMS = {
  ES256: {
    importParams: { name: "ECDSA", namedCurve: "P-256" },
    signParams: { name: "ECDSA", hash: "SHA-256" },
  },
  RS256: {
    importParams: { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    signParams: { name: "RSASSA-PKCS1-v1_5" },
  },
} as const;

export type JWSAlgorithm = keyof typeof ALGORITHMS;

/** Signs `claims` with the PKCS #8 PEM private key `pem`, `header` holding the fields besides `alg`. */
export async function signJWT(
  algorithm: JWSAlgorithm,
  pem: string,
  header: Record<string, string>,
  claims: Record<string, unknown>,
): Promise<string> {
  const { importParams, signParams } = ALGORITHMS[algorithm];
  const signingInput = `${base64url(JSON.stringify({ alg: algorithm, ...header }))}.${base64url(JSON.stringify(claims))}`;
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(pem), importParams, false, ["sign"]);
  const signature = await crypto.subtle.sign(signParams, key, new TextEncoder().encode(signingInput));
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

/** A PKCS #8 PEM key, its line breaks escaped (`\n`) as a secret set on one line has them. */
function pemToDer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/\\n/g, "\n")
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0)).buffer;
}

export function base64url(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
