#!/usr/bin/env node
// Uso:
//   node cli.mjs pk                         → pkHash inicial (para registrarClave)
//   node cli.mjs firmar <consumidor> <accion> → firma PQ hex
// Variables: PQ_SEED, RPC_URL, QUANTUM_GUARD, FIRMANTE
// <accion> puede ser ACTIVAR | LIBERAR | EXPIRAR | DISPUTA | ROTAR o un bytes32.
import { createPublicClient, http } from 'viem'
import { pkHash, firmaPQ, ACCIONES } from './lamport.mjs'

const env = (k) => {
  const v = process.env[k]
  if (!v) { console.error(`Falta ${k}`); process.exit(1) }
  return v
}

const [cmd, consumidor, accionArg] = process.argv.slice(2)

if (cmd === 'pk') {
  console.log(pkHash(env('PQ_SEED'), 0n))
} else if (cmd === 'firmar' && consumidor && accionArg) {
  const client = createPublicClient({ transport: http(env('RPC_URL')) })
  const accion = ACCIONES[accionArg.toUpperCase()] ?? accionArg
  console.log(await firmaPQ(client, {
    guard: env('QUANTUM_GUARD'),
    semilla: env('PQ_SEED'),
    consumidor,
    firmante: env('FIRMANTE'),
    accion,
  }))
} else {
  console.error('Uso: cli.mjs pk | cli.mjs firmar <consumidor> <accion>')
  process.exit(1)
}
