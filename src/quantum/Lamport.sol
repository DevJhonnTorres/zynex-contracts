// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Lamport
/// @notice Verificación de firmas Lamport de un solo uso sobre keccak256.
/// @dev Las firmas basadas en hash no dependen de logaritmos discretos ni de
///      factorización, por lo que el algoritmo de Shor no las rompe. Con un
///      digest de 256 bits la seguridad post-cuántica es de ~128 bits (Grover).
///
///      Clave privada: sk[i][b] para i en [0,256) y b en {0,1}.
///      Clave pública: pk[i][b] = keccak256(sk[i][b]).
///      Compromiso:    keccak256(pk[0][0] ‖ pk[0][1] ‖ pk[1][0] ‖ ... ‖ pk[255][1]).
///
///      Para firmar un digest se revela sk[i][bit_i] y se entrega pk[i][1-bit_i],
///      lo que permite reconstruir el compromiso sin almacenar las 512 hojas.
library Lamport {
    uint256 internal constant BITS = 256;

    /// @notice Reconstruye el compromiso de la clave pública a partir de una firma.
    /// @param digest  Mensaje firmado (bit 0 = bit más significativo).
    /// @param revelados  sk[i][bit_i] revelados.
    /// @param opuestos   pk[i][1 - bit_i].
    function compromiso(
        bytes32 digest,
        bytes32[BITS] memory revelados,
        bytes32[BITS] memory opuestos
    ) internal pure returns (bytes32 h) {
        bytes32[2 * BITS] memory pk;
        uint256 d = uint256(digest);
        for (uint256 i; i < BITS; ++i) {
            bytes32 hoja;
            bytes32 sk = revelados[i];
            assembly {
                mstore(0x00, sk)
                hoja := keccak256(0x00, 0x20)
            }
            if ((d >> (255 - i)) & 1 == 0) {
                pk[2 * i]     = hoja;
                pk[2 * i + 1] = opuestos[i];
            } else {
                pk[2 * i]     = opuestos[i];
                pk[2 * i + 1] = hoja;
            }
        }
        assembly {
            h := keccak256(pk, 0x4000) // 512 * 32 bytes
        }
    }

    function verificar(
        bytes32 digest,
        bytes32 pkHash,
        bytes32[BITS] memory revelados,
        bytes32[BITS] memory opuestos
    ) internal pure returns (bool) {
        return pkHash != bytes32(0) && compromiso(digest, revelados, opuestos) == pkHash;
    }
}
