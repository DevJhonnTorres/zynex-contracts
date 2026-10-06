// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MockUSDT.sol";
import "../src/quantum/QuantumGuard.sol";
import "../src/quantum/QDisputeModule.sol";
import "../src/quantum/QEscrowFactory.sol";
import "./lib/LamportSigner.sol";

/// @notice Despliega la versión post-cuántica del P2P de Zynex.
///
/// Variables de entorno:
///   PRIVATE_KEY       clave ECDSA del desplegador (admin).
///   PQ_SEED           semilla Lamport (bytes32) del desplegador. Si se define,
///                     se registra su clave PQ inicial (necesaria para administrar).
///   USDT_ADDRESS      token a usar. Por defecto, el MockUSDT ya desplegado en
///                     Base Sepolia; en otras redes se despliega uno nuevo.
///   TREASURY_ADDRESS, ARBITRO_ADDRESS, AGENT_ADDRESS, FEE_BPS  (opcionales)
///
/// El agente y el árbitro deben registrar su propia clave PQ con
/// script/RegistrarClavePQ.s.sol usando sus propias claves.
contract DeployQuantum is Script {
    address constant MOCK_USDT_BASE_SEPOLIA = 0x1725cd2965e4D57DB3C60DcB3F7CDD97D86B62A0;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);
        address arbitro  = vm.envOr("ARBITRO_ADDRESS",  deployer);
        address agente   = vm.envOr("AGENT_ADDRESS",    deployer);
        uint256 feeBps   = vm.envOr("FEE_BPS", uint256(500));
        bytes32 semilla  = vm.envOr("PQ_SEED", bytes32(0));
        address usdt     = vm.envOr(
            "USDT_ADDRESS",
            block.chainid == 84532 ? MOCK_USDT_BASE_SEPOLIA : address(0)
        );

        vm.startBroadcast(deployerKey);

        if (usdt == address(0)) {
            MockUSDT m = new MockUSDT();
            m.mint(deployer, 10_000e6);
            usdt = address(m);
        }

        QuantumGuard guard = new QuantumGuard(deployer);
        QDisputeModule dm  = new QDisputeModule(deployer, address(guard), arbitro);
        QEscrowFactory factory = new QEscrowFactory(
            deployer, address(guard), usdt, address(dm), treasury, feeBps, agente
        );

        address[] memory consumidores = new address[](2);
        consumidores[0] = address(factory);
        consumidores[1] = address(dm);
        guard.inicializar(address(factory), consumidores);

        if (semilla != bytes32(0)) {
            guard.registrarClave(LamportSigner.pkHash(semilla, 0));
        }

        vm.stopBroadcast();

        console.log("MockUSDT:       ", usdt);
        console.log("QuantumGuard:   ", address(guard));
        console.log("QDisputeModule: ", address(dm));
        console.log("QEscrowFactory: ", address(factory));
        console.log("Agente:         ", agente);
        console.log("Arbitro:        ", arbitro);
        console.log("Clave PQ admin: ", semilla != bytes32(0) ? "registrada" : "PENDIENTE (PQ_SEED no definido)");

        string memory o = "deploy";
        vm.serializeUint(o, "chainId", block.chainid);
        vm.serializeAddress(o, "deployer", deployer);
        vm.serializeAddress(o, "agente", agente);
        vm.serializeAddress(o, "arbitro", arbitro);
        vm.serializeString(o, "security", "hybrid ECDSA + Lamport (post-quantum, keccak256)");

        string memory c = "contracts";
        vm.serializeAddress(c, "MockUSDT", usdt);
        vm.serializeAddress(c, "QuantumGuard", address(guard));
        vm.serializeAddress(c, "DisputeModule", address(dm));
        string memory cs = vm.serializeAddress(c, "EscrowFactory", address(factory));

        string memory json = vm.serializeString(o, "contracts", cs);
        vm.writeJson(json, string.concat("deployments/quantum-", vm.toString(block.chainid), ".json"));
    }
}
