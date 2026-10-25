import "reflect-metadata";
import { X509Certificate } from "@peculiar/x509";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "cborg";
import { fromBase64, verifyAttestation, verifyReceipt } from "../src/attestation";
import forged from "./fixtures/forged-receipt.json";
import sample from "./fixtures/apple-attestation-sample.json";

// The receipt in Apple's sample was created at 2026-04-21T18:13:12.153Z, for the key it attests.
const created = Date.parse("2026-04-21T18:13:12.153Z");
const attStmt = (decode(fromBase64(sample.attestation), { useMaps: true }) as Map<string, Map<string, unknown>>).get(
  "attStmt",
)!;
const receipt = attStmt.get("receipt") as Uint8Array;
const [leaf, intermediate] = attStmt.get("x5c") as Uint8Array[];
const publicKey = await rawPublicKey(leaf!);
const input = { receipt, appId: sample.appId, publicKey, now: created + 60_000 };

/** The X9.62 point of a certificate's P-256 key, as verifyAttestation returns it. */
async function rawPublicKey(certificate: Uint8Array): Promise<Uint8Array> {
  const spki = new X509Certificate(certificate).publicKey.rawData;
  const key = await crypto.subtle.importKey("spki", spki, { name: "ECDSA", namedCurve: "P-256" }, true, ["verify"]);
  return new Uint8Array((await crypto.subtle.exportKey("raw", key)) as ArrayBuffer);
}

describe("receipt", () => {
  it("verifies the receipt of Apple's sample attestation", async () => {
    await expect(verifyReceipt(input)).resolves.toBeUndefined();
  });

  it("rejects a receipt created more than five minutes from now", async () => {
    await expect(verifyReceipt({ ...input, now: created + 5 * 60_000 })).resolves.toBeUndefined();
    await expect(verifyReceipt({ ...input, now: created + 5 * 60_000 + 1 })).rejects.toThrow("receipt too old");
    await expect(verifyReceipt({ ...input, now: created - 5 * 60_000 - 1 })).rejects.toThrow("receipt too old");
  });

  it("rejects a receipt for another app or key", async () => {
    await expect(verifyReceipt({ ...input, appId: "1234567890.com.example.other" })).rejects.toThrow(
      "receipt App ID mismatch",
    );
    const other = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
      "sign",
    ])) as CryptoKeyPair;
    const otherKey = new Uint8Array((await crypto.subtle.exportKey("raw", other.publicKey)) as ArrayBuffer);
    await expect(verifyReceipt({ ...input, publicKey: otherKey })).rejects.toThrow("receipt public key mismatch");
  });

  it("rejects a tampered payload", async () => {
    const tampered = new Uint8Array(receipt);
    const position = indexOf(tampered, new TextEncoder().encode("ATTEST"));
    tampered[position] = "B".charCodeAt(0);
    await expect(verifyReceipt({ ...input, receipt: tampered })).rejects.toThrow("invalid receipt signature");
  });

  it("rejects a chain that doesn't lead to Apple Root CA - G3", async () => {
    await expect(verifyReceipt({ ...input, root: intermediate })).rejects.toThrow("chain");
  });

  it("rejects a receipt signed by another certificate under an Apple CA", async () => {
    // Apple Root CA - G3 also issues certificates for developer keys: only the receipt signer counts.
    await expect(
      verifyReceipt({ ...input, receipt: fromBase64(forged.receipt), root: fromBase64(forged.root) }),
    ).rejects.toThrow("receipt not signed by Apple's receipt signer");
  });

  it("rejects garbage", async () => {
    await expect(verifyReceipt({ ...input, receipt: new Uint8Array([0x30, 0x00]) })).rejects.toThrow();
  });
});

describe("attestation receipt", () => {
  it("is verified with the attestation", async () => {
    const attestation = {
      attestation: fromBase64(sample.attestation),
      keyId: fromBase64(sample.keyId),
      clientDataHash: new TextEncoder().encode(sample.challenge),
      appId: sample.appId,
      validationCategories: [1],
    };
    await expect(verifyAttestation({ ...attestation, now: created + 60_000 })).resolves.toBeDefined();
    await expect(verifyAttestation({ ...attestation, now: created + 10 * 60_000 })).rejects.toThrow("receipt too old");
  });
});

function indexOf(data: Uint8Array, part: Uint8Array): number {
  for (let i = 0; i + part.length <= data.length; i++) {
    if (part.every((byte, j) => data[i + j] === byte)) return i;
  }
  throw new Error("not found");
}
