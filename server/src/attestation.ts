import { CBORError, decode, decodeItem, type CBORValue } from "./cbor";
import {
  children,
  DERError,
  firstChild,
  isCertificateAuthority,
  parseCertificate,
  readSingle,
  TAG,
  type Certificate,
} from "./der";

/**
 * Apple App Attest verification, following "Validating apps that connect to
 * your server" and the "Attestation Object Validation Guide" (Apple Developer
 * documentation, read on 2026-10-19). Pure functions: storage is in keys.ts.
 */

/**
 * Apple App Attestation Root CA, from
 * https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
 * (SHA-256 fingerprint 1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32).
 */
const APPLE_ROOT_CA =
  "MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYwJAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwKQXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNaFw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlvbiBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9ybmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdhNbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9auYen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYwCgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijVoyFraWVIyd/dganmrduC1bmTBGwD";

/** Extension of the credential certificate that holds the nonce. */
const NONCE_OID = "1.2.840.113635.100.8.2";

const SIGNATURE_HASHES: Record<string, string> = {
  "1.2.840.10045.4.3.2": "SHA-256",
  "1.2.840.10045.4.3.3": "SHA-384",
};
const CURVES: Record<string, { name: string; size: number }> = {
  "1.2.840.10045.3.1.7": { name: "P-256", size: 32 },
  "1.3.132.0.34": { name: "P-384", size: 48 },
};

export type AttestEnvironment = "development" | "production";

/**
 * `apple_validation_category_01` values an iOS build of this app can have, from
 * the table in "Validating apps that connect to your server": 2 TestFlight,
 * 3 development signing, 4 App Store. The others (0 invalid, 1 operating
 * system, 5 Enterprise or ad hoc, 6 Developer ID, 7-9 restricted, 10 unmatched
 * identity) are rejected.
 */
const APP_VALIDATION_CATEGORIES: readonly number[] = [2, 3, 4];

export class AttestationError extends Error {}

export interface AttestedKey {
  /** X9.62 uncompressed P-256 point of the attested key. */
  publicKey: Uint8Array;
  environment: AttestEnvironment;
  /**
   * Kept for Apple's fraud metric, which this server doesn't query yet. Not verified: Apple
   * asks to check its signature, App ID, creation time and public key before trusting it.
   */
  receipt: Uint8Array;
  /** `apple_validation_category_01`, when the device sends it. */
  validationCategory?: number;
  /** `apple_bundle_version_01`, when the device sends it. */
  bundleVersion?: string;
}

interface AuthenticatorData {
  rpIdHash: Uint8Array;
  counter: number;
  aaguid?: Uint8Array;
  credentialId?: Uint8Array;
  validationCategory?: number;
  bundleVersion?: string;
}

/**
 * Verifies the object `DCAppAttestService.attestKey` returned for `keyId` and
 * `clientDataHash`, which the app computes as the SHA-256 of the challenge.
 */
export async function verifyAttestation(input: {
  attestation: Uint8Array;
  keyId: Uint8Array;
  clientDataHash: Uint8Array;
  appId: string;
  now: number;
  root?: Uint8Array;
  validationCategories?: readonly number[];
  minBundleVersion?: string;
}): Promise<AttestedKey> {
  return guarded(async () => {
    const object = asMap(decode(input.attestation));
    if (object.get("fmt") !== "apple-appattest") throw new AttestationError("unexpected format");
    const statement = asMap(object.get("attStmt"));
    const x5c = statement.get("x5c");
    const receipt = statement.get("receipt");
    const authDataBytes = object.get("authData");
    if (!Array.isArray(x5c) || !(receipt instanceof Uint8Array) || !(authDataBytes instanceof Uint8Array)) {
      throw new AttestationError("malformed attestation");
    }

    // 1. The x5c chain (credential certificate, then intermediate) leads to Apple's root.
    const [leafBytes, intermediateBytes] = x5c;
    if (!(leafBytes instanceof Uint8Array) || !(intermediateBytes instanceof Uint8Array)) {
      throw new AttestationError("missing certificates");
    }
    const leaf = parseCertificate(leafBytes);
    const intermediate = parseCertificate(intermediateBytes);
    const root = parseCertificate(input.root ?? fromBase64(APPLE_ROOT_CA));
    if (!isCertificateAuthority(intermediate)) throw new AttestationError("intermediate is not a CA");
    await verifyIssued(leaf, intermediate, input.now);
    await verifyIssued(intermediate, root, input.now);

    // 2-4. nonce = SHA-256(authData || clientDataHash) is in the credential certificate.
    const nonce = await sha256(concat(authDataBytes, input.clientDataHash));
    const extension = leaf.extensions.get(NONCE_OID);
    if (!extension) throw new AttestationError("missing nonce extension");
    const octets = firstChild(firstChild(readSingle(extension, TAG.sequence)));
    if (octets?.tag !== TAG.octetString || !equal(octets.contents, nonce)) throw new AttestationError("nonce mismatch");

    // 5. The key identifier is the SHA-256 of the certificate's public key.
    if (!equal(await sha256(leaf.publicKey), input.keyId)) throw new AttestationError("key identifier mismatch");

    const authData = parseAuthenticatorData(authDataBytes, true);
    // 6. RP ID is the SHA-256 of the App ID.
    if (!equal(authData.rpIdHash, await sha256(new TextEncoder().encode(input.appId)))) {
      throw new AttestationError("App ID mismatch");
    }
    // 7. A new key has never signed an assertion.
    if (authData.counter !== 0) throw new AttestationError("counter is not zero");
    // 8. aaguid tells the App Attest environment.
    const environment = attestEnvironment(authData.aaguid!);
    // 9. credentialId is the key identifier too.
    if (!equal(authData.credentialId!, input.keyId)) throw new AttestationError("credential mismatch");

    // 10. The build is one of this app's. 11. The build is still supported.
    checkValidationCategory(authData, input.validationCategories);
    checkBundleVersion(authData, input.minBundleVersion);
    return {
      publicKey: leaf.publicKey,
      environment,
      receipt,
      validationCategory: authData.validationCategory,
      bundleVersion: authData.bundleVersion,
    };
  });
}

/**
 * Verifies an object `DCAppAttestService.generateAssertion` returned for
 * `clientData`, and returns its counter, which the caller stores.
 */
export async function verifyAssertion(input: {
  assertion: Uint8Array;
  clientData: Uint8Array;
  publicKey: Uint8Array;
  appId: string;
  previousCounter: number;
  validationCategories?: readonly number[];
  minBundleVersion?: string;
}): Promise<number> {
  return guarded(async () => {
    const object = asMap(decode(input.assertion));
    const signature = object.get("signature");
    const authDataBytes = object.get("authenticatorData");
    if (!(signature instanceof Uint8Array) || !(authDataBytes instanceof Uint8Array)) {
      throw new AttestationError("malformed assertion");
    }

    // 1-3. The signature covers nonce = SHA-256(authenticatorData || SHA-256(clientData)).
    const nonce = await sha256(concat(authDataBytes, await sha256(input.clientData)));
    const key = await crypto.subtle.importKey(
      "raw",
      copy(input.publicKey),
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      copy(rawSignature(signature, 32)),
      copy(nonce),
    );
    if (!valid) throw new AttestationError("invalid signature");

    const authData = parseAuthenticatorData(authDataBytes, false);
    // 4. RP ID is the SHA-256 of the App ID.
    if (!equal(authData.rpIdHash, await sha256(new TextEncoder().encode(input.appId)))) {
      throw new AttestationError("App ID mismatch");
    }
    // 5. The counter only grows, which rejects replayed assertions.
    if (authData.counter <= input.previousCounter) throw new AttestationError("counter did not increase");
    // 6. The caller checks the challenge embedded in clientData.
    // 7-8. Same checks as for the attestation.
    checkValidationCategory(authData, input.validationCategories);
    checkBundleVersion(authData, input.minBundleVersion);
    return authData.counter;
  });
}

/**
 * WebAuthn authenticator data: rpIdHash (32), flags (1), counter (4), then for
 * an attestation aaguid (16), credentialId length (2), credentialId and the
 * COSE public key. Apple's extensions map follows; Apple's own sample sends it
 * without setting the ED flag, so it is read whenever bytes remain.
 */
function parseAuthenticatorData(data: Uint8Array, attested: boolean): AuthenticatorData {
  if (data.length < 37) throw new AttestationError("authenticator data too short");
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  const result: AuthenticatorData = { rpIdHash: data.subarray(0, 32), counter: view.getUint32(33) };
  let offset = 37;
  if (attested) {
    if (data.length < 55) throw new AttestationError("authenticator data too short");
    result.aaguid = data.subarray(37, 53);
    const length = view.getUint16(53);
    result.credentialId = data.subarray(55, 55 + length);
    if (result.credentialId.length !== length) throw new AttestationError("authenticator data too short");
    offset = decodeItem(data, 55 + length).end;
  }
  if (offset < data.length) {
    const { value, end } = decodeItem(data, offset);
    if (end !== data.length) throw new AttestationError("trailing authenticator data");
    const extensions = asMap(value);
    const category = extensions.get("apple_validation_category_01");
    if (category !== undefined) {
      if (!(category instanceof Uint8Array) || category.length !== 4)
        throw new AttestationError("invalid validation category");
      // Apple's sample encodes category 1 as 01 00 00 00: little-endian.
      result.validationCategory = new DataView(category.buffer, category.byteOffset, 4).getUint32(0, true);
    }
    const version = extensions.get("apple_bundle_version_01");
    if (version !== undefined) {
      if (typeof version !== "string") throw new AttestationError("invalid bundle version");
      result.bundleVersion = version;
    }
  }
  return result;
}

function checkValidationCategory(authData: AuthenticatorData, allowed = APP_VALIDATION_CATEGORIES): void {
  // Apple asks to verify it, so an object without it can't be trusted.
  if (authData.validationCategory === undefined) throw new AttestationError("missing validation category");
  if (!allowed.includes(authData.validationCategory)) {
    throw new AttestationError(`validation category ${authData.validationCategory} not allowed`);
  }
}

/**
 * Rejects builds older than `minimum`, so that raising it after a fix shuts out
 * the builds before it. Both are CFBundleVersion strings: up to three
 * period-separated integers, compared numerically.
 */
function checkBundleVersion(authData: AuthenticatorData, minimum: string | undefined): void {
  if (authData.bundleVersion === undefined) throw new AttestationError("missing bundle version");
  if (minimum === undefined) return;
  const version = parseBundleVersion(authData.bundleVersion);
  const floor = parseBundleVersion(minimum);
  if (!version || !floor) throw new AttestationError(`invalid bundle version ${authData.bundleVersion}`);
  for (let i = 0; i < 3; i++) {
    const difference = (version[i] ?? 0) - (floor[i] ?? 0);
    if (difference > 0) return;
    if (difference < 0) throw new AttestationError(`bundle version ${authData.bundleVersion} no longer supported`);
  }
}

function parseBundleVersion(text: string): number[] | undefined {
  if (!/^\d{1,9}(\.\d{1,9}){0,2}$/.test(text)) return undefined;
  return text.split(".").map(Number);
}

function attestEnvironment(aaguid: Uint8Array): AttestEnvironment {
  const text = new TextDecoder().decode(aaguid);
  if (text === "appattest\0\0\0\0\0\0\0") return "production";
  // "appattestdevelop" per the validation article and guide; the article on
  // testing names "appattestsandbox" for the same sandbox environment.
  if (text === "appattestdevelop" || text === "appattestsandbox") return "development";
  throw new AttestationError("unknown aaguid");
}

async function verifyIssued(certificate: Certificate, issuer: Certificate, now: number): Promise<void> {
  for (const item of [certificate, issuer]) {
    if (now < item.notBefore || now > item.notAfter)
      throw new AttestationError("certificate outside its validity period");
  }
  if (!equal(certificate.issuer, issuer.subject)) throw new AttestationError("certificate chain mismatch");
  const hash = SIGNATURE_HASHES[certificate.signatureAlgorithm];
  const curve = CURVES[issuer.curve];
  if (!hash || !curve) throw new AttestationError("unsupported certificate algorithm");
  const key = await crypto.subtle.importKey(
    "spki",
    copy(issuer.spki),
    { name: "ECDSA", namedCurve: curve.name },
    false,
    ["verify"],
  );
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash },
    key,
    copy(rawSignature(certificate.signature, curve.size)),
    copy(certificate.tbs),
  );
  if (!valid) throw new AttestationError("invalid certificate signature");
}

/** DER `SEQUENCE { r INTEGER, s INTEGER }` to the r || s form WebCrypto expects. */
export function rawSignature(der: Uint8Array, size: number): Uint8Array {
  const parts = children(readSingle(der, TAG.sequence));
  if (parts.length !== 2) throw new AttestationError("invalid signature encoding");
  const result = new Uint8Array(size * 2);
  parts.forEach((part, index) => {
    if (part.tag !== TAG.integer) throw new AttestationError("invalid signature encoding");
    let value = part.contents;
    while (value.length > 1 && value[0] === 0) value = value.subarray(1);
    if (value.length > size) throw new AttestationError("invalid signature encoding");
    result.set(value, (index + 1) * size - value.length);
  });
  return result;
}

/**
 * Turns every failure into a verification failure: the input is untrusted, and
 * WebCrypto also throws on malformed keys or signatures.
 */
async function guarded<T>(body: () => Promise<T>): Promise<T> {
  try {
    return await body();
  } catch (error) {
    if (error instanceof AttestationError) throw error;
    if (error instanceof DERError || error instanceof CBORError) throw new AttestationError(error.message);
    throw new AttestationError(`malformed input: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function asMap(value: CBORValue | undefined): Map<CBORValue, CBORValue> {
  if (!(value instanceof Map)) throw new AttestationError("expected a CBOR map");
  return value;
}

export async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", copy(data)));
}

export function fromBase64(text: string): Uint8Array {
  return Uint8Array.from(atob(text), (character) => character.charCodeAt(0));
}

export function toBase64(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data));
}

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const result = new Uint8Array(a.length + b.length);
  result.set(a);
  result.set(b, a.length);
  return result;
}

function equal(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((byte, index) => byte === b[index]);
}

/** WebCrypto wants buffers backed by a plain ArrayBuffer. */
function copy(data: Uint8Array): Uint8Array<ArrayBuffer> {
  return new Uint8Array(data);
}
