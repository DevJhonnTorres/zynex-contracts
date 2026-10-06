// Firmas Lamport (post-cuánticas) compatibles con src/quantum/QuantumGuard.sol.
// Debe coincidir con script/lib/LamportSigner.sol.
import { keccak256, encodeAbiParameters, concat, hexToBigInt, stringToHex } from 'viem'

const U = { type: 'uint256' }
const B32 = { type: 'bytes32' }

export const sk = (semilla, n, i, b) =>
  keccak256(encodeAbiParameters([B32, U, U, U], [semilla, BigInt(n), BigInt(i), BigInt(b)]))

export const pk = (semilla, n, i, b) => keccak256(sk(semilla, n, i, b))

export function pkHash(semilla, n) {
  const hojas = []
  for (let i = 0; i < 256; i++) hojas.push(pk(semilla, n, i, 0), pk(semilla, n, i, 1))
  return keccak256(concat(hojas))
}

export function firmar(semilla, n, digest) {
  const d = hexToBigInt(digest)
  const revelados = []
  const opuestos = []
  for (let i = 0; i < 256; i++) {
    const bit = Number((d >> BigInt(255 - i)) & 1n)
    revelados.push(sk(semilla, n, i, bit))
    opuestos.push(pk(semilla, n, i, 1 - bit))
  }
  return { revelados, opuestos }
}

export function codificar(siguientePkHash, { revelados, opuestos }) {
  return encodeAbiParameters(
    [B32, { type: 'bytes32[256]' }, { type: 'bytes32[256]' }],
    [siguientePkHash, revelados, opuestos],
  )
}

// Acciones fijas de QEscrowInstance / QuantumGuard.
export const ACCIONES = {
  ACTIVAR: keccak256(stringToHex('ACTIVAR_ESCROW')),
  LIBERAR: keccak256(stringToHex('LIBERAR_ESCROW')),
  EXPIRAR: keccak256(stringToHex('EXPIRAR_ORDEN')),
  DISPUTA: keccak256(stringToHex('ABRIR_DISPUTA')),
  ROTAR:   keccak256(stringToHex('ROTAR_CLAVE')),
}

export const accionVoto = (instancia, ganador) =>
  keccak256(encodeAbiParameters(
    [{ type: 'string' }, { type: 'address' }, { type: 'address' }],
    ['VOTO', instancia, ganador],
  ))

const GUARD_ABI = [
  { name: 'nonces', type: 'function', stateMutability: 'view',
    inputs: [{ type: 'address' }], outputs: [{ type: 'uint256' }] },
  { name: 'digest', type: 'function', stateMutability: 'view',
    inputs: [{ type: 'address' }, { type: 'address' }, { type: 'bytes32' }, { type: 'bytes32' }],
    outputs: [{ type: 'bytes32' }] },
]

/**
 * Firma PQ lista para pasar como `firmaPQ`.
 * @param client  viem PublicClient conectado a la red del guard.
 */
export async function firmaPQ(client, { guard, semilla, consumidor, firmante, accion }) {
  const n = await client.readContract({ address: guard, abi: GUARD_ABI, functionName: 'nonces', args: [firmante] })
  const siguiente = pkHash(semilla, n + 1n)
  const digest = await client.readContract({
    address: guard, abi: GUARD_ABI, functionName: 'digest',
    args: [consumidor, firmante, accion, siguiente],
  })
  return codificar(siguiente, firmar(semilla, n, digest))
}
