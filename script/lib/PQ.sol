// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/quantum/QuantumGuard.sol";
import "./LamportSigner.sol";

/// @notice Atajo para producir la firma PQ que espera un contrato consumidor.
library PQ {
    /// @param consumidor Contrato que llamará a guard.consumir (instancia,
    ///        factory, dispute module) o el propio guard para su administración.
    function firma(
        QuantumGuard guard,
        bytes32 semilla,
        address consumidor,
        address firmante,
        bytes32 accion
    ) internal view returns (bytes memory) {
        uint256 n = guard.nonces(firmante);
        bytes32 siguiente = LamportSigner.pkHash(semilla, n + 1);
        bytes32 d = guard.digest(consumidor, firmante, accion, siguiente);
        return LamportSigner.firmaCodificada(semilla, n, d, siguiente);
    }
}
