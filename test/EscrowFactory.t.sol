// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EscrowFactory.sol";
import "../src/EscrowInstance.sol";
import "../src/DisputeModule.sol";
import "../src/MockUSDT.sol";

contract EscrowFactoryTest is Test {
    event OrdenCreada(
        address indexed instancia,
        address indexed vendedor,
        address indexed comprador,
        uint256 monto,
        bytes32 referenciaPago,
        uint256 deadline
    );

    MockUSDT usdt;
    DisputeModule dm;
    EscrowFactory factory;

    address admin     = makeAddr("admin");
    address arbitro   = makeAddr("arbitro");
    address agente    = makeAddr("agente");
    address vendedor  = makeAddr("vendedor");
    address comprador = makeAddr("comprador");
    address treasury  = makeAddr("treasury");

    uint256 constant MONTO   = 100e6;
    uint256 constant FEE_BPS = 500;

    function setUp() public {
        usdt    = new MockUSDT();
        dm      = new DisputeModule(admin, arbitro);
        factory = new EscrowFactory(admin, address(usdt), address(dm), treasury, FEE_BPS);

        vm.prank(admin);
        factory.setAgentePrincipal(agente);

        usdt.mint(vendedor, 1000e6);
        vm.prank(vendedor);
        usdt.approve(address(factory), type(uint256).max);
    }

    function test_crear_orden_emite_evento() public {
        bytes32 ref = keccak256("uuid-001");
        vm.expectEmit(false, true, true, false);
        emit OrdenCreada(address(0), vendedor, comprador, MONTO, ref, 0);
        vm.prank(vendedor);
        factory.crearOrden(comprador, MONTO, ref, 30 minutes);
    }

    function test_crear_orden_transfiere_usdt() public {
        bytes32 ref = keccak256("uuid-002");
        vm.prank(vendedor);
        address inst = factory.crearOrden(comprador, MONTO, ref, 30 minutes);

        assertEq(usdt.balanceOf(inst),     MONTO);
        assertEq(usdt.balanceOf(vendedor), 900e6);
    }

    function test_instancia_valida_registrada() public {
        vm.prank(vendedor);
        address inst = factory.crearOrden(comprador, MONTO, keccak256("uuid-003"), 30 minutes);
        assertTrue(factory.esInstanciaValida(inst));
    }

    function test_instancia_tiene_datos_correctos() public {
        vm.prank(vendedor);
        address addr = factory.crearOrden(comprador, MONTO, keccak256("uuid-004"), 30 minutes);
        EscrowInstance inst = EscrowInstance(addr);

        assertEq(inst.vendedor(),  vendedor);
        assertEq(inst.comprador(), comprador);
        assertEq(inst.monto(),     MONTO);
        assertEq(inst.feeBps(),    FEE_BPS);
        assertEq(inst.treasury(),  treasury);
        assertEq(inst.agente(),    agente);
    }

    function test_no_crear_sin_agente_configurado() public {
        EscrowFactory f2 = new EscrowFactory(admin, address(usdt), address(dm), treasury, FEE_BPS);
        usdt.mint(vendedor, MONTO);
        vm.prank(vendedor);
        usdt.approve(address(f2), MONTO);

        vm.prank(vendedor);
        vm.expectRevert("agente no configurado");
        f2.crearOrden(comprador, MONTO, keccak256("ref"), 30 minutes);
    }

    function test_no_crear_deadline_muy_corto() public {
        vm.prank(vendedor);
        vm.expectRevert("deadline muy corto");
        factory.crearOrden(comprador, MONTO, keccak256("ref"), 5 minutes);
    }

    function test_no_comprador_igual_vendedor() public {
        vm.prank(vendedor);
        vm.expectRevert("comprador == vendedor");
        factory.crearOrden(vendedor, MONTO, keccak256("ref"), 30 minutes);
    }

    function test_actualizar_fee() public {
        vm.prank(admin);
        factory.setFeeBps(300);
        assertEq(factory.feeBps(), 300);
    }

    function test_fee_maximo_10_porciento() public {
        vm.prank(admin);
        vm.expectRevert("fee maximo 10%");
        factory.setFeeBps(1001);
    }

    function test_solo_admin_actualiza_fee() public {
        vm.prank(vendedor);
        vm.expectRevert();
        factory.setFeeBps(100);
    }
}
