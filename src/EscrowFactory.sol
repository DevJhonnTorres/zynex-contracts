// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./EscrowInstance.sol";

contract EscrowFactory is AccessControl {
    using SafeERC20 for IERC20;

    address public usdtToken;
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

    constructor(
        address admin,
        address usdt_,
        address disputeModule_,
        address treasury_,
        uint256 feeBps_
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        usdtToken     = usdt_;
        disputeModule = disputeModule_;
        treasury      = treasury_;
        feeBps        = feeBps_;
    }

    function crearOrden(
        address comprador,
        uint256 monto,
        bytes32 referenciaPago,
        uint256 duracionSegundos
    ) external returns (address instancia) {
        require(monto > 0,                       "monto invalido");
        require(comprador != address(0),          "comprador invalido");
        require(comprador != msg.sender,          "comprador == vendedor");
        require(duracionSegundos >= 15 minutes,   "deadline muy corto");
        require(agentePrincipal != address(0),    "agente no configurado");

        uint256 deadline = block.timestamp + duracionSegundos;

        EscrowInstance nueva = new EscrowInstance(
            msg.sender,
            comprador,
            usdtToken,
            disputeModule,
            agentePrincipal,
            monto,
            deadline,
            referenciaPago,
            feeBps,
            treasury
        );

        instancia = address(nueva);
        esInstanciaValida[instancia] = true;

        IERC20(usdtToken).safeTransferFrom(msg.sender, instancia, monto);

        emit OrdenCreada(instancia, msg.sender, comprador, monto, referenciaPago, deadline);
    }

    function setAgentePrincipal(address nuevo) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(nuevo != address(0), "agente invalido");
        agentePrincipal = nuevo;
        emit AgenteActualizado(nuevo);
    }

    function setFeeBps(uint256 nuevoBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(nuevoBps <= 1000, "fee maximo 10%");
        feeBps = nuevoBps;
        emit FeeActualizado(nuevoBps);
    }

    function setDisputeModule(address nuevo) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(nuevo != address(0), "modulo invalido");
        disputeModule = nuevo;
    }

    function setTreasury(address nuevo) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(nuevo != address(0), "treasury invalido");
        treasury = nuevo;
        emit TreasuryActualizado(nuevo);
    }
}
