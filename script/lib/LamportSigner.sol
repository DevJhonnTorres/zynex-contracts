// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title LamportSigner
/// @notice Generación de claves y firmas Lamport (SOLO off-chain: scripts y tests).
/// @dev Las claves se derivan de forma determinista de una semilla secreta:
///        sk(semilla, n, i, b) = keccak256(abi.encode(semilla, n, i, b))
///      donde n es el índice de la clave (= nonce del firmante en el
///      QuantumGuard). Así basta con guardar la semilla de 32 bytes.
///      Debe coincidir con tools/pq-signer/lamport.mjs.
library LamportSigner {
    function sk(bytes32 semilla, uint256 n, uint256 i, uint256 b) internal pure returns (bytes32) {
        return keccak256(abi.encode(semilla, n, i, b));
    }

    function pk(bytes32 semilla, uint256 n, uint256 i, uint256 b) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(sk(semilla, n, i, b)));
    }

    function pkHash(bytes32 semilla, uint256 n) internal pure returns (bytes32) {
        bytes32[512] memory hojas;
        for (uint256 i; i < 256; ++i) {
            hojas[2 * i]     = pk(semilla, n, i, 0);
            hojas[2 * i + 1] = pk(semilla, n, i, 1);
        }
        return keccak256(abi.encodePacked(hojas));
    }

    function firmar(bytes32 semilla, uint256 n, bytes32 digest)
        internal
        pure
        returns (bytes32[256] memory revelados, bytes32[256] memory opuestos)
    {
        uint256 d = uint256(digest);
        for (uint256 i; i < 256; ++i) {
            uint256 bit = (d >> (255 - i)) & 1;
            revelados[i] = sk(semilla, n, i, bit);
            opuestos[i]  = pk(semilla, n, i, 1 - bit);
        }
    }

    /// @notice Firma codificada tal como la espera QuantumGuard.consumir.
    function firmaCodificada(bytes32 semilla, uint256 n, bytes32 digest, bytes32 siguientePkHash)
        internal
        pure
        returns (bytes memory)
    {
        (bytes32[256] memory r, bytes32[256] memory o) = firmar(semilla, n, digest);
        return abi.encode(siguientePkHash, r, o);
    }
}
