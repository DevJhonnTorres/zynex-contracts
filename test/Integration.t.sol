// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EscrowFactory.sol";
import "../src/EscrowInstance.sol";
import "../src/DisputeModule.sol";
import "../src/MockUSDT.sol";

contract IntegrationTest is Test {
    MockUSDT usdt;
    DisputeModule dm;
    EscrowFactory factory;

    address admin     = makeAddr("admin");
    address arbitro   = makeAddr("arbitro");
    address agente    = makeAddr("agente");
    address vendedor  = makeAddr("vendedor");
    address comprador = makeAddr("comprador");
    address treasury  = makeAddr("treasury");

    uint256 constant MONTO   = 200e6;
    uint256 constant FEE_BPS = 500;

    function setUp() public {
        usdt    = new MockUSDT();
        dm      = new DisputeModule(admin, arbitro);
        factory = new EscrowFactory(admin, address(usdt), address(dm), treasury, FEE_BPS);

        vm.prank(admin);
        factory.setAgentePrincipal(agente);

        usdt.mint(vendedor, 10_000e6);
        vm.prank(vendedor);
        usdt.approve(address(factory), type(uint256).max);
    }

    function _crearYActivar(bytes32 ref) internal returns (EscrowInstance) {
        vm.prank(vendedor);
        address addr = factory.crearOrden(comprador, MONTO, ref, 30 minutes);
        vm.prank(agente);
        EscrowInstance(addr).activarEscrow();
        return EscrowInstance(addr);
    }

    function test_flujo_completo_liberacion() public {
        EscrowInstance inst = _crearYActivar(keccak256("ord-1"));
        vm.prank(agente);
        inst.liberarEscrow();

        uint256 fee = (MONTO * FEE_BPS) / 10000;
        assertEq(usdt.balanceOf(comprador), MONTO - fee);
        assertEq(usdt.balanceOf(treasury),  fee);
        assertEq(uint(inst.estado()), uint(EscrowInstance.Estado.COMPLETADA));
    }

    function test_expiracion_devuelve_vendedor() public {
        EscrowInstance inst = _crearYActivar(keccak256("ord-2"));
        uint256 balAntes = usdt.balanceOf(vendedor);

        vm.warp(block.timestamp + 31 minutes);
        vm.prank(agente);
        inst.expirarOrden();

        assertEq(usdt.balanceOf(vendedor), balAntes + MONTO);
        assertEq(uint(inst.estado()), uint(EscrowInstance.Estado.EXPIRADA));
    }

    function test_disputa_2de3_comprador_gana() public {
        EscrowInstance inst = _crearYActivar(keccak256("ord-3"));
        vm.prank(comprador); inst.abrirDisputa();
        vm.prank(comprador); dm.registrarVoto(address(inst), comprador);
        vm.prank(arbitro);   dm.registrarVoto(address(inst), comprador);

        assertEq(usdt.balanceOf(comprador), MONTO);
        assertEq(uint(inst.estado()), uint(EscrowInstance.Estado.RESUELTA));
    }

    function test_disputa_2de3_vendedor_gana() public {
        EscrowInstance inst = _crearYActivar(keccak256("ord-4"));
        uint256 balAntes = usdt.balanceOf(vendedor);

        vm.prank(comprador); inst.abrirDisputa();
        vm.prank(vendedor);  dm.registrarVoto(address(inst), vendedor);
        vm.prank(arbitro);   dm.registrarVoto(address(inst), vendedor);

        assertEq(usdt.balanceOf(vendedor), balAntes + MONTO);
        assertEq(uint(inst.estado()), uint(EscrowInstance.Estado.RESUELTA));
    }

    function test_no_liberar_si_expirada() public {
        EscrowInstance inst = _crearYActivar(keccak256("ord-5"));
        vm.warp(block.timestamp + 31 minutes);
        vm.prank(agente); inst.expirarOrden();

        vm.prank(agente);
        vm.expectRevert("no activo");
        inst.liberarEscrow();
    }

    function test_reentrancy_guard_doble_liberacion() public {
        EscrowInstance inst = _crearYActivar(keccak256("ord-6"));
        vm.prank(agente); inst.liberarEscrow();

        vm.prank(agente);
        vm.expectRevert("no activo");
        inst.liberarEscrow();
    }

    function test_solo_agente_puede_expirar() public {
        EscrowInstance inst = _crearYActivar(keccak256("ord-7"));
        vm.warp(block.timestamp + 31 minutes);

        vm.prank(makeAddr("random"));
        vm.expectRevert("solo agente autorizado");
        inst.expirarOrden();
    }

    function test_solo_dispute_module_resuelve() public {
        EscrowInstance inst = _crearYActivar(keccak256("ord-8"));
        vm.prank(comprador); inst.abrirDisputa();

        vm.prank(makeAddr("hacker"));
        vm.expectRevert("solo dispute module");
        inst.ejecutarResolucion(comprador);
    }

    function test_multiples_ordenes_independientes() public {
        EscrowInstance inst1 = _crearYActivar(keccak256("ord-9a"));
        EscrowInstance inst2 = _crearYActivar(keccak256("ord-9b"));

        vm.prank(agente); inst1.liberarEscrow();

        vm.warp(block.timestamp + 31 minutes);
        vm.prank(agente); inst2.expirarOrden();

        assertEq(uint(inst1.estado()), uint(EscrowInstance.Estado.COMPLETADA));
        assertEq(uint(inst2.estado()), uint(EscrowInstance.Estado.EXPIRADA));
    }
}
