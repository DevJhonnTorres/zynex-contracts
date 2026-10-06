// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/quantum/QuantumGuard.sol";
import "./lib/PQ.sol";

/// @notice Genera (sin transmitir) una firma PQ lista para pasar como `firmaPQ`.
///   PQ_SEED, QUANTUM_GUARD, FIRMANTE, CONSUMIDOR, ACCION (bytes32)
/// Ejemplo (activar un escrow):
///   ACCION=$(cast keccak ACTIVAR_ESCROW) CONSUMIDOR=<instancia> \
///   forge script script/FirmarPQ.s.sol --rpc-url base_sepolia
contract FirmarPQ is Script {
    function run() external view {
        bytes memory f = PQ.firma(
            QuantumGuard(vm.envAddress("QUANTUM_GUARD")),
            vm.envBytes32("PQ_SEED"),
            vm.envAddress("CONSUMIDOR"),
            vm.envAddress("FIRMANTE"),
            vm.envBytes32("ACCION")
        );
        console.logBytes(f);
    }
}
