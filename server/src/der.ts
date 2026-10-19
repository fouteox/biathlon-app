/**
 * Minimal DER reader and X.509 parser: just what App Attest needs to check
 * Apple's certificate chain with WebCrypto.
 */

export const TAG = {
  integer: 0x02,
  bitString: 0x03,
  octetString: 0x04,
  oid: 0x06,
  utcTime: 0x17,
  generalizedTime: 0x18,
  sequence: 0x30,
} as const;

export interface DERNode {
  /** First identifier byte (class, constructed bit and low tag number). */
  tag: number;
  /** The whole encoding: identifier, length and contents. */
  bytes: Uint8Array;
  contents: Uint8Array;
}

export class DERError extends Error {}

/** Reads the element at `offset`. Indefinite lengths aren't DER, so they're rejected. */
export function readNode(data: Uint8Array, offset = 0): DERNode {
  let position = offset;
  const tag = byteAt(data, position++);
  if ((tag & 0x1f) === 0x1f) {
    // High tag number form: continuation bytes have the top bit set.
    while (byteAt(data, position++) & 0x80);
  }
  let length = byteAt(data, position++);
  if (length & 0x80) {
    const count = length & 0x7f;
    if (count === 0 || count > 4) throw new DERError("unsupported length");
    length = 0;
    for (let i = 0; i < count; i++) length = length * 256 + byteAt(data, position++);
  }
  const end = position + length;
  if (end > data.length) throw new DERError("truncated element");
  return { tag, bytes: data.subarray(offset, end), contents: data.subarray(position, end) };
}

/** Reads a whole buffer that must hold exactly one element. */
export function readSingle(data: Uint8Array, tag?: number): DERNode {
  const node = readNode(data);
  if (node.bytes.length !== data.length) throw new DERError("trailing bytes");
  if (tag !== undefined) expectTag(node, tag);
  return node;
}

export function children(node: DERNode): DERNode[] {
  if ((node.tag & 0x20) === 0) throw new DERError("not a constructed element");
  const result: DERNode[] = [];
  let offset = 0;
  while (offset < node.contents.length) {
    const child = readNode(node.contents, offset);
    result.push(child);
    offset += child.bytes.length;
  }
  return result;
}

export function expectTag(node: DERNode, tag: number): DERNode {
  if (node.tag !== tag) throw new DERError(`expected tag 0x${tag.toString(16)}, got 0x${node.tag.toString(16)}`);
  return node;
}

export function decodeOID(node: DERNode): string {
  const bytes = expectTag(node, TAG.oid).contents;
  if (bytes.length === 0) throw new DERError("empty OID");
  const parts: number[] = [];
  let value = 0;
  for (const byte of bytes) {
    value = value * 128 + (byte & 0x7f);
    if ((byte & 0x80) === 0) {
      if (parts.length === 0) parts.push(value < 80 ? Math.floor(value / 40) : 2, value < 80 ? value % 40 : value - 80);
      else parts.push(value);
      value = 0;
    }
  }
  return parts.join(".");
}

/** UTCTime or GeneralizedTime, in milliseconds since 1970. */
export function decodeTime(node: DERNode): number {
  const text = new TextDecoder().decode(node.contents);
  const match =
    node.tag === TAG.utcTime
      ? text.match(/^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/)
      : node.tag === TAG.generalizedTime
        ? text.match(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/)
        : null;
  if (!match) throw new DERError("invalid time");
  const [, y, mo, d, h, mi, s] = match.map(Number) as number[];
  // RFC 5280: UTCTime years 50-99 mean 19xx, 00-49 mean 20xx.
  const year = node.tag === TAG.utcTime ? (y! >= 50 ? 1900 + y! : 2000 + y!) : y!;
  return Date.UTC(year, mo! - 1, d!, h!, mi!, s!);
}

export interface Certificate {
  tbs: Uint8Array;
  signatureAlgorithm: string;
  signature: Uint8Array;
  issuer: Uint8Array;
  subject: Uint8Array;
  notBefore: number;
  notAfter: number;
  /** DER SubjectPublicKeyInfo, as WebCrypto imports it. */
  spki: Uint8Array;
  /** Named curve OID of the EC public key. */
  curve: string;
  /** Contents of the public key BIT STRING: the X9.62 point. */
  publicKey: Uint8Array;
  extensions: Map<string, Uint8Array>;
}

export function parseCertificate(data: Uint8Array): Certificate {
  const [tbsNode, algorithm, signatureNode] = children(readSingle(data, TAG.sequence));
  if (!tbsNode || !algorithm || !signatureNode) throw new DERError("invalid certificate");
  const fields = children(expectTag(tbsNode, TAG.sequence));
  // Skips the optional [0] version.
  const start = fields[0]?.tag === 0xa0 ? 1 : 0;
  const [, , issuer, validity, subject, spki] = fields.slice(start);
  if (!issuer || !validity || !subject || !spki) throw new DERError("invalid certificate");
  const [notBefore, notAfter] = children(validity);
  const [keyAlgorithm, keyBits] = children(expectTag(spki, TAG.sequence));
  if (!notBefore || !notAfter || !keyAlgorithm || !keyBits) throw new DERError("invalid certificate");
  const [, curveNode] = children(keyAlgorithm);
  if (!curveNode) throw new DERError("not an EC key");

  const extensions = new Map<string, Uint8Array>();
  const extensionsNode = fields.slice(start + 6).find((field) => field.tag === 0xa3);
  if (extensionsNode) {
    const [list] = children(extensionsNode);
    for (const extension of children(expectTag(list!, TAG.sequence))) {
      const parts = children(extension);
      const value = parts[parts.length - 1];
      if (!parts[0] || !value) throw new DERError("invalid extension");
      extensions.set(decodeOID(parts[0]), expectTag(value, TAG.octetString).contents);
    }
  }

  return {
    tbs: tbsNode.bytes,
    signatureAlgorithm: decodeOID(children(algorithm)[0]!),
    signature: bitStringBytes(signatureNode),
    issuer: issuer.bytes,
    subject: subject.bytes,
    notBefore: decodeTime(notBefore),
    notAfter: decodeTime(notAfter),
    spki: spki.bytes,
    curve: decodeOID(curveNode),
    publicKey: bitStringBytes(keyBits),
    extensions,
  };
}

/** BasicConstraints (2.5.29.19) cA flag. */
export function isCertificateAuthority(certificate: Certificate): boolean {
  const value = certificate.extensions.get("2.5.29.19");
  if (!value) return false;
  const [flag] = children(readSingle(value, TAG.sequence));
  return flag?.tag === 0x01 && flag.contents[0] === 0xff;
}

function bitStringBytes(node: DERNode): Uint8Array {
  const contents = expectTag(node, TAG.bitString).contents;
  if (contents[0] !== 0) throw new DERError("unexpected unused bits");
  return contents.subarray(1);
}

function byteAt(data: Uint8Array, index: number): number {
  const byte = data[index];
  if (byte === undefined) throw new DERError("truncated element");
  return byte;
}
