// @peculiar/x509 needs the Reflect metadata API, which must load before it.
import "reflect-metadata";
import { ContentInfo, id_signedData, SignedData } from "@peculiar/asn1-cms";
import { AsnConvert, AsnParser } from "@peculiar/asn1-schema";
import { SubjectPublicKeyInfo } from "@peculiar/asn1-x509";
import { AsnEcSignatureFormatter, BasicConstraintsExtension, X509Certificate } from "@peculiar/x509";
import { Constructed, fromBER, Integer, OctetString, Sequence, Set, verifySchema } from "asn1js";
import { decode, decodeFirst, type DecodeOptions } from "cborg";

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

/**
 * Apple Root CA - G3, which signs App Attest receipts, from
 * https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
 * (SHA-256 fingerprint 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79).
 */
const APPLE_ROOT_CA_G3 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

/** Extension of the credential certificate that holds the nonce: `SEQUENCE { [1] EXPLICIT OCTET STRING }`. */
const NONCE_OID = "1.2.840.113635.100.8.2";
const NONCE_SCHEMA = new Sequence({
  value: [new Constructed({ idBlock: { tagClass: 3, tagNumber: 1 }, value: [new OctetString({ name: "nonce" })] })],
});

/**
 * Untrusted input: definite lengths, no duplicate keys, no tags (cborg's
 * default), and maps as `Map` since COSE keys have integer keys.
 */
const CBOR_OPTIONS: DecodeOptions = {
  useMaps: true,
  rejectDuplicateMapKeys: true,
  allowIndefinite: false,
  allowUndefined: false,
  allowBigInt: false,
};

/** The algorithm of App Attest keys, which sign the assertions. */
const KEY_ALGORITHM = { name: "ECDSA", namedCurve: "P-256" } as const;

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
  /** Verified with the attestation, and kept for Apple's fraud metric, which this server doesn't query yet. */
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
    const object = asMap(decode(input.attestation, CBOR_OPTIONS));
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
    const leaf = new X509Certificate(copy(leafBytes));
    const intermediate = new X509Certificate(copy(intermediateBytes));
    const root = new X509Certificate(input.root ? copy(input.root) : APPLE_ROOT_CA);
    if (!intermediate.getExtension(BasicConstraintsExtension)?.ca) {
      throw new AttestationError("intermediate is not a CA");
    }
    await verifyIssued(leaf, intermediate, input.now);
    await verifyIssued(intermediate, root, input.now);

    // 2-4. nonce = SHA-256(authData || clientDataHash) is in the credential certificate.
    const nonce = await sha256(concat(authDataBytes, input.clientDataHash));
    const extension = leaf.getExtension(NONCE_OID);
    if (!extension) throw new AttestationError("missing nonce extension");
    const parsed = verifySchema(extension.value, NONCE_SCHEMA);
    if (!parsed.verified || !equal(parsed.result.nonce.valueBlock.valueHexView, nonce)) {
      throw new AttestationError("nonce mismatch");
    }

    // 5. The key identifier is the SHA-256 of the certificate's public key.
    const publicKey = new Uint8Array(AsnConvert.parse(leaf.publicKey.rawData, SubjectPublicKeyInfo).subjectPublicKey);
    if (!equal(await sha256(publicKey), input.keyId)) throw new AttestationError("key identifier mismatch");

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
    // 12. Apple: verify the receipt that comes with the attestation before storing it.
    await verifyReceipt({ receipt, appId: input.appId, publicKey, now: input.now });
    return {
      publicKey,
      environment,
      receipt,
      validationCategory: authData.validationCategory,
      bundleVersion: authData.bundleVersion,
    };
  });
}

/** Receipt payload fields Apple asks to check. */
const RECEIPT_FIELD = { appId: 2, attestedPublicKey: 3, creationTime: 12 } as const;
/** Apple: a receipt created more than five minutes ago may be replayed. */
const RECEIPT_MAX_AGE_MS = 5 * 60 * 1000;
/**
 * Apple Root CA - G3 also issues certificates for keys developers hold (Apple Pay
 * Payment Processing, through WWDR G2), so the chain is pinned to the names Apple
 * gives the receipt signer and its CA. Only Apple can issue a CA under the root.
 */
const RECEIPT_SIGNER = "CN=Application Attestation Fraud Receipt Signing, O=Apple Inc., C=US";
const RECEIPT_CA = "CN=Apple Application Integration CA 5 - G1, OU=Apple Certification Authority, O=Apple Inc., C=US";
const SHA256_OID = "2.16.840.1.101.3.4.2.1";
const ECDSA_WITH_SHA256_OID = "1.2.840.10045.4.3.2";

/**
 * Verifies the receipt that came with the attestation of `publicKey`, following
 * "Verify the receipt" in "Assessing fraud risk" (Apple Developer documentation,
 * read on 2026-10-25). The receipt is a BER-encoded PKCS #7 container, signed
 * without signed attributes, whose payload is a set of
 * `SEQUENCE { type INTEGER, version INTEGER, value OCTET STRING }` fields.
 */
export async function verifyReceipt(input: {
  receipt: Uint8Array;
  appId: string;
  publicKey: Uint8Array;
  now: number;
  root?: Uint8Array;
}): Promise<void> {
  return guarded(async () => {
    const info = AsnParser.parse(copy(input.receipt), ContentInfo);
    if (info.contentType !== id_signedData) throw new AttestationError("receipt is not signed data");
    const signedData = AsnParser.parse(info.content, SignedData);
    const [signer, ...others] = signedData.signerInfos;
    if (!signer || others.length > 0) throw new AttestationError("receipt must have one signer");
    if (signer.signedAttrs) throw new AttestationError("unexpected receipt signed attributes");
    if (
      signer.digestAlgorithm.algorithm !== SHA256_OID ||
      signer.signatureAlgorithm.algorithm !== ECDSA_WITH_SHA256_OID
    ) {
      throw new AttestationError("unsupported receipt algorithm");
    }

    // 1. The signature covers the payload. The signer names its certificate by issuer and serial number.
    const payload = receiptPayload(signedData);
    const certificates = (signedData.certificates ?? []).flatMap((choice) =>
      choice.certificate ? [new X509Certificate(AsnConvert.serialize(choice.certificate))] : [],
    );
    const id = signer.sid.issuerAndSerialNumber;
    const signing =
      id &&
      certificates.find(
        (certificate) =>
          certificate.serialNumber === hex(new Uint8Array(id.serialNumber)) &&
          equal(
            new Uint8Array(certificate.issuerName.toArrayBuffer()),
            new Uint8Array(AsnConvert.serialize(id.issuer)),
          ),
      );
    if (!signing) throw new AttestationError("missing receipt signing certificate");
    const raw = new AsnEcSignatureFormatter().toWebSignature(KEY_ALGORITHM, signer.signature.buffer);
    if (!raw) throw new AttestationError("invalid receipt signature encoding");
    const key = await signing.publicKey.export(KEY_ALGORITHM, ["verify"]);
    if (!(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, raw, copy(payload)))) {
      throw new AttestationError("invalid receipt signature");
    }

    // 2. The signing certificate is Apple's receipt signer, and chains up to Apple Root CA - G3.
    if (signing.subject !== RECEIPT_SIGNER || signing.issuer !== RECEIPT_CA) {
      throw new AttestationError("receipt not signed by Apple's receipt signer");
    }
    const intermediate = certificates.find((certificate) => certificate.subject === RECEIPT_CA);
    if (!intermediate) throw new AttestationError("receipt certificate chain mismatch");
    if (!intermediate.getExtension(BasicConstraintsExtension)?.ca) {
      throw new AttestationError("receipt intermediate is not a CA");
    }
    await verifyIssued(signing, intermediate, input.now);
    await verifyIssued(intermediate, new X509Certificate(input.root ? copy(input.root) : APPLE_ROOT_CA_G3), input.now);

    // 3. The payload's fields. 4. The App ID is this app's.
    const fields = receiptFields(payload);
    if (new TextDecoder().decode(receiptField(fields, RECEIPT_FIELD.appId)) !== input.appId) {
      throw new AttestationError("receipt App ID mismatch");
    }
    // 5. Created within five minutes of now.
    const created = Date.parse(new TextDecoder().decode(receiptField(fields, RECEIPT_FIELD.creationTime)));
    if (!(Math.abs(input.now - created) <= RECEIPT_MAX_AGE_MS)) throw new AttestationError("receipt too old");
    // 6. The attested public key, in the credential certificate there, is the one just attested.
    const attested = new X509Certificate(receiptField(fields, RECEIPT_FIELD.attestedPublicKey));
    const attestedKey = AsnConvert.parse(attested.publicKey.rawData, SubjectPublicKeyInfo).subjectPublicKey;
    if (!equal(new Uint8Array(attestedKey), input.publicKey)) throw new AttestationError("receipt public key mismatch");
  });
}

/** The encapsulated content, which Apple sends as a constructed (chunked) OCTET STRING. */
function receiptPayload(signedData: SignedData): Uint8Array {
  const content = signedData.encapContentInfo.eContent?.any;
  if (!content) throw new AttestationError("missing receipt payload");
  const { offset, result } = fromBER(content);
  if (offset !== content.byteLength || !(result instanceof OctetString)) {
    throw new AttestationError("malformed receipt payload");
  }
  return new Uint8Array(result.getValue());
}

function receiptFields(payload: Uint8Array): Map<number, Uint8Array> {
  const { offset, result } = fromBER(copy(payload));
  if (offset !== payload.length || !(result instanceof Set)) throw new AttestationError("malformed receipt payload");
  const fields = new Map<number, Uint8Array>();
  for (const item of result.valueBlock.value) {
    const [type, , value] = item instanceof Sequence ? item.valueBlock.value : [];
    if (!(type instanceof Integer) || !(value instanceof OctetString)) {
      throw new AttestationError("malformed receipt field");
    }
    fields.set(type.valueBlock.valueDec, new Uint8Array(value.getValue()));
  }
  return fields;
}

function receiptField(fields: Map<number, Uint8Array>, type: number): Uint8Array {
  const value = fields.get(type);
  if (!value) throw new AttestationError(`missing receipt field ${type}`);
  return value;
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
    const object = asMap(decode(input.assertion, CBOR_OPTIONS));
    const signature = object.get("signature");
    const authDataBytes = object.get("authenticatorData");
    if (!(signature instanceof Uint8Array) || !(authDataBytes instanceof Uint8Array)) {
      throw new AttestationError("malformed assertion");
    }

    // 1-3. The signature covers nonce = SHA-256(authenticatorData || SHA-256(clientData)).
    const nonce = await sha256(concat(authDataBytes, await sha256(input.clientData)));
    const key = await crypto.subtle.importKey("raw", copy(input.publicKey), KEY_ALGORITHM, false, ["verify"]);
    // App Attest signatures are DER; WebCrypto wants r || s.
    const raw = new AsnEcSignatureFormatter().toWebSignature(KEY_ALGORITHM, copy(signature));
    if (!raw) throw new AttestationError("invalid signature encoding");
    const valid = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, raw, copy(nonce));
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
    // Skips the COSE public key, the same key as the certificate's.
    offset = data.length - decodeFirst(data.subarray(55 + length), CBOR_OPTIONS)[1].length;
  }
  if (offset < data.length) {
    const extensions = asMap(decode(data.subarray(offset), CBOR_OPTIONS));
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

async function verifyIssued(certificate: X509Certificate, issuer: X509Certificate, now: number): Promise<void> {
  for (const item of [certificate, issuer]) {
    if (now < item.notBefore.getTime() || now > item.notAfter.getTime())
      throw new AttestationError("certificate outside its validity period");
  }
  if (certificate.issuer !== issuer.subject) throw new AttestationError("certificate chain mismatch");
  if (!(await certificate.verify({ publicKey: issuer, signatureOnly: true }))) {
    throw new AttestationError("invalid certificate signature");
  }
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
    throw new AttestationError(`malformed input: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function asMap(value: unknown): Map<unknown, unknown> {
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

function hex(data: Uint8Array): string {
  return Array.from(data, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function equal(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((byte, index) => byte === b[index]);
}

/** WebCrypto wants buffers backed by a plain ArrayBuffer. */
function copy(data: Uint8Array): Uint8Array<ArrayBuffer> {
  return new Uint8Array(data);
}
