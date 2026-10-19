/**
 * Minimal CBOR decoder (RFC 8949) for App Attest objects: integers, byte and
 * text strings, arrays, maps and simple values, definite lengths only.
 */

export type CBORValue = number | Uint8Array | string | boolean | null | CBORValue[] | Map<CBORValue, CBORValue>;

export class CBORError extends Error {}

const MAX_DEPTH = 16;

/** Decodes one item starting at `offset` and returns where it ends. */
export function decodeItem(data: Uint8Array, offset = 0, depth = 0): { value: CBORValue; end: number } {
  if (depth > MAX_DEPTH) throw new CBORError("nesting too deep");
  const initial = byteAt(data, offset);
  const major = initial >> 5;
  const info = initial & 0x1f;
  let position = offset + 1;

  let argument: number;
  if (info < 24) {
    argument = info;
  } else if (info <= 27) {
    const size = 1 << (info - 24);
    argument = 0;
    for (let i = 0; i < size; i++) argument = argument * 256 + byteAt(data, position++);
    if (!Number.isSafeInteger(argument)) throw new CBORError("integer too large");
  } else {
    throw new CBORError("unsupported encoding");
  }

  switch (major) {
    case 0:
      return { value: argument, end: position };
    case 1:
      return { value: -1 - argument, end: position };
    case 2:
    case 3: {
      const end = position + argument;
      if (end > data.length) throw new CBORError("truncated string");
      const bytes = data.subarray(position, end);
      return { value: major === 2 ? bytes : decodeText(bytes), end };
    }
    case 4: {
      const items: CBORValue[] = [];
      for (let i = 0; i < argument; i++) {
        const item = decodeItem(data, position, depth + 1);
        items.push(item.value);
        position = item.end;
      }
      return { value: items, end: position };
    }
    case 5: {
      const map = new Map<CBORValue, CBORValue>();
      for (let i = 0; i < argument; i++) {
        const key = decodeItem(data, position, depth + 1);
        const value = decodeItem(data, key.end, depth + 1);
        if (map.has(key.value)) throw new CBORError("duplicate map key");
        map.set(key.value, value.value);
        position = value.end;
      }
      return { value: map, end: position };
    }
    case 7:
      if (argument === 20) return { value: false, end: position };
      if (argument === 21) return { value: true, end: position };
      if (argument === 22) return { value: null, end: position };
      throw new CBORError("unsupported simple value");
    default:
      throw new CBORError("unsupported major type");
  }
}

/** Decodes a buffer that must hold exactly one item. */
export function decode(data: Uint8Array): CBORValue {
  const { value, end } = decodeItem(data);
  if (end !== data.length) throw new CBORError("trailing bytes");
  return value;
}

function decodeText(bytes: Uint8Array): string {
  try {
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
  } catch {
    throw new CBORError("invalid UTF-8 text");
  }
}

function byteAt(data: Uint8Array, index: number): number {
  const byte = data[index];
  if (byte === undefined) throw new CBORError("truncated item");
  return byte;
}
