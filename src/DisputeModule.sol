// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

interface IEscrowInstance {
    function ejecutarResolucion(address ganador) external;
}

contract DisputeModule is AccessControl {
    bytes32 public constant ARBITRO_ROLE = keccak256("ARBITRO_ROLE");

    struct Disputa {
        address comprador;
        address vendedor;
        uint8 votosComprador;
        uint8 votosVendedor;
        bool resuelta;
    }

    mapping(address => Disputa) private _disputas;
    mapping(address => mapping(address => bool)) private _haVotado;

    event VotoRegistrado(address indexed instancia, address indexed votante, address indexed ganador);
    event ResolucionEjecutada(address indexed instancia, address indexed ganador);

    constructor(address admin, address arbitro) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ARBITRO_ROLE, arbitro);
    }

    function registrarDisputa(address comprador_, address vendedor_) external {
        address instancia = msg.sender;
        require(_disputas[instancia].comprador == address(0), "disputa ya registrada");
        _disputas[instancia].comprador = comprador_;
        _disputas[instancia].vendedor  = vendedor_;
    }

    function registrarVoto(address instancia, address ganador) external {
        Disputa storage d = _disputas[instancia];
        require(!d.resuelta,                "disputa ya resuelta");
        require(d.comprador != address(0),  "disputa no registrada");

        bool esComprador = msg.sender == d.comprador;
        bool esVendedor  = msg.sender == d.vendedor;
        bool esArbitro   = hasRole(ARBITRO_ROLE, msg.sender);
        require(esComprador || esVendedor || esArbitro, "no autorizado");
        require(!_haVotado[instancia][msg.sender],      "ya voto");
        require(ganador == d.comprador || ganador == d.vendedor, "ganador invalido");

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
            IEscrowInstance(instancia).ejecutarResolucion(d.comprador);
        } else if (d.votosVendedor >= 2) {
            d.resuelta = true;
            emit ResolucionEjecutada(instancia, d.vendedor);
            IEscrowInstance(instancia).ejecutarResolucion(d.vendedor);
        }
    }
}
