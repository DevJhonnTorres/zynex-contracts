// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IDisputeModule {
    function registrarDisputa(address comprador, address vendedor) external;
}

contract EscrowInstance is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Estado { CREADA, ACTIVA, COMPLETADA, EXPIRADA, DISPUTA, RESUELTA }

    address public immutable factory;
    address public immutable vendedor;
    address public immutable comprador;
    address public immutable usdt;
    address public immutable disputeModule;
    address public immutable agente;
    uint256 public immutable monto;
    uint256 public immutable deadline;
    bytes32 public immutable referenciaPago;
    uint256 public immutable feeBps;
    address public immutable treasury;

    Estado public estado;

    event EscrowActivado(address indexed instancia, uint256 timestamp);
    event EscrowLiberado(address indexed instancia, address indexed receptor, uint256 monto, uint256 fee);
    event OrdenExpirada(address indexed instancia, address indexed vendedor_, uint256 montoDevuelto);
    event DisputaAbierta(address indexed instancia, address indexed quien, uint256 timestamp);
    event DisputaResuelta(address indexed instancia, address indexed ganador, uint256 monto);

    modifier soloAgente() {
        require(msg.sender == agente, "solo agente autorizado");
        _;
    }

    constructor(
        address vendedor_,
        address comprador_,
        address usdt_,
        address disputeModule_,
        address agente_,
        uint256 monto_,
        uint256 deadline_,
        bytes32 referenciaPago_,
        uint256 feeBps_,
        address treasury_
    ) {
        factory        = msg.sender;
        vendedor       = vendedor_;
        comprador      = comprador_;
        usdt           = usdt_;
        disputeModule  = disputeModule_;
        agente         = agente_;
        monto          = monto_;
        deadline       = deadline_;
        referenciaPago = referenciaPago_;
        feeBps         = feeBps_;
        treasury       = treasury_;
        estado         = Estado.CREADA;
    }

    function activarEscrow() external soloAgente {
        require(estado == Estado.CREADA, "estado invalido");
        require(IERC20(usdt).balanceOf(address(this)) >= monto, "fondos insuficientes");
        estado = Estado.ACTIVA;
        emit EscrowActivado(address(this), block.timestamp);
    }

    function liberarEscrow() external nonReentrant {
        require(estado == Estado.ACTIVA, "no activo");
        require(msg.sender == vendedor || msg.sender == agente, "no autorizado");

        estado = Estado.COMPLETADA;
        uint256 fee            = (monto * feeBps) / 10000;
        uint256 montoComprador = monto - fee;

        IERC20(usdt).safeTransfer(comprador, montoComprador);
        if (fee > 0) IERC20(usdt).safeTransfer(treasury, fee);

        emit EscrowLiberado(address(this), comprador, montoComprador, fee);
    }

    function expirarOrden() external nonReentrant soloAgente {
        require(estado == Estado.ACTIVA, "no activo");
        require(block.timestamp >= deadline, "no ha expirado");

        estado = Estado.EXPIRADA;
        IERC20(usdt).safeTransfer(vendedor, monto);
        emit OrdenExpirada(address(this), vendedor, monto);
    }

    function abrirDisputa() external {
        require(estado == Estado.ACTIVA, "no activo");
        require(msg.sender == comprador || msg.sender == vendedor, "no autorizado");

        estado = Estado.DISPUTA;
        IDisputeModule(disputeModule).registrarDisputa(comprador, vendedor);
        emit DisputaAbierta(address(this), msg.sender, block.timestamp);
    }

    function ejecutarResolucion(address ganador) external nonReentrant {
        require(msg.sender == disputeModule, "solo dispute module");
        require(estado == Estado.DISPUTA, "no en disputa");
        require(ganador == comprador || ganador == vendedor, "ganador invalido");

        estado = Estado.RESUELTA;
        IERC20(usdt).safeTransfer(ganador, monto);
        emit DisputaResuelta(address(this), ganador, monto);
    }
}
