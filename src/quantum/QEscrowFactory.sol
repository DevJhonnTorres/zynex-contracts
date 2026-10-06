// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./QEscrowInstance.sol";
import "./QuantumGuard.sol";

/// @title QEscrowFactory
/// @notice Factory de escrows P2P resistentes a computación cuántica.
/// @dev Toda la administración exige ECDSA del admin + firma Lamport del admin.
///      `crearOrden` mantiene la misma firma que la v1 para el frontend; un
///      vendedor con clave PQ registrada debe usar `crearOrdenPQ`.
contract QEscrowFactory {
    using SafeERC20 for IERC20;

    address public admin;
    QuantumGuard public immutable guard;
    address public immutable usdtToken;
    address public disputeModule;
    address public treasury;
    uint256 public feeBps;
    address public agentePrincipal;

    mapping(address => bool) public esInstanciaValida;

    event OrdenCreada(
        address indexed instancia,
        address indexed vendedor,
        address indexed comprador,
        uint256 monto,
        bytes32 referenciaPago,
        uint256 deadline
    );
    event FeeActualizado(uint256 nuevoFeeBps);
    event TreasuryActualizado(address nuevoTreasury);
    event AgenteActualizado(address nuevoAgente);
    event DisputeModuleActualizado(address nuevoModulo);
    event AdminTransferido(address nuevoAdmin);

    constructor(
        address admin_,
        address guard_,
        address usdt_,
        address disputeModule_,
        address treasury_,
        uint256 feeBps_,
        address agente_
    ) {
        require(admin_ != address(0) && guard_ != address(0), "config invalida");
        require(feeBps_ <= 1000, "fee maximo 10%");
        admin           = admin_;
        guard           = QuantumGuard(guard_);
        usdtToken       = usdt_;
        disputeModule   = disputeModule_;
        treasury        = treasury_;
        feeBps          = feeBps_;
        agentePrincipal = agente_;
        emit AgenteActualizado(agente_);
    }

    // ─── Órdenes ──────────────────────────────────────────────────────────

    function crearOrden(
        address comprador,
        uint256 monto,
        bytes32 referenciaPago,
        uint256 duracionSegundos
    ) external returns (address) {
        return _crearOrden(comprador, monto, referenciaPago, duracionSegundos, "");
    }

    function crearOrdenPQ(
        address comprador,
        uint256 monto,
        bytes32 referenciaPago,
        uint256 duracionSegundos,
        bytes calldata firmaPQ
    ) external returns (address) {
        return _crearOrden(comprador, monto, referenciaPago, duracionSegundos, firmaPQ);
    }

    function accionCrearOrden(
        address comprador,
        uint256 monto,
        bytes32 referenciaPago,
        uint256 duracionSegundos
    ) public pure returns (bytes32) {
        return keccak256(abi.encode("CREAR_ORDEN", comprador, monto, referenciaPago, duracionSegundos));
    }

    function _crearOrden(
        address comprador,
        uint256 monto,
        bytes32 referenciaPago,
        uint256 duracionSegundos,
        bytes memory firmaPQ
    ) internal returns (address instancia) {
        require(monto > 0,                       "monto invalido");
        require(comprador != address(0),          "comprador invalido");
        require(comprador != msg.sender,          "comprador == vendedor");
        require(duracionSegundos >= 15 minutes,   "deadline muy corto");
        require(agentePrincipal != address(0),    "agente no configurado");

        if (guard.tieneClave(msg.sender)) {
            guard.consumir(
                msg.sender,
                accionCrearOrden(comprador, monto, referenciaPago, duracionSegundos),
                firmaPQ
            );
        }

        uint256 deadline = block.timestamp + duracionSegundos;

        QEscrowInstance nueva = new QEscrowInstance(
            msg.sender,
            comprador,
            usdtToken,
            disputeModule,
            agentePrincipal,
            monto,
            deadline,
            referenciaPago,
            feeBps,
            treasury,
            address(guard)
        );

        instancia = address(nueva);
        esInstanciaValida[instancia] = true;

        IERC20(usdtToken).safeTransferFrom(msg.sender, instancia, monto);

        emit OrdenCreada(instancia, msg.sender, comprador, monto, referenciaPago, deadline);
    }

    // ─── Administración (ECDSA + PQ) ──────────────────────────────────────

    modifier soloAdminPQ(bytes32 accion, bytes calldata firma) {
        require(msg.sender == admin, "solo admin");
        guard.consumir(admin, accion, firma);
        _;
    }

    function setAgentePrincipal(address nuevo, bytes calldata firmaPQ)
        external
        soloAdminPQ(keccak256(abi.encode("SET_AGENTE", nuevo)), firmaPQ)
    {
        require(nuevo != address(0), "agente invalido");
        agentePrincipal = nuevo;
        emit AgenteActualizado(nuevo);
    }

    function setFeeBps(uint256 nuevoBps, bytes calldata firmaPQ)
        external
        soloAdminPQ(keccak256(abi.encode("SET_FEE", nuevoBps)), firmaPQ)
    {
        require(nuevoBps <= 1000, "fee maximo 10%");
        feeBps = nuevoBps;
        emit FeeActualizado(nuevoBps);
    }

    function setDisputeModule(address nuevo, bytes calldata firmaPQ)
        external
        soloAdminPQ(keccak256(abi.encode("SET_DISPUTE_MODULE", nuevo)), firmaPQ)
    {
        require(nuevo != address(0), "modulo invalido");
        disputeModule = nuevo;
        emit DisputeModuleActualizado(nuevo);
    }

    function setTreasury(address nuevo, bytes calldata firmaPQ)
        external
        soloAdminPQ(keccak256(abi.encode("SET_TREASURY", nuevo)), firmaPQ)
    {
        require(nuevo != address(0), "treasury invalido");
        treasury = nuevo;
        emit TreasuryActualizado(nuevo);
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
