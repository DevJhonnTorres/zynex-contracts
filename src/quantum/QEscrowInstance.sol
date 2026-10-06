// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./QuantumGuard.sol";

interface IQDisputeModule {
    function registrarDisputa(address comprador, address vendedor) external;
}

/// @title QEscrowInstance
/// @notice Escrow P2P con autorización híbrida ECDSA + firma post-cuántica.
/// @dev - El agente SIEMPRE firma con su clave Lamport (activar, liberar, expirar).
///      - Vendedor y comprador usan su wallet normal; si registraron una clave
///        PQ en el QuantumGuard, deben usar las variantes `...PQ`.
contract QEscrowInstance is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Estado { CREADA, ACTIVA, COMPLETADA, EXPIRADA, DISPUTA, RESUELTA }

    bytes32 public constant ACCION_ACTIVAR = keccak256("ACTIVAR_ESCROW");
    bytes32 public constant ACCION_LIBERAR = keccak256("LIBERAR_ESCROW");
    bytes32 public constant ACCION_EXPIRAR = keccak256("EXPIRAR_ORDEN");
    bytes32 public constant ACCION_DISPUTA = keccak256("ABRIR_DISPUTA");

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
    QuantumGuard public immutable guard;

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
        address treasury_,
        address guard_
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
        guard          = QuantumGuard(guard_);
        estado         = Estado.CREADA;
    }

    // ─── Agente (PQ obligatorio) ──────────────────────────────────────────

    function activarEscrow(bytes calldata firmaPQ) external soloAgente {
        require(estado == Estado.CREADA, "estado invalido");
        require(IERC20(usdt).balanceOf(address(this)) >= monto, "fondos insuficientes");
        guard.consumir(agente, ACCION_ACTIVAR, firmaPQ);
        estado = Estado.ACTIVA;
        emit EscrowActivado(address(this), block.timestamp);
    }

    function expirarOrden(bytes calldata firmaPQ) external nonReentrant soloAgente {
        require(estado == Estado.ACTIVA, "no activo");
        require(block.timestamp >= deadline, "no ha expirado");
        guard.consumir(agente, ACCION_EXPIRAR, firmaPQ);

        estado = Estado.EXPIRADA;
        IERC20(usdt).safeTransfer(vendedor, monto);
        emit OrdenExpirada(address(this), vendedor, monto);
    }

    // ─── Liberación ───────────────────────────────────────────────────────

    /// @notice Liberación por un vendedor sin clave PQ registrada.
    function liberarEscrow() external nonReentrant {
        _liberar("");
    }

    /// @notice Liberación con firma PQ (agente, o vendedor con clave PQ).
    function liberarEscrowPQ(bytes calldata firmaPQ) external nonReentrant {
        _liberar(firmaPQ);
    }

    function _liberar(bytes memory firmaPQ) internal {
        require(estado == Estado.ACTIVA, "no activo");
        require(msg.sender == vendedor || msg.sender == agente, "no autorizado");
        _autorizar(ACCION_LIBERAR, firmaPQ, msg.sender == agente);

        estado = Estado.COMPLETADA;
        uint256 fee            = (monto * feeBps) / 10000;
        uint256 montoComprador = monto - fee;

        IERC20(usdt).safeTransfer(comprador, montoComprador);
        if (fee > 0) IERC20(usdt).safeTransfer(treasury, fee);

        emit EscrowLiberado(address(this), comprador, montoComprador, fee);
    }

    // ─── Disputas ─────────────────────────────────────────────────────────

    function abrirDisputa() external {
        _abrirDisputa("");
    }

    function abrirDisputaPQ(bytes calldata firmaPQ) external {
        _abrirDisputa(firmaPQ);
    }

    function _abrirDisputa(bytes memory firmaPQ) internal {
        require(estado == Estado.ACTIVA, "no activo");
        require(msg.sender == comprador || msg.sender == vendedor, "no autorizado");
        _autorizar(ACCION_DISPUTA, firmaPQ, false);

        estado = Estado.DISPUTA;
        IQDisputeModule(disputeModule).registrarDisputa(comprador, vendedor);
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

    // ─── Interno ──────────────────────────────────────────────────────────

    /// @dev Exige firma PQ si el llamador es privilegiado o tiene clave registrada.
    function _autorizar(bytes32 accion, bytes memory firmaPQ, bool obligatorio) internal {
        if (obligatorio || guard.tieneClave(msg.sender)) {
            guard.consumir(msg.sender, accion, firmaPQ);
        }
    }
}
