// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./QuantumGuard.sol";

interface IQEscrowInstance {
    function ejecutarResolucion(address ganador) external;
}

/// @title QDisputeModule
/// @notice Resolución 2-de-3 (comprador, vendedor, árbitro) con firmas PQ.
/// @dev El árbitro y el admin SIEMPRE firman con Lamport. Las partes usan su
///      wallet; si registraron clave PQ deben usar `registrarVotoPQ`.
contract QDisputeModule {
    struct Disputa {
        address comprador;
        address vendedor;
        uint8 votosComprador;
        uint8 votosVendedor;
        bool resuelta;
    }

    address public admin;
    QuantumGuard public immutable guard;
    mapping(address => bool) public esArbitro;

    mapping(address => Disputa) private _disputas;
    mapping(address => mapping(address => bool)) private _haVotado;

    event VotoRegistrado(address indexed instancia, address indexed votante, address indexed ganador);
    event ResolucionEjecutada(address indexed instancia, address indexed ganador);
    event ArbitroActualizado(address indexed arbitro, bool habilitado);
    event AdminTransferido(address nuevoAdmin);

    constructor(address admin_, address guard_, address arbitro) {
        require(admin_ != address(0) && guard_ != address(0), "config invalida");
        admin = admin_;
        guard = QuantumGuard(guard_);
        esArbitro[arbitro] = true;
        emit ArbitroActualizado(arbitro, true);
    }

    function registrarDisputa(address comprador_, address vendedor_) external {
        address instancia = msg.sender;
        require(_disputas[instancia].comprador == address(0), "disputa ya registrada");
        _disputas[instancia].comprador = comprador_;
        _disputas[instancia].vendedor  = vendedor_;
    }

    function accionVoto(address instancia, address ganador) public pure returns (bytes32) {
        return keccak256(abi.encode("VOTO", instancia, ganador));
    }

    /// @notice Voto de una parte sin clave PQ registrada.
    function registrarVoto(address instancia, address ganador) external {
        _registrarVoto(instancia, ganador, "");
    }

    function registrarVotoPQ(address instancia, address ganador, bytes calldata firmaPQ) external {
        _registrarVoto(instancia, ganador, firmaPQ);
    }

    function _registrarVoto(address instancia, address ganador, bytes memory firmaPQ) internal {
        Disputa storage d = _disputas[instancia];
        require(!d.resuelta,                "disputa ya resuelta");
        require(d.comprador != address(0),  "disputa no registrada");

        bool esComprador = msg.sender == d.comprador;
        bool esVendedor  = msg.sender == d.vendedor;
        bool arbitro     = esArbitro[msg.sender];
        require(esComprador || esVendedor || arbitro, "no autorizado");
        require(!_haVotado[instancia][msg.sender],    "ya voto");
        require(ganador == d.comprador || ganador == d.vendedor, "ganador invalido");

        if (arbitro || guard.tieneClave(msg.sender)) {
            guard.consumir(msg.sender, accionVoto(instancia, ganador), firmaPQ);
        }

        _haVotado[instancia][msg.sender] = true;
        if (ganador == d.comprador) {
            d.votosComprador++;
        } else {
            d.votosVendedor++;
        }

        emit VotoRegistrado(instancia, msg.sender, ganador);
        _verificarResolucion(instancia);
    }

    function getDisputa(address instancia) external view returns (
        address comprador,
        address vendedor,
        uint8 votosComprador,
        uint8 votosVendedor,
        bool resuelta
    ) {
        Disputa storage d = _disputas[instancia];
        return (d.comprador, d.vendedor, d.votosComprador, d.votosVendedor, d.resuelta);
    }

    function _verificarResolucion(address instancia) internal {
        Disputa storage d = _disputas[instancia];
        if (d.votosComprador >= 2) {
            d.resuelta = true;
            emit ResolucionEjecutada(instancia, d.comprador);
            IQEscrowInstance(instancia).ejecutarResolucion(d.comprador);
        } else if (d.votosVendedor >= 2) {
            d.resuelta = true;
            emit ResolucionEjecutada(instancia, d.vendedor);
            IQEscrowInstance(instancia).ejecutarResolucion(d.vendedor);
        }
    }

    // ─── Administración (ECDSA + PQ) ──────────────────────────────────────

    modifier soloAdminPQ(bytes32 accion, bytes calldata firma) {
        require(msg.sender == admin, "solo admin");
        guard.consumir(admin, accion, firma);
        _;
    }

    function setArbitro(address arbitro, bool habilitado, bytes calldata firmaPQ)
        external
        soloAdminPQ(keccak256(abi.encode("SET_ARBITRO", arbitro, habilitado)), firmaPQ)
    {
        esArbitro[arbitro] = habilitado;
        emit ArbitroActualizado(arbitro, habilitado);
    }

    function transferirAdmin(address nuevo, bytes calldata firmaPQ)
        external
        soloAdminPQ(keccak256(abi.encode("TRANSFERIR_ADMIN", nuevo)), firmaPQ)
    {
        require(nuevo != address(0), "admin invalido");
        admin = nuevo;
        emit AdminTransferido(nuevo);
    }
}
