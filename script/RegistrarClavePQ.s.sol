// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/quantum/QuantumGuard.sol";
import "./lib/LamportSigner.sol";

/// @notice Registra la clave PQ inicial de la cuenta PRIVATE_KEY.
///   PRIVATE_KEY, PQ_SEED, QUANTUM_GUARD
contract RegistrarClavePQ is Script {
    function run() external {
        uint256 key     = vm.envUint("PRIVATE_KEY");
        bytes32 semilla = vm.envBytes32("PQ_SEED");
        QuantumGuard guard = QuantumGuard(vm.envAddress("QUANTUM_GUARD"));

        bytes32 pkHash = LamportSigner.pkHash(semilla, 0);

        vm.startBroadcast(key);
        guard.registrarClave(pkHash);
        vm.stopBroadcast();

        console.log("Firmante:", vm.addr(key));
        console.log("pkHash:  ", vm.toString(pkHash));
    }
}
