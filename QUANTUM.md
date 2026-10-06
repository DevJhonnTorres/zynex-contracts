# Zynex P2P — Contratos Quantum (post-cuánticos)

La versión Quantum del escrow P2P protege cada acción crítica con **dos firmas**:

1. **ECDSA** (la wallet normal que envía la transacción), y
2. **Lamport sobre keccak256**, una firma basada en hash que un computador
   cuántico no puede romper con el algoritmo de Shor (seguridad ~128 bits
   frente a Grover).

Si algún día un atacante deriva la clave privada ECDSA del agente, del árbitro
o del admin a partir de su clave pública, **no puede mover fondos ni cambiar
la configuración** sin la semilla Lamport, que nunca se publica en la cadena.

## Contratos (`src/quantum/`)

| Contrato | Rol |
|---|---|
| `Lamport.sol` | Verificador de firmas Lamport (256 bits, keccak256). |
| `QuantumGuard.sol` | Registro de claves PQ por cuenta, nonces y verificación. Cada firma consume la clave y registra la siguiente (rotación obligatoria, ninguna clave se usa dos veces). |
| `QEscrowFactory.sol` | Igual que `EscrowFactory`; administración (fee, treasury, agente, dispute module, admin) exige firma PQ del admin. |
| `QEscrowInstance.sol` | Escrow por orden; el agente **siempre** firma PQ (`activarEscrow`, `expirarOrden`, `liberarEscrowPQ`). |
| `QDisputeModule.sol` | Resolución 2-de-3; el árbitro **siempre** firma PQ (`registrarVotoPQ`). |

Comprador y vendedor siguen usando su wallet (MetaMask, etc.) con las mismas
funciones que la v1 (`crearOrden`, `liberarEscrow`, `abrirDisputa`,
`registrarVoto`), así que el frontend no cambia. Si un usuario registra su
propia clave PQ, desde ese momento debe usar las variantes `...PQ`.

El digest firmado incluye `chainid`, el guard, el contrato consumidor, el
firmante, su nonce, la acción y la siguiente clave: una firma no puede
reutilizarse en otra orden, otra acción, otra red ni dos veces.

Costo: cada firma PQ son 16 416 bytes de calldata, ~680k gas por acción del
agente en total (en Base Sepolia, fracciones de centavo).

## Desplegar en Base Sepolia

```bash
# 1. Semillas Lamport (guárdalas como guardas una clave privada)
cast keccak "$(openssl rand -hex 32)"   # -> PQ_SEED del admin
cast keccak "$(openssl rand -hex 32)"   # -> PQ_SEED del agente (si es otra cuenta)

# 2. Desplegar (reusa el MockUSDT existente 0x1725…62A0)
PRIVATE_KEY=0x...  PQ_SEED=0x...  \
AGENT_ADDRESS=0x... ARBITRO_ADDRESS=0x... TREASURY_ADDRESS=0x... \
forge script script/DeployQuantum.s.sol \
  --rpc-url base_sepolia --broadcast --verify
# -> escribe deployments/quantum-84532.json

# 3. Si el agente / árbitro son cuentas distintas al admin, cada uno registra su clave:
PRIVATE_KEY=<clave del agente> PQ_SEED=<semilla del agente> QUANTUM_GUARD=0x... \
forge script script/RegistrarClavePQ.s.sol --rpc-url base_sepolia --broadcast
```

Luego, en Vercel (proyecto `zynex`), definir:

```
NEXT_PUBLIC_QUANTUM_ESCROW_FACTORY=<EscrowFactory>
NEXT_PUBLIC_QUANTUM_DISPUTE_MODULE=<DisputeModule>
NEXT_PUBLIC_QUANTUM_GUARD=<QuantumGuard>
```

y redeploy: el frontend pasa a usar la versión Quantum y muestra la etiqueta
`QUANTUM-SAFE`.

## Firmar como agente

Con Node (`tools/pq-signer`, recomendado para el bot):

```bash
cd tools/pq-signer && npm install
PQ_SEED=0x... RPC_URL=https://sepolia.base.org QUANTUM_GUARD=0x... FIRMANTE=<agente> \
  node cli.mjs firmar <instancia> ACTIVAR     # -> firma hex
cast send <instancia> "activarEscrow(bytes)" <firma> --private-key <agente>
```

Desde código: `import { firmaPQ, ACCIONES } from './lamport.mjs'`.

Con Foundry: `script/FirmarPQ.s.sol` (mismas variables + `CONSUMIDOR`, `ACCION`).

Las firmas dependen del nonce actual del firmante: genera cada firma justo
antes de enviar la transacción y envía las acciones del agente una a una.

## Tests

```bash
forge test --match-path "test/quantum/*"
```
