// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EscrowInstance.sol";
import "../src/DisputeModule.sol";
import "../src/MockUSDT.sol";

contract EscrowInstanceTest is Test {
    MockUSDT usdt;
    DisputeModule dm;
    EscrowInstance escrow;

    address admin     = makeAddr("admin");
    address arbitro   = makeAddr("arbitro");
    address agente    = makeAddr("agente");
    address vendedor  = makeAddr("vendedor");
    address comprador = makeAddr("comprador");
    address treasury  = makeAddr("treasury");

    uint256 constant MONTO    = 100e6;
    uint256 constant FEE_BPS  = 500;
    uint256 constant DURACION = 30 minutes;

    function setUp() public {
        usdt = new MockUSDT();
        dm   = new DisputeModule(admin, arbitro);

        usdt.mint(vendedor, MONTO);

        bytes32 refPago = keccak256("orden-uuid-1234");
        escrow = new EscrowInstance(
            vendedor,
            comprador,
            address(usdt),
            address(dm),
            agente,
            MONTO,
            block.timestamp + DURACION,
            refPago,
            FEE_BPS,
            treasury
        );

        vm.prank(vendedor);
        usdt.transfer(address(escrow), MONTO);
    }

    function test_estado_inicial_creada() public view {
        assertEq(uint(escrow.estado()), uint(EscrowInstance.Estado.CREADA));
    }

    function test_activar_escrow() public {
        vm.prank(agente);
        escrow.activarEscrow();
        assertEq(uint(escrow.estado()), uint(EscrowInstance.Estado.ACTIVA));
    }

    function test_solo_agente_puede_activar() public {
        vm.prank(vendedor);
        vm.expectRevert("solo agente autorizado");
        escrow.activarEscrow();
    }

    function test_liberar_por_agente() public {
        vm.prank(agente); escrow.activarEscrow();
        vm.prank(agente); escrow.liberarEscrow();

        uint256 fee = (MONTO * FEE_BPS) / 10000;
        assertEq(usdt.balanceOf(comprador), MONTO - fee);
        assertEq(usdt.balanceOf(treasury),  fee);
        assertEq(uint(escrow.estado()), uint(EscrowInstance.Estado.COMPLETADA));
    }

    function test_liberar_por_vendedor() public {
        vm.prank(agente);   escrow.activarEscrow();
        vm.prank(vendedor); escrow.liberarEscrow();

        uint256 fee = (MONTO * FEE_BPS) / 10000;
        assertEq(usdt.balanceOf(comprador), MONTO - fee);
    }

    function test_fee_calculo_correcto() public {
        // 100 USDT * 500 bps / 10000 = 5 USDT de fee (5%)
        vm.prank(agente); escrow.activarEscrow();
        vm.prank(agente); escrow.liberarEscrow();
        assertEq(usdt.balanceOf(treasury),  5_000_000);
        assertEq(usdt.balanceOf(comprador), 95_000_000);
    }

    function test_expirar_orden() public {
        vm.prank(agente); escrow.activarEscrow();
        vm.warp(block.timestamp + DURACION + 1);
        vm.prank(agente); escrow.expirarOrden();

        assertEq(usdt.balanceOf(vendedor), MONTO);
        assertEq(uint(escrow.estado()), uint(EscrowInstance.Estado.EXPIRADA));
    }

    function test_no_expirar_antes_de_deadline() public {
        vm.prank(agente); escrow.activarEscrow();
        vm.prank(agente);
        vm.expectRevert("no ha expirado");
        escrow.expirarOrden();
    }

    function test_no_liberar_si_expirada() public {
        vm.prank(agente); escrow.activarEscrow();
        vm.warp(block.timestamp + DURACION + 1);
        vm.prank(agente); escrow.expirarOrden();

        vm.prank(agente);
        vm.expectRevert("no activo");
        escrow.liberarEscrow();
    }

    function test_abrir_disputa() public {
        vm.prank(agente);    escrow.activarEscrow();
        vm.prank(comprador); escrow.abrirDisputa();
        assertEq(uint(escrow.estado()), uint(EscrowInstance.Estado.DISPUTA));
    }

    function test_solo_disputemodule_resuelve() public {
        vm.prank(agente);    escrow.activarEscrow();
        vm.prank(comprador); escrow.abrirDisputa();

        vm.prank(makeAddr("hacker"));
        vm.expectRevert("solo dispute module");
        escrow.ejecutarResolucion(comprador);
    }

    function test_resolucion_sin_fee() public {
        vm.prank(agente);    escrow.activarEscrow();
        vm.prank(comprador); escrow.abrirDisputa();

        vm.prank(address(dm));
        escrow.ejecutarResolucion(comprador);

        assertEq(usdt.balanceOf(comprador), MONTO);
        assertEq(usdt.balanceOf(treasury),  0);
        assertEq(uint(escrow.estado()), uint(EscrowInstance.Estado.RESUELTA));
    }
}
